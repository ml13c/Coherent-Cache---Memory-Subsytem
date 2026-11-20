// cpu_if: one CPU port (loads and stores).
// drv_cb drives requests; mon_cb only observes, so a checker never races the DUT.

interface cpu_if
  import cache_pkg::*;
(
  input logic clk,
  input logic rst
);

  logic  req_valid;
  logic  req_ready;
  logic  req_we;
  addr_t req_addr;
  word_t req_wdata;
  strb_t req_strb;
  logic  resp_valid;
  word_t resp_rdata;

  clocking drv_cb @(posedge clk);
    input  rst, req_ready, resp_valid;
    output req_valid, req_we, req_addr, req_wdata, req_strb;
  endclocking

  clocking mon_cb @(posedge clk);
    input rst, req_valid, req_ready, req_we, req_addr, req_wdata, req_strb,
          resp_valid, resp_rdata;
  endclocking

endinterface
