// tag_state_sva: line-state rules, checked at the tag array's write port.
// Bound into tag_array; old_tag/old_state are the entry being overwritten.
// Every state change goes through this port (reset only clears to I), so
// checking writes covers every transition.

module tag_state_sva
  import cache_pkg::*;
#(
  parameter string NAME = "tags"
) (
  input logic   clk,
  input logic   rst,
  input logic   wr_en,
  input index_t wr_index,
  input way_t   wr_way,
  input tag_t   wr_tag,
  input mesi_e  wr_state,
  input tag_t   old_tag,
  input mesi_e  old_state
);

  // A dirty line may change state (store hit M -> M, WriteBack done M -> I) but is
  // never replaced by another line: its WriteBack must set it to I first.
  a_no_dirty_overwrite: assert property (@(posedge clk) disable iff (rst)
    wr_en && old_state == MESI_M |-> wr_tag == old_tag)
    else $error("%s: set %0d way %0d: M line tag 0x%0h overwritten by tag 0x%0h without WriteBack",
                NAME, wr_index, wr_way, old_tag, wr_tag);

  // Stage 6: remove or replace. With one cache, memory ties resp_shared to 0, so
  // no line can be S. With two caches S is legal and this check would fail.
  a_no_s_single: assert property (@(posedge clk) disable iff (rst)
    wr_en |-> wr_state != MESI_S)
    else $error("%s: set %0d way %0d written to S in single-cache mode", NAME, wr_index, wr_way);

endmodule
