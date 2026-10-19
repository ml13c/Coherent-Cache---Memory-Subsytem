# Planned scope

The finished subsystem should have:

- Two coherent 2-way L1 data caches with 16 sets and 16-byte lines
- Aligned 32-bit loads and stores
- Read hits/misses, write-back, write-allocate, and LRU eviction
- MESI ownership, snoops, and invalidation across the two caches
- Round-robin arbitration with one active coherence transaction
- A limited AXI4-style adapter for four-beat line transfers
- A synthesizable RTL subsystem that can be targeted in Vivado

Not planned: a complete CPU, instruction caches, L2/L3, virtual memory, DMA coherence, or out-of-order requests. The backing memory and CPU traffic sources start as simulation components.
