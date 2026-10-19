# Why we chose this design

This is the target architecture, not the only way to build a cache.

| Choice | Reason | Tradeoff |
| --- | --- | --- |
| **Two private L1 caches** | Makes cache coherence necessary without needing full CPU cores | More control logic than a single cache |
| **16 sets, 2 ways, 16-byte lines** | Small enough to inspect while still showing set conflicts | Tiny capacity compared with a real CPU |
| **Write-back** | Avoids a memory write on every store | Dirty lines need writeback on eviction or sharing |
| **Write-allocate** | A write miss fetches the line so later accesses can hit | A store may require a full line fetch |
| **LRU replacement** | A simple way to choose a victim based on recent use | One bit works for 2 ways, not for arbitrary associativity |
| **MESI** | Covers clean sharing, private ownership, and dirty ownership | Requires snoops, invalidations, and transient wait states |
| **Round-robin snooping bus** | Gives both caches a turn and keeps ownership ordered | Only one coherence transaction at once |
| **Write back M before sharing** | Both Shared copies and memory agree on the data | Extra memory traffic compared with an Owned-state protocol |
| **AXI4-style bursts** | Moves a whole line in four standard-size transfers | Our first adapter won't support every AXI feature |
| **Simulated CPUs and memory** | Keeps the project focused on RTL cache design | Full on-board operation would need more modules |

The FPGA target is **Nexys A7-100T**, with **100 MHz as an initial goal**. We will adjust pipelining if the actual memory implementation needs it.
