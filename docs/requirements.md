# Final-System Requirements and Acceptance Criteria

**Document:** REQ-001 | **Version:** 0.1 | **State:** Planned, not implemented

| ID | Requirement | Objective acceptance evidence |
| --- | --- | --- |
| REQ-001 | Two independent 32-bit CPU requester ports | Simultaneous requests to both ports pass self-checking tests |
| REQ-002 | Two private 2-way, 16-set, 16-byte-line caches | Elaboration/synthesis confirms intended parameters; mapping test checks address fields |
| REQ-003 | Correct aligned 32-bit read and write operations | Scoreboard checks returned read words and acknowledged stores |
| REQ-004 | Read hit and read miss handling | Directed tests for cold hit/miss, set conflicts, refill/eviction |
| REQ-005 | Write-back, write-allocate | Write miss allocates M; backing-memory test shows delayed update until writeback |
| REQ-006 | True 2-way LRU | Two-line history and third conflicting line evicts least recently accessed way |
| REQ-007 | MESI (M/E/S/I) per line | Each state and each critical transition exercised and checked |
| REQ-008 | Correct dual-cache invalidation and sharing | Sharing/upgrade/ownership-transfer tests pass with no stale reads |
| REQ-009 | Flush modified owner on snooped read/ownership transfer | Modified-owner read/write sequences return current values; backing store updated as specified |
| REQ-010 | Single active coherence transaction and fair arbitration | Contention scenario completes both requests and preserves serialized ownership |
| REQ-011 | Ready/valid handshakes and variable memory latency | No lost, repeated or corrupted transactions under randomized stalls |
| REQ-012 | Single outstanding CPU request per port | Accepted requests receive exactly one response; no unsupported request sequence accepted |
| REQ-013 | Memory line transfers through 4 × 32-bit beats | Beat count, order and address consistency checked for reads/writebacks |
| REQ-014 | Reference scoreboard, assertions and functional coverage | Regression exits cleanly; all required scenario coverage bins hit; report attached |
| REQ-015 | FPGA synthesis and timing | Record target part, constraints, resource counts, timing results; 100-MHz goal marked pass/fail |
| REQ-016 | Reproducible build and documentation | README contains tool versions, commands, directory map and honest feature status |

## Performance measurements (report actual results, do not invent them)

- Per-cache read/write hit rate for named traces.
- Mean/maximum observed latency in cycles for hit, clean miss, and dirty miss.
- Dirty writeback count and coherence traffic count.
- Resource utilization (LUTs, FFs, BRAM), WNS/Fmax, and exact FPGA configuration.

## Sign-off checklist

- [ ] All required directed tests pass.
- [ ] Randomized tests pass over documented seeds and memory latencies.
- [ ] SVA safety properties pass with no unreviewed waivers.
- [ ] Coverpoints/transitions defined in `verification_plan.md` are hit.
- [ ] FPGA synthesis is complete and implementation/timing result is recorded.
- [ ] README clearly distinguishes completed features from stretch goals.
