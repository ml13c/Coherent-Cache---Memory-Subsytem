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

## Open the diagrams

1. **Editable visual diagrams**: open `diagrams/coherent_cache_system.drawio` at [diagrams.net](https://app.diagrams.net/). This contains multiple diagram pages.
2. **GitHub-rendered diagrams**: browse `docs/system_architecture.md` and `docs/verification_plan.md` on GitHub (Mermaid diagrams render inside Markdown).
3. **Edit diagram source**: the separate `.mmd` files in `diagrams/` can be edited in VS Code or pasted into [Mermaid Live](https://mermaid.live/).
4. **Fast image previews**: `diagrams/system_architecture_preview.png` and `diagrams/mesi_state_preview.png`.

## Read in this order

1. `docs/system_architecture.md` — final architecture and diagrams.
2. `docs/requirements.md` — what must be true for the project to count as complete.
3. `docs/interfaces.md` — external handshakes and internal protocol contracts.
4. `docs/verification_plan.md` — how correctness will be proven.
5. `docs/design_decisions.md` — decisions, assumptions, and intentionally excluded features.

## Repo structure when RTL development begins

```text
rtl/                       # synthesizable controller, MESI, arbitration, adapter
sim/                       # independent memory/CPU models, smoke tests
verification/uvm/          # UVM environment (simulator support validated separately)
verification/assertions/   # SVA safety/protocol checks
docs/                      # this end-goal design specification
scripts/                   # reproducible simulation and synth commands
diagrams/                  # editable diagrams, Mermaid sources
```

**Boundary:** the UVM testbench is not synthesized. Simulated CPU requesters are not full CPUs. “AXI4-style” is a planned burst-compatible interface, *not* a claim of protocol compliance before implementation and verification.
