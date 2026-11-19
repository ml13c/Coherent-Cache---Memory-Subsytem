# Verification

How the design is checked. Sections for parts not built yet are marked with the stage that builds them.

## Structure

| Path | Contents |
| --- | --- |
| `tb/env/line_if.sv` | Line channel interface, one clocking block per side |
| `tb/mem/mem_pkg.sv` | Memory model class and the initial-content function |
| `tb/sva/` | Protocol assertions |
| `tb/tests/` | Test tops |
| `sim/` | File list, run and regression scripts |

## Memory Model
The memory model is the slave side of one line channel. It accepts one request at a time, holds `req_ready` low while busy and raises it randomly while idle. Each response waits a random latency in `[min_lat, max_lat]` cycles; latency 0 means the response is valid in the cycle right after acceptance.

A line that was never written reads back a pattern computed from its address: each word holds its own byte address with the upper 16 bits inverted. A reference model can predict any line without sharing state with the memory, and a bug that routes an address into a data path cannot read back a matching value. A WriteBack response carries random data, so a master that uses it gets garbage.

## Assertions
`handshake_sva` checks one valid/ready channel. `line_channel_sva` applies it to both directions of a line channel and adds pairing rules.

| Assertion | Rule |
| --- | --- |
| `a_valid_held` | Once valid is high, it stays high until the handshake |
| `a_payload_stable` | Payload holds while `valid && !ready` |
| `a_ctrl_known` | `valid` and `ready` are never X or Z out of reset |
| `a_valid_low_after_reset` | `valid` is low in the cycle after a reset cycle |
| `a_one_outstanding` | A request is accepted only when none is outstanding |
| `a_resp_has_req` | A response is valid only while a request is outstanding |
| `a_cmd_known` | Command and address are not X while the request is valid |

"Valid must not depend on ready" is a combinational-path rule that a cycle-based assertion cannot observe. It is enforced by registering `valid` in the RTL and checked in review.

## Pass/Fail
A run passes only if its log contains `TEST PASSED` and no line starting with `Error` or `Fatal`. The simulator's exit code is not used: xsim exits 0 even after `$fatal`. An assertion failure therefore fails a run even when the test's own checks pass.

## Memory Model Test
`tb_mem_model` drives random BusRd, BusRdX and WriteBack requests from a small hot set and the full address space, with random gaps and random response backpressure. It checks read data against a shadow memory, latency against the configured bounds, and `resp_shared = 0`. A run also fails unless the stress it claims was reached: both latency extremes, stalls on each channel with backpressure enabled, and reads of both written and never-written lines.

| Config | Latency | `req_ready` | `resp_ready` |
| --- | --- | --- | --- |
| `mem_default` | 1–10 | 70% | 60% |
| `mem_fast` | 0 | 100% | 100% |
| `mem_slow` | 5–40 | 20% | 20% |

### Checker Sanity (Mutations)
Each bug was planted in the memory model alone and the test run with seed 1.

| Planted bug | Caught by |
| --- | --- |
| Response data changes while waiting | `a_payload_stable`, data check |
| Response valid dropped before handshake | `a_valid_held`, latency check |
| Latency one cycle too long | Latency check |
| Write silently lost | Data check |

## Reference Model, Scoreboard, Coverage

> Planned (Stage 1: reference model. Stage 4: UVM environment, coverage, RTL mutation testing)
