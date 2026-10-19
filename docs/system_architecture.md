# System architecture

Each simulated CPU gets its own L1 cache. Both caches connect to the same memory through a snooping fabric and an AXI-style adapter.

```mermaid
flowchart TB
    subgraph TB[Outside synthesizable RTL - simulation testbench]
      CPU0[CPU requester 0]
      CPU1[CPU requester 1]
      RAM[Shared backing memory model]
    end
    subgraph DUT[Synthesizable coherent-cache RTL subsystem]
      C0[L1 cache 0<br/>2-way, 16 sets, 512 B<br/>tags, data, MESI, LRU, FSM]
      C1[L1 cache 1<br/>2-way, 16 sets, 512 B<br/>tags, data, MESI, LRU, FSM]
      FAB[Snooping coherence fabric<br/>round-robin arbiter, serialization<br/>grants and snoop acknowledgements]
      AXI[32-bit AXI4-style memory adapter<br/>one 4-beat burst at a time]
      PERF[Performance counters]
    end
    CPU0 <-->|request / response| C0
    CPU1 <-->|request / response| C1
    C0 <-->|coherence requests + snoops| FAB
    C1 <-->|coherence requests + snoops| FAB
    FAB <-->|line reads / dirty writebacks| AXI
    AXI <-->|4 x 32-bit beats, handshakes| RAM
    C0 -. local hits / misses / stores .-> PERF
    C1 -. local hits / misses / stores .-> PERF
    FAB -. snoops / invalidations / writebacks .-> PERF
```

## Why it's arranged this way

- **Private L1 caches** make nearby data fast for each CPU, but they can end up holding different copies of the same address.
- **The snooping fabric** broadcasts ownership requests to the other cache. It lets only one coherence transaction use the bus at a time so ownership changes have a clear order.
- **The memory adapter** moves a whole 16-byte cache line in four 32-bit transfers. The caches work with lines; the CPUs work with words.
- **Simulated CPUs and memory** let us focus on the cache hardware without building a processor or external RAM controller first.

## MESI states

| State | Meaning |
| --- | --- |
| **M** — Modified | This cache has the only current copy. Memory can be out of date. |
| **E** — Exclusive | This cache has the only copy, and it matches memory. |
| **S** — Shared | Other caches may have the same clean line. |
| **I** — Invalid | The entry cannot supply data. |

```mermaid
stateDiagram-v2
    direction LR
    [*] --> I: reset
    state "Invalid (I)" as I
    state "Shared (S)" as S
    state "Exclusive (E)" as E
    state "Modified (M)" as M
    I --> E: BusRd fill, no peer copy
    I --> S: BusRd fill, peer has copy
    I --> M: BusRdX fill and store
    E --> M: local store hit
    E --> S: peer BusRd
    E --> I: peer BusRdX or eviction
    S --> M: BusUpgr, invalidation ack, grant
    S --> I: peer BusRdX or BusUpgr
    S --> I: clean eviction
    M --> S: peer BusRd after writeback
    M --> I: peer BusRdX after writeback
    M --> I: dirty eviction after writeback
    S --> S: local read hit
    E --> E: local read hit
    M --> M: local hit
```

**Why MESI?** A cache can write directly when it has **E** or **M**, without sending an ownership request every time. A write to **S** must first invalidate other copies. MESI captures both behaviors without the extra *Owned* state of MOESI.

This is a diagram of the **stable line states**. The controller will also have temporary wait states while a transfer or invalidation is in progress.

See [transaction examples](transaction_examples.md) for an actual read and write exchange between the caches.
