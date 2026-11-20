# Verification

How the design is checked. Sections for parts not built yet are marked with the stage that builds them.

## Structure

| Path | Contents |
| --- | --- |
| `tb/env/line_if.sv` | Line channel interface, one clocking block per side |
| `tb/env/cpu_if.sv` | CPU port interface, driver and monitor clocking blocks |
| `tb/mem/mem_pkg.sv` | Memory model class and the initial-content function |
| `tb/model/model_pkg.sv` | Reference model of one cache |
| `tb/sva/` | Protocol assertions bound into `l1_cache`, line-state assertions bound into `tag_array` |
| `tb/tests/` | Test tops |
| `sim/` | File list, run and regression scripts |

## Memory Model
The memory model is the slave side of one line channel. It accepts one request at a time, holds `req_ready` low while busy and raises it randomly while idle. Each response waits a random latency in `[min_lat, max_lat]` cycles; latency 0 means the response is valid in the cycle right after acceptance.

A line that was never written reads back a pattern computed from its address: each word holds its own byte address with the upper 16 bits inverted. A reference model can predict any line without sharing state with the memory, and a bug that routes an address into a data path cannot read back a matching value. A WriteBack response carries random data, so a master that uses it gets garbage.

## Reference Model
`cache_model` is called once per accepted CPU request, in acceptance order, and makes two independent predictions:

1. **Values.** What a load must return, and what a WriteBack must carry, taken from architectural memory: every accepted store applied byte by byte. It does not depend on cache contents or the replacement policy, so a wrong victim choice cannot make it agree with a wrong answer. The byte merge is the model's own code, not the RTL's `merge_line`.
2. **Traffic.** Hit or miss, and the exact memory requests that follow, from a shadow copy of the cache's tags and dirty bits: a WriteBack of the victim if it is dirty, then `BusRd` (load) or `BusRdX` (store) of the line. The test compares this list with the requests seen on the memory channel. A missing request and an extra one both fail.

## Assertions
`handshake_sva` checks one valid/ready channel. `line_channel_sva` applies it to both directions of a line channel and adds pairing rules. `cpu_port_sva` applies it to the CPU request and checks that each response is a single pulse for exactly one accepted request, that addresses are word-aligned and that a store's strobe is not zero. Both are attached to `l1_cache` with `bind`. `tag_state_sva` is bound into `tag_array` and checks every write to a line's state, which is every state change.

| Assertion | Rule |
| --- | --- |
| `a_valid_held` | Once valid is high, it stays high until the handshake |
| `a_payload_stable` | Payload holds while `valid && !ready` |
| `a_ctrl_known` | `valid` and `ready` are never X or Z out of reset |
| `a_valid_low_after_reset` | `valid` is low in the cycle after a reset cycle |
| `a_one_outstanding` | A request is accepted only when none is outstanding |
| `a_resp_has_req` | A response is valid only while a request is outstanding |
| `a_cmd_known` | Command and address are not X while the request is valid |
| `a_strb_nonzero` | A store's strobe is not `0000` |
| `a_no_dirty_overwrite` | An M line is never replaced by another tag; its WriteBack must set it to I first |
| `a_no_s_single` | No line is written to S while one cache runs alone (memory ties `shared` to 0). Removed or replaced in Stage 6 |

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

## L1 Test
`tb_l1` runs a directed sequence, then random requests. Its hit and WriteBack patterns are also checked against fixed lists, which validates the reference model itself.

| Directed (one set) | Shows |
| --- | --- |
| Cold miss, hits, hit to another word, conflict miss 2 KiB away, re-miss, back-to-back hits | Stage 1 load path |
| Store hit on an E line, then a back-to-back load of the same word | E → M, store visible the next cycle |
| Load to the conflicting line | That M line is evicted: WriteBack, then BusRd |
| Store miss, clean victim, strobe `0101` | No WriteBack; BusRdX, two bytes merged into the fill |
| Reload of both written words | Merge correct; the first store survived WriteBack and refetch |
| Store miss, dirty victim, strobe `1000` | WriteBack, then BusRdX |
| Load miss, dirty victim, then a reload | WriteBack, then BusRd; data correct after a second round trip |

Random requests are stores with probability `STORE_PCT` (default 40%) and use a random non-zero strobe. Addresses mix four modes: hot lines (hits), same index with a new tag (conflict misses), sequential words, and uniform. Half of the conflict-mode tags differ from the previous tag in exactly one bit, so a tag compare that ignores any single bit fails. About half the requests are issued without waiting for the previous response.

Each request is checked for:
- load data
- a 1-cycle response on a hit
- the exact memory traffic: a WriteBack (address and data) if the victim was dirty, then BusRd or BusRdX. Nothing on a hit.

A run fails unless the random phase reached load and store hits and misses, cold misses, clean evictions, dirty evictions caused by both loads and stores, back-to-back requests, a WriteBack held by backpressure, and all 15 non-zero strobe patterns (a covergroup grouped as full word, single byte, two contiguous, three contiguous, non-contiguous). Conditions that a store mix cannot reach are skipped: `STORE_PCT=0` instead requires no WriteBack, and `STORE_PCT=100` skips the load conditions. Memory must see one read per miss and one write per dirty eviction.

| Config | `STORE_PCT` | Memory |
| --- | --- | --- |
| `l1` | 40 | default |
| `l1_fast` | 40 | `mem_fast` latency and request ready |
| `l1_slow` | 40 | `mem_slow` latency and request ready |
| `l1_loads` | 0 | default |
| `l1_stores` | 100 | default |

### Checker Sanity (Stage 1 RTL Mutations)
Each bug was planted in `cache_ctrl` alone and the Stage 1 load test run with seed 1, 500 random loads.

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

### Checker Sanity (Stage 2 Mutations)
Each bug was planted alone (in `cache_ctrl`, or in the stimulus for the last row) and `tb_l1` run with seed 1, 500 random requests, 40% stores.

| Planted bug | Caught by |
| --- | --- |
| Store hit ignores the strobe (writes all 4 bytes) | Data check, WriteBack data check |
| Dirty victim not written back | `a_no_dirty_overwrite`, traffic check (missing WriteBack), data check |
| WriteBack to the new line's address instead of the victim's | Traffic check (address), data check |
| Store hit leaves the line in E | Traffic check (missing WriteBack), data check |
| Store miss merges at word 0, not the store's word | Data check, WriteBack data check |
| Store miss: fill overwrites the store bytes | Data check, WriteBack data check |
| Clean victim also written back | Traffic check only (extra WriteBack): data stays correct |
| RAM enable not FSM-gated (raw `cpu_req_valid` with the CPU's address) | `a_payload_stable`, WriteBack data check, data check |
| WriteBack completion leaves the victim in M | `a_no_dirty_overwrite` only: the fill overwrites the line, so data and traffic stay correct |
| Load fill installs S instead of E | `a_no_s_single` only |
| Stimulus sends a store with strobe `0000` | `a_strb_nonzero`, covergroup illegal bin |

The ungated-enable row backs the claim that the WriteBack data can come from the data RAM's output register: with the enable gated by the FSM the register holds the victim line, and without the gating the assertion fires.

## Scoreboard, Coverage

> Planned (Stage 4: UVM environment, functional coverage, full mutation testing)
