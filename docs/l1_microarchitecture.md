# Inside one L1 cache

Both L1s use the same hardware. Each has **16 sets with two ways per set**, and each way can hold a 16-byte line. A read compares the requested tag against both ways in the selected set.

```mermaid
flowchart TB
    CPU[CPU valid/ready load-store port] --> PORT[Request latch + response buffer<br/>one outstanding request]
    PORT --> DEC[32-bit address decoder<br/>tag 31:8 / set 7:4 / offset 3:0]
    DEC --> TAG0[Way 0 tag + MESI array]
    DEC --> TAG1[Way 1 tag + MESI array]
    DEC --> D0[Way 0 128-bit data array]
    DEC --> D1[Way 1 128-bit data array]
    TAG0 --> COMP0[Way 0 compare<br/>state != I]
    TAG1 --> COMP1[Way 1 compare<br/>state != I]
    DEC --> COMP0
    DEC --> COMP1
    COMP0 --> SEL[Hit / way select]
    COMP1 --> SEL
    D0 --> DATA[128-bit data mux and store merger]
    D1 --> DATA
    SEL --> DATA
    DEC --> DATA
    DATA --> RESP[32-bit read-word extract / write-word insertion]
    RESP --> PORT
    SEL --> CTRL[L1 transaction FSM<br/>hit / miss / refill / eviction / snoop]
    LRU[16 x 1-bit LRU metadata] <--> CTRL
    CTRL <--> TAG0
    CTRL <--> TAG1
    CTRL <--> D0
    CTRL <--> D1
    CTRL <--> SNOOP[Snoop handler + local-access interlock<br/>stable MESI / transient busy]
    SNOOP <--> FAB[Coherence request/response and snoop port]
    CTRL <--> FAB
    CTRL --> COUNTS[Per-cache hit / miss / store events]
```

## Where the address goes

A CPU address is 32 bits. We split it like this:

| Bits | Name | Why |
| --- | --- | --- |
| `[31:8]` | Tag (24 bits) | Identifies which memory line is stored |
| `[7:4]` | Set index (4 bits) | Selects one of 16 sets |
| `[3:0]` | Byte offset (4 bits) | Finds the requested byte within a 16-byte line |

Only aligned 32-bit operations are supported, so `addr[1:0] = 00`; `addr[3:2]` selects one of the four words in a line.

## What's stored in each cache

| Storage | Size |
| --- | ---: |
| Data | 2 ways × 16 sets × 128 bits = **512 B** |
| Tags | 2 × 16 × 24 = 768 bits |
| MESI metadata | 2 × 16 × 2 = 64 bits |
| LRU metadata | 1 bit per set = 16 bits |

**Why two ways?** Two different addresses can occupy the same set. A direct-mapped cache would have to evict one immediately. Two ways reduce those conflicts without making the design much larger.

**Why LRU?** When both ways are occupied, the controller replaces the one used least recently. With only two ways, that takes a single bit per set. An invalid way is always preferred over evicting a valid one.

**Why keep MESI with each tag?** The tag says *which* line this is; the MESI bits say *whether it can be used, shared, or written*. State **I** already means invalid, and **M** already means dirty, so we do not need separate valid or dirty bits.

The FSM handles misses, refills, writebacks, and snoops. A hit uses the selected word; a miss brings in an entire line. See [coherence ordering](coherence_ordering.md) for conflicts between a local request and a snoop.
