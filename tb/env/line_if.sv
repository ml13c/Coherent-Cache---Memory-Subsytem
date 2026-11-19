// line_if: one line channel (request + response), see docs/architecture.md.
// RTL uses plain ports; the testbench connects them through this interface.
// Each side gets a clocking block so testbench reads and drives never race the
// RTL's flops: inputs are sampled just before the edge, outputs change at the edge.

interface line_if
  import cache_pkg::*;
(
  input logic clk,
  input logic rst
);

  // Request: master -> slave
  logic       req_valid;
  logic       req_ready;
  bus_cmd_e   req_cmd;
  line_addr_t req_addr;
  line_t      req_wdata;

  // Response: slave -> master
  logic       resp_valid;
  logic       resp_ready;
  line_t      resp_rdata;
  logic       resp_shared;

  // Slave side (memory model)
  clocking slv_cb @(posedge clk);
    input  rst, req_valid, req_cmd, req_addr, req_wdata, resp_ready;
    output req_ready, resp_valid, resp_rdata, resp_shared;
  endclocking

  // Master side (test drivers; the cache in Stage 1)
  clocking mst_cb @(posedge clk);
    input  rst, req_ready, resp_valid, resp_rdata, resp_shared;
    output req_valid, req_cmd, req_addr, req_wdata, resp_ready;
  endclocking

endinterface
