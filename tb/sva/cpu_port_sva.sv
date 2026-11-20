// cpu_port_sva: protocol checks for one CPU port.
// Handshake rules on the request, and request/response pairing: the response has
// no ready, so it is a one-cycle pulse for exactly one accepted request.

module cpu_port_sva
  import cache_pkg::*;
#(
  parameter string NAME = "cpu"
) (
  input logic  clk,
  input logic  rst,
  input logic  req_valid,
  input logic  req_ready,
  input addr_t req_addr,
  input logic  resp_valid
);

  handshake_sva #(.NAME({NAME, ".req"}), .W(ADDR_W)) u_req (
    .clk, .rst, .valid(req_valid), .ready(req_ready), .payload(req_addr)
  );

  logic        req_hs;
  int unsigned outstanding;

  assign req_hs = req_valid && req_ready;

  always_ff @(posedge clk) begin
    if (rst) outstanding <= 0;
    else     outstanding <= outstanding + 32'(req_hs) - 32'(resp_valid);
  end

  a_one_outstanding: assert property (@(posedge clk) disable iff (rst)
    req_hs |-> outstanding == 0 || (outstanding == 1 && resp_valid))
    else $error("%s: request accepted while another is outstanding", NAME);

  a_resp_has_req: assert property (@(posedge clk) disable iff (rst)
    resp_valid |-> outstanding == 1)
    else $error("%s: response without an outstanding request", NAME);

  a_resp_known: assert property (@(posedge clk) disable iff (rst)
    !$isunknown(resp_valid))
    else $error("%s: resp_valid is X or Z", NAME);

  a_addr_aligned: assert property (@(posedge clk) disable iff (rst)
    req_valid |-> req_addr[BYTE_OFF_W-1:0] == '0)
    else $error("%s: request address 0x%08h not word-aligned", NAME, req_addr);

endmodule
