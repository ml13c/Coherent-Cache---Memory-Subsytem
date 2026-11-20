# Verification

How the design is checked. Sections for parts not built yet are marked with the stage that builds them.

## Structure

| Path | Contents |
| --- | --- |
| `tb/env/line_if.sv` | Line channel interface, one clocking block per side |
| `tb/env/cpu_if.sv` | CPU port interface, driver and monitor clocking blocks |
| `tb/mem/mem_pkg.sv` | Memory model class and the initial-content function |
| `tb/model/model_pkg.sv` | Reference model of one cache |
| `tb/sva/` | Protocol assertions, bound into `l1_cache` |
| `tb/tests/` | Test tops |
| `sim/` | File list, run and regression scripts |

## Memory Model
The memory model is the slave side of one line channel. It accepts one request at a time, holds `req_ready` low while busy and raises it randomly while idle. Each response waits a random latency in `[min_lat, max_lat]` cycles; latency 0 means the response is valid in the cycle right after acceptance.

A line that was never written reads back a pattern computed from its address: each word holds its own byte address with the upper 16 bits inverted. A reference model can predict any line without sharing state with the memory, and a bug that routes an address into a data path cannot read back a matching value. A WriteBack response carries random data, so a master that uses it gets garbage.

## Reference Model
`cache_model` is called once per accepted CPU request, in acceptance order, and makes two independent predictions:

1. **Load value.** What the load must return, taken from architectural memory only. It does not depend on cache contents or the replacement policy, so a wrong victim choice cannot make it agree with a wrong answer.
2. **Access.** Hit or miss, the expected fill, and the line evicted, from a shadow copy of the cache's tags. The test compares this with the requests seen on the memory channel.

## Assertions
`handshake_sva` checks one valid/ready channel. `line_channel_sva` applies it to both directions of a line channel and adds pairing rules. `cpu_port_sva` applies it to the CPU request and checks that each response is a single pulse for exactly one accepted request and that addresses are word-aligned. Both are attached to `l1_cache` with `bind`.

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

Warnings fail a run too: any compile or elaborate warning, and any simulation warning after the test's `RESET:` line. The one exemption is before reset release, when the FSM state is still X and `unique case` warns. After reset, the same warning means the FSM reached an X or unlisted state. A test that prints no `RESET:` line gets no exemption.

### Checker Sanity (Pass/Fail Rule)
Each case was planted alone and the test run with seed 1.

| Planted | Expected | Result |
| --- | --- | --- |
| `$warning` after `RESET:` in `tb_l1_read` | Fail | Fail |
| `$warning` before `RESET:` in `tb_l1_read` | Pass | Pass |
| `void'($value$plusargs(...))` (elaborate warning) | Fail | Fail |
| `$warning` in `tb_mem_model` (no `RESET:` line) | Fail | Fail |

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

## Load Test (Stage 1)
`tb_l1_read` runs a directed sequence, then random loads. The directed sequence covers a cold miss, a hit, a hit to another word of the line, a conflict miss 2 KiB away, a re-miss, and back-to-back hits; its hit/miss pattern is also checked against a fixed list, which validates the reference model itself.

Random loads mix four address modes: hot lines (hits), same index with a new tag (conflict misses), sequential words, and uniform. Half of the conflict-mode tags differ from the previous tag in exactly one bit, so a tag compare that ignores any single bit fails. About half the loads are issued without waiting for the previous response.

Each load is checked for data, for a 1-cycle response on a hit, and for exactly one BusRd of the predicted line on a miss and none on a hit. A run fails unless hits, cold misses, conflict misses and back-to-back requests all occurred, and memory saw one read per miss and no writes. It runs against the three memory configs above.

### Checker Sanity (RTL Mutations)
Each bug was planted in `cache_ctrl` alone and the test run with seed 1, 500 random loads.

| Planted bug | Caught by |
| --- | --- |
| Hit returns word 0 of the line | Data check |
| Hit ignores line state | `a_resp_known` (X), watchdog |
| Fill writes the tag to the wrong set | Traffic check, hit latency check |
| Fill returns word 0 of the line | Data check |
| Tag compare ignores bit 0 | Traffic check, data check |
| Tag compare ignores bit 20 | Traffic check, data check |
| REQ leaves without waiting for ready | `a_valid_held`, watchdog |
| Fill installs the line as I | Traffic check, hit latency check |

## Scoreboard, Coverage

> Planned (Stage 4: UVM environment, functional coverage, full mutation testing)
