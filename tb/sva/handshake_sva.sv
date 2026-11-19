// handshake_sva: valid/ready rules for one channel (AXI handshake rules).
//   1. Once valid is high, it stays high until the handshake.
//   2. The payload holds stable while valid && !ready.
//   3. valid and ready are never X or Z out of reset.
//   4. valid is low in the cycle after a reset cycle.
// "valid must not depend on ready" is a combinational-path rule that a
// cycle-based assertion cannot observe; it is enforced by registering valid.

module handshake_sva #(
  parameter string       NAME = "channel",
  parameter int unsigned W    = 1
) (
  input logic         clk,
  input logic         rst,
  input logic         valid,
  input logic         ready,
  input logic [W-1:0] payload
);

  a_valid_held: assert property (@(posedge clk) disable iff (rst)
    valid && !ready |=> valid)
    else $error("%s: valid dropped before handshake", NAME);

  a_payload_stable: assert property (@(posedge clk) disable iff (rst)
    valid && !ready |=> $stable(payload))
    else $error("%s: payload changed while valid && !ready", NAME);

  a_ctrl_known: assert property (@(posedge clk) disable iff (rst)
    !$isunknown({valid, ready}))
    else $error("%s: valid/ready is X or Z", NAME);

  a_valid_low_after_reset: assert property (@(posedge clk)
    rst |=> !valid)
    else $error("%s: valid high in the cycle after reset", NAME);

endmodule
