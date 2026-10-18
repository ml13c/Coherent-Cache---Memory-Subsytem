# Coherence Ordering, Race Handling, and Invariants

**Document:** COH-001 | **Version:** 0.2 | **Status:** Proposed end-goal behavioral contract

This document specifies **how a cache handles a local CPU access arriving near a peer snoop**. A shared bus that serializes *bus transactions* does **not** automatically serialize **local cache hits**; the L1 controller must handle that boundary explicitly.

## A. Stable-state ownership invariants

For **the same 16-byte line address** (not merely the same set or index), the only legal stable two-cache pairs are:

| Cache 0 | Cache 1 | Why |
| --- | --- | --- |
| I | I | Neither cache holds the line |
| M | I | Exactly one dirty owner |
| I | M | Exactly one dirty owner |
| E | I | Exactly one clean exclusive owner |
| I | E | Exactly one clean exclusive owner |
| S | I | One clean shared-state copy is permitted |
| I | S | One clean shared-state copy is permitted |
| S | S | Both caches hold identical clean data |

Any pair with **M and another non-I copy**, or **E and another non-I copy**, is prohibited. (M/M, M/S, M/E, E/E, E/S and their reversals are illegal.) `S/S` must agree on line data, and both copies must agree with backing memory whenever memory is clean. These rules are checked at **stable transaction boundaries**; controller transient/busy states are monitored separately.

## B. CPU vs snoop ordering contract

1. **Accepted CPU operations are not necessarily completed operations.** `req_valid && req_ready` accepts a request; it does not alone establish when a store becomes visible. The cache handles at most one accepted-but-not-completed CPU request at a time.
2. **Snoop wins a same-cycle acceptance tie.** If `snoop_valid` targets the same cache and a local CPU request would otherwise be accepted on the same clock edge, the cache lowers `req_ready`. For this starter design, all CPU accepts may conservatively stall while handling any snoop (simpler than per-line forwarding).
3. **Drain earlier accepted conflicting operations before snoop acknowledgement.** If a store to the snooped line was accepted before the snoop, complete its local word update **before** returning snoop data or acknowledgement. Never return an older version of the line.
4. **Hold a line stable during an in-flight snoop.** Lock/restrict accesses to a line while fetching the latest data, flushing Modified data, downgrading or invalidating. Do not let an E/M write hit bypass a snoop that has already started.
5. **Make ownership grants indivisible.** After a peer invalidation or dirty flush acknowledgement, the fabric grants ownership; the requester cannot use the line as M until the grant and local store update. Never grant until snoop acknowledgements and required memory completion have occurred.
6. **Revalidate a pending upgrade.** While `BusUpgr` waits for the fabric, a previous snoop might invalidate the pending S line. Check tag+state again when the grant would commit. If no longer S for that line, abandon/retry using `BusRdX` rather than updating an invalid line. The pending transaction interface must support the required retry/cancellation handshake.
7. **Fabric ordering is deterministic.** Two requesting L1s are selected via round-robin arbitration with **at most one coherence transaction active**. Unrelated local hits can be globally unordered; conflicting operations must produce a legal single-copy view and pass a linearizability/order check.

**Architectural store commit point:** for an E/M hit, the local data-array update; for an S/I store, after serialized ownership grant **and** local data-array update. The store response follows commit. Snoop responses reflect all previously committed stores and any earlier accepted same-line store that must be drained per rule 3.

## C. Required transient controller behavior

MESI diagrams show four **stable** states (I, S, E, M), not the complete controller FSM. The RTL needs extra **busy/transient** control states such as `WAIT_ARB`, `WAIT_SNOOP`, `WAIT_WRITEBACK`, `WAIT_REFILL`, `WAIT_UPGRADE_GRANT`, `RESPOND` and `RETRY`. Exact encoding is up to the implementation; the behavior above is mandatory. Defer line eviction or conflicting local access while ownership is unresolved.

## D. Memory writeback policy

This design intentionally chooses **writeback-before-sharing** rather than a separate dirty Owned state. When a peer in M is read by another core:

1. Obtain the latest 16-byte line from the M owner.
2. Finish writing the line to backing memory.
3. Downgrade old M owner to S, receive snoop ack, grant the requester S with the same latest data.

For peer `BusRdX`, flush M then invalidate it and grant the requester M after obtaining the latest data. For dirty eviction, finish writeback before reusing the victim. A local M owner may keep memory stale until such an event. This deliberately favors simple verification over lower coherence traffic.

## E. What to verify

- For each line, no prohibited stable MESI pair ever occurs.
- A snoop acknowledgement may not precede the visibility of a prior accepted store to the same line.
- Peer reads never return stale data after a store completed before the read's ordered operation.
- A write upgrade cannot commit if the presumed S line was invalidated while waiting.
- Memory writeback completes before an M owner downgrades or invalidates in this chosen policy.
- Every accepted request gets exactly one response unless canceled by specified reset behavior.

**Verification independence:** expected read data is generated from CPU request payloads and the legal observed operation order—not copied from the DUT's returned value or read-data array. Internal commit/grant instrumentation may establish ordering but must never supply *expected data* to the reference model.

```mermaid
sequenceDiagram
    autonumber
    participant A as CPU0
    participant C0 as L1 cache 0 (M)
    participant F as Coherence fabric
    participant C1 as L1 cache 1
    A->>C0: store X accepted; not yet committed
    C1->>F: BusRd X
    F->>C0: snoop BusRd X
    Note over C0: Block newly accepted conflicting accesses; finish prior accepted store
    C0->>C0: commit accepted store payload to X
    C0-->>F: snoop M hit + latest dirty line data
    F->>F: serialize dirty writeback and downgrade
    F->>C0: commit downgrade M to S
    C0-->>F: snoop-complete ack
    F-->>C1: grant latest X as S
    Note over C0,C1: The peer cannot observe data older than the earlier committed store
```
