# Architecture Decision Log

**Document:** ADR-001 | **Version:** 0.2

| Decision | Rationale | Revisit if... |
| --- | --- | --- |
| Two private caches, not a full CPU | Focuses effort on RTL/DV and coherent memory hierarchy | Integrating a processor becomes a separate stretch goal |
| Two-way, 16 sets, 16-byte line | Makes all corner cases tractable; address split is easy to audit | Resource mapping/timing demands new parameters |
| Full MESI, not MSI | Exercises E optimization, sharing and ownership changes | Coherence effort must be reduced to demonstrable subset |
| Central snooping fabric, not directory | Fewer agents and deterministic arbitration for a 2-cache design | Scaling beyond two caches becomes a goal |
| One transaction in fabric at a time | Keeps bus ownership ordering deterministic; local cache hits still need snoop interlocks | Throughput optimization is intentionally added later |
| Snoop-priority same-cycle tie / drain older local request | Prevents a local M/E store from passing an already active snoop, without silently dropping accepted writes | Adding a pipelined local/snoop scoreboard becomes feasible |
| Retry invalidated queued BusUpgr | A pending S upgrade can be invalidated before it reaches the front of the coherence bus | More complex retry-free queue design is separately proven |
| Flush M owner before downgrade/invalidate | Simplifies latest-data source and memory semantics at cost of extra traffic; prevents dirty sharing without Owned state | Introducing MOESI or direct dirty forwarding becomes a goal |
| Aligned 32-bit operations only | Avoids byte masks, unaligned split access and endianness corner cases | ISA integration requires byte/halfword accesses |
| AXI4-style subset | Provides real burst-handshake design work without broad AXI coverage claims | Compliance is explicitly required |
| Initial simulator XSIM, UVM simulator TBD | Early RTL sim is available in Vivado 2025.2; UVM capabilities must be validated | Simulator support is tested on the actual machine |
| 100-MHz timing goal, not promise | Gives a measurable FPGA constraint | Implementation shows different achievable frequency |
| Synthesizable cache core vs simulated backing memory | Makes RTL simulation, UVM and on-FPGA timing analysis feasible independently | A hardware BRAM slave + test traffic are implemented |
| MESI metadata encodes validity and dirtiness | MESI=I means invalid; MESI=M means dirty so extra valid/dirty bits are redundant | Enhancing coherence state representation |

## Open design questions

- Which UVM-capable simulator and UVM library will pass a campus-license smoke test?
- Are tag/data arrays inferred as block RAM or distributed storage under the chosen cycle-latency interface?
- What error response, if any, should a memory AXI burst failure produce to the CPU?
- Which exact performance-counter widths and overflow behavior should be implemented?

These do **not** change the high-level end goal, but they must be decided before signing off the corresponding RTL.
