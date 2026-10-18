# Interface Contract (Proposed)

**Document:** IF-001 | **Version:** 0.2 | **State:** Architectural interface, RTL signal naming subject to refinement.

## 1. Per-requester interface

One in-flight request is supported *per requester*. Valid/ready transactions transfer on the rising clock edge where both signals are high. Request fields remain stable while `req_valid=1` and `req_ready=0`. A response remains valid and stable until `resp_ready=1`.

| Signal | Direction relative to L1 | Width | Meaning |
| --- | --- | --- | --- |
| `clk`, `rst_n` | in | 1 each | Single clock / synchronous active-low reset |
| `req_valid` | in | 1 | Request offered |
| `req_ready` | out | 1 | Cache can accept request |
| `req_addr` | in | 32 | Byte address, `addr[1:0]=00` |
| `req_write` | in | 1 | 0=load, 1=store |
| `req_wdata` | in | 32 | Data used for stores |
| `resp_valid` | out | 1 | Response available |
| `resp_ready` | in | 1 | Requester accepts response |
| `resp_rdata` | out | 32 | Load result (ignored for stores) |
| `resp_error` | out | 1 | Unsupported access / protocol error if implemented |

Requests may be blocked while a miss/coherence operation is in progress. A new request can be accepted only if no prior accepted request is awaiting completion. A same-cycle snoop wins the acceptance tie and may lower `req_ready`; already accepted same-line stores must be completed before the snoop acknowledges. No read response can be returned before the latest ordered value is coherent.

## 2. Coherence-fabric transaction contract

The RTL may choose discrete signals or SystemVerilog structs/interfaces. Semantic fields:

- `source`: cache 0 or cache 1.
- `op`: `BusRd`, `BusRdX`, `BusUpgr`, or `Writeback`.
- `line_addr`: 16-byte-aligned 32-bit byte address.
- `line_data`: 128-bit payload for dirty writeback, or returned full cache line.
- `snoop_result`: miss/clean-hit/modified-hit and associated dirty data.
- `grant`: serialized completion; output `fill_state` E/S/M as appropriate.
- `valid/ready` or request/ack handshakes with stable-while-stalled guarantees.

Exactly one coherence transaction is active; the fabric waits for all necessary snoop acknowledgements and backing-memory completion **before granting ownership**. Arbiter round-robin selection must eventually serve both ports under sustained demand.

**Ordering/interlock semantics:** the L1 exposes an internal snoop-pending/interlock (actual RTL signal naming TBD), drains accepted conflicting CPU operations before ack, and exposes simulation-observable local store commit + state transition events. A pending `BusUpgr` must re-check that the same S line remains present; if not, the cache retries as `BusRdX` via a defined cancellation/re-request handshake. This rule prevents two caches from believing they exclusively own the same line. See `coherence_ordering.md` for the full contract.

## 3. Backing memory / AXI4-style adapter

Plan **32-bit AXI4-style** memory channels carrying **4 data beats** per 16-byte cache line. An incremental burst starts at a 16-byte aligned address. This is an intended subset with **at most one outstanding burst**:

| Channel | Required conceptual fields |
| --- | --- |
| Read address | `ARVALID/ARREADY`, `ARADDR`, `ARLEN=3`, `ARSIZE=2`, `ARBURST=INCR` |
| Read data | `RVALID/RREADY`, `RDATA[31:0]`, `RLAST`, `RRESP` |
| Write address | `AWVALID/AWREADY`, `AWADDR`, `AWLEN=3`, `AWSIZE=2`, `AWBURST=INCR` |
| Write data | `WVALID/WREADY`, `WDATA[31:0]`, `WSTRB=4'b1111`, `WLAST` |
| Write response | `BVALID/BREADY`, `BRESP` |

No narrow/unaligned accesses, reordering, multiple IDs or interleaved transactions in this initial final target. Error policy must be fixed before RTL sign-off. Do not label the implementation AXI4-compliant without independently checking all mandatory requirements for the claimed subset.

## 4. Reset

Reset invalidates all L1 tag/MESI entries, clears pending fabric transactions and performance counters, and causes no fabricated completion acknowledgements. The *simulation-only testbench* controls initial backing-memory contents. The memory model is **outside** the synthesizable boundary; standalone FPGA operation requires an additional synthesizable BRAM memory slave and stimulus generator. Reset during in-flight transfers will be separately tested and documented; it is not a durability or persistence guarantee.
