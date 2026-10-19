# Interfaces

These are the planned signal groups, not a finalized RTL module declaration.

## CPU to L1

Each cache accepts aligned, 32-bit loads and stores. `req_valid` and `req_ready` mark an accepted request; `resp_valid` and `resp_ready` mark a completed response.

| Signals | Purpose |
| --- | --- |
| `clk`, `rst_n` | Common clock and synchronous active-low reset |
| `req_valid`, `req_ready` | Request handshake |
| `req_addr[31:0]`, `req_write` | Address and read/write choice |
| `req_wdata[31:0]` | Data for a store |
| `resp_valid`, `resp_ready` | Response handshake |
| `resp_rdata[31:0]`, `resp_error` | Read value or error status |

**Why ready/valid?** A cache hit may finish quickly, but a miss or snoop can stall for many cycles. The handshake avoids assuming every request finishes in one cycle. Each CPU port has **one outstanding request** to keep ordering simple.

## Between caches

| Transaction | Purpose |
| --- | --- |
| `BusRd` | Request a line for reading |
| `BusRdX` | Request a line with permission to write |
| `BusUpgr` | Upgrade a cached Shared line to writable ownership |
| `Writeback` | Send a modified line to memory |

Requests carry a cache ID and aligned line address. Responses include the line data when needed, peer state information, snoop acknowledgement, and the final ownership grant. The fabric services one transaction at a time.

## Cache to memory

The adapter uses a **32-bit AXI4-style** read/write interface. A 16-byte cache line takes **four 32-bit beats** (`ARLEN` or `AWLEN` = 3; `ARSIZE` or `AWSIZE` = 2), with ready/valid handshakes and a response channel.

**Why AXI-style?** It is a useful hardware interface to learn and matches the line-transfer behavior we need. We are implementing a limited subset, **not claiming full AXI4 compliance**.

Reset invalidates cache entries and cancels pending work. It does **not** automatically flush dirty data to memory, so reset is not a data-persistence operation.
