# Coherent Cache & Memory Subsystem

A SystemVerilog project for two L1 data caches that share memory using **MESI coherence**. The CPU requesters and main memory are simulated; the caches and interconnect are intended to be synthesizable.

## The design

| Part | Plan |
| --- | --- |
| L1 caches | Two private, 2-way caches; 512 bytes each |
| Cache lines | 16 bytes; 16 sets per cache |
| CPU interface | Aligned 32-bit loads and stores |
| Writes | Write-back and write-allocate |
| Replacement | One LRU bit per set |
| Coherence | MESI on a shared snooping bus |
| Memory link | 32-bit AXI4-style, four-beat bursts |
| FPGA target | Nexys A7-100T; Vivado 2025.2 ML Edition |

**Why this setup?** One cache teaches hits, misses, and eviction. A second cache adds the harder problem: keeping two copies of the same address consistent. The small sizes keep the RTL manageable while still covering real cache behavior.

## Documentation

- [System architecture](docs/system_architecture.md) — what connects to what, and the MESI states
- [Inside an L1 cache](docs/l1_microarchitecture.md) — storage, datapath, and address breakdown
- [Design choices](docs/design_decisions.md) — why we chose MESI, LRU, write-back, and the bus
- [Transaction examples](docs/transaction_examples.md) — two common cache-to-cache operations
- [Coherence ordering](docs/coherence_ordering.md) — how simultaneous requests are handled
- [Interfaces](docs/interfaces.md) — proposed signals and memory transactions
- [Scope](docs/requirements.md) — features we plan to implement

Editable diagrams are in [diagrams/coherent_cache_system.drawio](diagrams/coherent_cache_system.drawio); Mermaid sources are in `diagrams/`.

`rtl/`, `sim/`, `verification/`, and `scripts/` are reserved for implementation. [Verification notes](docs/verification_plan.md) are kept separately.

**Status:** design documented; RTL and measurements not started. The 100 MHz clock is a goal, not an achieved result.
