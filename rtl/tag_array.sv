// tag_array: tag and line state for every set and way. Storage only, no policy.
// Read is combinational so the controller can compare tags in the cycle a
// request is accepted. Only the state resets (to I); tags need no reset because
// the tag of an I line is never used.

module tag_array
  import cache_pkg::*;
(
  input  logic   clk,
  input  logic   rst,

  // Read: all ways of one set
  input  index_t rd_index,
  output tag_t   rd_tag   [WAYS],
  output mesi_e  rd_state [WAYS],

  // Write: one way of one set
  input  logic   wr_en,
  input  index_t wr_index,
  input  way_t   wr_way,
  input  tag_t   wr_tag,
  input  mesi_e  wr_state
);

  tag_t  tags   [SETS][WAYS];
  mesi_e states [SETS][WAYS];

  always_ff @(posedge clk) begin
    if (wr_en) tags[wr_index][wr_way] <= wr_tag;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int unsigned s = 0; s < SETS; s++)
        for (int unsigned w = 0; w < WAYS; w++)
          states[s][w] <= MESI_I;
    end else if (wr_en) begin
      states[wr_index][wr_way] <= wr_state;
    end
  end

  always_comb begin
    for (int unsigned w = 0; w < WAYS; w++) begin
      rd_tag[w]   = tags[rd_index][w];
      rd_state[w] = states[rd_index][w];
    end
  end

endmodule
