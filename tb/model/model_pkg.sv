// model_pkg: reference model of one cache, called once per accepted CPU request
// in acceptance order. Two independent predictions:
//   1. load_value: what a load must return. Comes from architectural memory
//      only, so it does not depend on the cache's contents or replacement policy.
//   2. access: hit or miss, and the memory traffic and victim that follow.
//      Comes from a shadow copy of the cache's tags.
// v1 (Stage 1): loads only, direct-mapped. Stage 2 adds stores and writebacks,
// Stage 3 LRU. Wrapped by the UVM scoreboard in Stage 4.

package model_pkg;
  import cache_pkg::*;
  import mem_pkg::*;

  // Prediction for one access
  typedef struct packed {
    logic       hit;
    way_t       way;         // hit way, or the way the fill goes to
    logic       fill;        // a fill (BusRd) is expected
    line_addr_t fill_addr;
    logic       evict;       // the fill replaces a valid line (conflict miss)
    line_addr_t evict_addr;
  } access_t;

  class cache_model;

    local logic valid [SETS][WAYS];
    local tag_t tags  [SETS][WAYS];

    function new();
      reset();
    endfunction

    function void reset();
      foreach (valid[s, w]) valid[s][w] = 1'b0;
    endfunction

    // Architectural value of the word at a (no stores yet: memory's initial content).
    function word_t load_value(addr_t a);
      return mem_init_word(get_line_addr(a), get_word_off(a));
    endfunction

    // Predict one access and update the shadow tags.
    function access_t access(addr_t a);
      access_t r = '0;
      index_t  i = get_index(a);
      tag_t    t = get_tag(a);

      for (int unsigned w = 0; w < WAYS; w++) begin
        if (valid[i][w] && tags[i][w] == t) begin
          r.hit = 1'b1;
          r.way = way_t'(w);
          return r;
        end
      end

      r.way        = victim(i);
      r.fill       = 1'b1;
      r.fill_addr  = get_line_addr(a);
      r.evict      = valid[i][r.way];
      r.evict_addr = make_line_addr(tags[i][r.way], i);
      valid[i][r.way] = 1'b1;
      tags[i][r.way]  = t;
      return r;
    endfunction

    // Direct-mapped: way 0. Stage 3: first invalid way, else LRU.
    local function way_t victim(index_t i);
      return '0;
    endfunction

  endclass

endpackage
