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

## 2. Conflict-address generator returned X (simulator bug)

| | |
| --- | --- |
| Stage | 1 |
| Found by | `cpu_port_sva.a_addr_aligned` and `a_resp_known`, then the data check, in `tb_l1_read` |
| Seed | 1 |
| Component | Testbench stimulus; root cause in Vivado 2025.2 xsim |

**Symptom.** At 845 ns the CPU port carried an address of `xxxxxX88`; `resp_valid` went X one cycle later and the load check failed. Only the same-index conflict mode produced X.

**Root cause.** The generator picked a new tag with `do t = tag_t'($urandom()); while (t == get_tag(prev));` inside an automatic function. In xsim 2025.2, a `do`-`while` whose body is a single statement without `begin`/`end` never performs the assignment, so `t` stayed X. A standalone test confirmed it: the same loop with `begin`/`end` works.

**Fix.** No loop: `t = get_tag(prev) + nonzero random offset`, which is bounded and always differs. Rule for this code base: a `do`-`while` body always gets `begin`/`end`.
