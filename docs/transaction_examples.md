# Cache transactions

These examples show why the two caches need to communicate. `X` means the same cache-line address in both caches.

## Read from a Modified peer

CPU 0 misses on X, but cache 1 has the newest copy in **M**. Reading directly from memory would return old data, so the fabric gets the line from cache 1. In our design, it writes the line back before both caches move to **S**.

```mermaid
sequenceDiagram
    autonumber
    participant R0 as CPU 0
    participant C0 as L1 0 (I)
    participant F as Fabric
    participant C1 as L1 1 (M)
    participant A as Memory adapter
    participant M as Memory
    R0->>C0: read X
    C0->>F: BusRd X
    F->>C1: snoop BusRd X
    C1-->>F: modified hit and latest line
    F->>A: write back dirty line
    A->>M: four-beat write
    M-->>A: write response
    A-->>F: writeback complete
    F->>C1: downgrade M to S
    C1-->>F: snoop ack
    F-->>C0: latest line, grant S
    C0-->>R0: read data
    Note over C0,C1: Both caches hold clean Shared copies
```

**Result:** both caches have a clean Shared copy. Memory now has the updated line. We chose the writeback-before-sharing approach because it is easier to reason about, although it creates extra memory traffic.

## Write to a Shared line

CPU 0 wants to change X while both caches hold it in **S**. It must first ask for exclusive ownership. The fabric invalidates cache 1 and waits for its acknowledgement before granting the write.

```mermaid
sequenceDiagram
    autonumber
    participant R0 as CPU 0
    participant C0 as L1 0 (S)
    participant F as Fabric
    participant C1 as L1 1 (S)
    R0->>C0: write X
    C0->>F: BusUpgr X
    F->>C1: invalidate X
    C1-->>F: line invalidated, ack
    F-->>C0: ownership grant
    C0->>C0: recheck tag and state
    C0->>C0: update data, mark M
    C0-->>R0: write complete
    Note over C0,C1: If S was lost, retry as a write miss
```

**Result:** cache 0 is **M** and cache 1 is **I**. This prevents cache 1 from later reading an old copy as if it were current. Cache 0 rechecks its own tag and state after the grant in case an earlier snoop changed the entry.

Other cases use the same rules: a read with no peer copy fills **E**; a write miss uses `BusRdX`; an evicted **M** line must be written back.
