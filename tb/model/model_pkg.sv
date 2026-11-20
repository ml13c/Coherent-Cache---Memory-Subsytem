// model_pkg: reference model of one cache, called once per accepted CPU request
// in acceptance order. Two independent predictions:
//   1. Values: load_value and the WriteBack data come from architectural memory
//      (every store applied byte by byte), so they do not depend on the cache's
//      contents or replacement policy.
//   2. Traffic: access predicts hit or miss, the WriteBack of a dirty victim and
//      the fill, from a shadow copy of the cache's tags and dirty bits.
// v2 (Stage 2): loads and stores, write-back, write-allocate, direct-mapped.
// Stage 3 adds LRU. Wrapped by the UVM scoreboard in Stage 4.

package model_pkg;
  import cache_pkg::*;
  import mem_pkg::*;

  // Prediction for one access
  typedef struct packed {
    logic       hit;
    way_t       way;         // hit way, or the way the fill goes to
    logic       fill;        // a fill is expected
    bus_cmd_e   fill_cmd;    // BusRd (load) or BusRdX (store)
    line_addr_t fill_addr;
    logic       evict;       // the fill replaces a valid line
    line_addr_t evict_addr;
    logic       wb;          // the evicted line is dirty: WriteBack before the fill
    line_t      wb_data;     // architectural value of the evicted line
  } access_t;

  class cache_model;

    local logic  valid [SETS][WAYS];
    local logic  dirty [SETS][WAYS];
    local tag_t  tags  [SETS][WAYS];
    local word_t arch  [addr_t];  // words written by stores, keyed by word address

    function new();
      reset();
    endfunction

    function void reset();
      foreach (valid[s, w]) begin
        valid[s][w] = 1'b0;
        dirty[s][w] = 1'b0;
      end
      arch.delete();
    endfunction

    // Architectural value of the word at a: the last store's bytes, else memory's
    // initial content.
    function word_t load_value(addr_t a);
      return arch.exists(a) ? arch[a] : mem_init_word(get_line_addr(a), get_word_off(a));
    endfunction

    function line_t line_value(line_addr_t la);
      line_t l;
      for (int unsigned w = 0; w < WORDS_PER_LINE; w++)
        l[w*WORD_W +: WORD_W] = load_value({la, word_off_t'(w), {BYTE_OFF_W{1'b0}}});
      return l;
    endfunction

    // Apply a store's enabled bytes to architectural memory.
    function void store(addr_t a, word_t wdata, strb_t strb);
      word_t v = load_value(a);
      for (int unsigned b = 0; b < WORD_BYTES; b++)
        if (strb[b]) v[b*8 +: 8] = wdata[b*8 +: 8];
      arch[a] = v;
    endfunction

    // Predict one access and update the shadow tags and dirty bits.
    function access_t access(addr_t a, logic we);
      access_t r = '0;
      index_t  i = get_index(a);
      tag_t    t = get_tag(a);

      for (int unsigned w = 0; w < WAYS; w++) begin
        if (valid[i][w] && tags[i][w] == t) begin
          r.hit = 1'b1;
          r.way = way_t'(w);
          if (we) dirty[i][w] = 1'b1;
          return r;
        end
      end

      r.way        = victim(i);
      r.fill       = 1'b1;
      r.fill_cmd   = we ? BUS_RDX : BUS_RD;
      r.fill_addr  = get_line_addr(a);
      r.evict      = valid[i][r.way];
      r.evict_addr = make_line_addr(tags[i][r.way], i);
      r.wb         = r.evict && dirty[i][r.way];
      if (r.wb) r.wb_data = line_value(r.evict_addr);
      valid[i][r.way] = 1'b1;
      dirty[i][r.way] = we;
      tags[i][r.way]  = t;
      return r;
    endfunction

    // Direct-mapped: way 0. Stage 3: first invalid way, else LRU.
    local function way_t victim(index_t i);
      return '0;
    endfunction

  endclass

endpackage
