// cpu_if: one CPU port (loads; stores are added in Stage 2).
// drv_cb drives requests; mon_cb only observes, so a checker never races the DUT.

interface cpu_if
  import cache_pkg::*;
(
  input logic clk,
  input logic rst
);

  logic  req_valid;
  logic  req_ready;
  addr_t req_addr;
  logic  resp_valid;
  word_t resp_rdata;

  clocking drv_cb @(posedge clk);
    input  rst, req_ready, resp_valid;
    output req_valid, req_addr;
  endclocking

  clocking mon_cb @(posedge clk);
    input rst, req_valid, req_ready, req_addr, resp_valid, resp_rdata;
  endclocking

endinterface
