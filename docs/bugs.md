# Bug Log

Bugs found by the testbench, in the order found.

## 1. Test master raised valid in the cycle after reset

| | |
| --- | --- |
| Stage | 0 |
| Found by | `handshake_sva.a_valid_low_after_reset` in `tb_mem_model` |
| Seed | 3 (all three memory configs) |
| Component | Testbench (`tb_mem_model` master), not RTL |

**Symptom.** `mem_if.req: valid high in the cycle after reset` at 55 ns. The test itself printed `TEST PASSED`; the run failed only because the regression script treats any `Error:` line as a failure.

**Root cause.** The master waited `repeat (5) @(posedge clk)`, released `rst`, then waited `@(lif.mst_cb)` for one idle cycle. Both events fire on the same edge, so the clocking-block wait returned in the same timestep instead of one cycle later. When the seed chose a zero-cycle gap before the first request, `req_valid` rose in the cycle after the last reset cycle.

**Fix.** The master waits only on the clocking block (`repeat (5) @(lif.mst_cb)`). One process should never mix `@(posedge clk)` and `@(clocking block)`.
