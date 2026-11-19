// line_channel_sva: protocol checks for one line channel.
// Handshake rules on both directions, plus request/response pairing:
// at most one request outstanding, and no response without a request.
// Ports use line_if's signal names so a bind into an RTL module can use .*.

module line_channel_sva
  import cache_pkg::*;
#(
  parameter string NAME = "line"
) (
  input logic       clk,
  input logic       rst,
  input logic       req_valid,
  input logic       req_ready,
  input bus_cmd_e   req_cmd,
  input line_addr_t req_addr,
  input line_t      req_wdata,
  input logic       resp_valid,
  input logic       resp_ready,
  input line_t      resp_rdata,
  input logic       resp_shared
);

  localparam int unsigned REQ_W  = unsigned'($bits(bus_cmd_e)) + LINE_ADDR_W + LINE_W;
  localparam int unsigned RESP_W = LINE_W + 1;

  handshake_sva #(.NAME({NAME, ".req"}), .W(REQ_W)) u_req (
    .clk, .rst, .valid(req_valid), .ready(req_ready),
    .payload({req_cmd, req_addr, req_wdata})
  );

  handshake_sva #(.NAME({NAME, ".resp"}), .W(RESP_W)) u_resp (
    .clk, .rst, .valid(resp_valid), .ready(resp_ready),
    .payload({resp_rdata, resp_shared})
  );

  // Requests accepted but not yet answered.
  logic req_hs, resp_hs;
  int unsigned outstanding;

  assign req_hs  = req_valid  && req_ready;
  assign resp_hs = resp_valid && resp_ready;

  always_ff @(posedge clk) begin
    if (rst) outstanding <= 0;
    else     outstanding <= outstanding + 32'(req_hs) - 32'(resp_hs);
  end

  a_one_outstanding: assert property (@(posedge clk) disable iff (rst)
    req_hs |-> outstanding == 0 || (outstanding == 1 && resp_hs))
    else $error("%s: request accepted while another is outstanding", NAME);

  a_resp_has_req: assert property (@(posedge clk) disable iff (rst)
    resp_valid |-> outstanding == 1)
    else $error("%s: response without an outstanding request", NAME);

  a_cmd_known: assert property (@(posedge clk) disable iff (rst)
    req_valid |-> !$isunknown({req_cmd, req_addr}))
    else $error("%s: request cmd/addr is X while valid", NAME);

endmodule
