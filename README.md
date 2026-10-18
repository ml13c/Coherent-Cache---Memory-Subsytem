# Coherent Cache & Memory Subsystem

**Architecture-first documentation starter** | Version 0.1 | 2026-10-18

A portfolio RTL / design-verification project planned for **AMD Vivado ML Edition 2025.2** and a Nexys A7-100T (Artix-7) synthesis target. The final architecture is specified here **before RTL implementation**.

> **Status:** Design proposal, not a completed or verified implementation. All quantitative results remain TBD until measured.

## Intended final system

- Two independent simulated CPU requesters, each attached to a private L1 data cache.
- Each cache: 32-bit addresses, 32-bit word accesses, 16 sets, 2 ways, 16-byte lines (**512 bytes/cache**).
- Write-back / write-allocate, true 2-way LRU (one bit per set), MESI line states.
- A central snooping fabric with round-robin arbitration and one coherence transaction active at a time.
- Shared backing-memory model reached by an AXI4-style burst adapter (32-bit data, four beats per 16-byte line).
- SystemVerilog testbench initially; UVM agents, reference scoreboard, assertions, functional coverage as final verification goals.
- Vivado synthesis, utilization, timing, and measured hit/miss and traffic results.
