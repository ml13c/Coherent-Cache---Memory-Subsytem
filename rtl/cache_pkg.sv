// cache_pkg: geometry, derived widths, types and address helpers shared by
// every cache module and the testbench. All sizes in the design come from here.

`ifndef CACHE_WAYS
  `define CACHE_WAYS 1  // Stage 3 raises the default to 2. Override: xvlog -d CACHE_WAYS=n
`endif

package cache_pkg;

  // ---------------------------------------------------------------------------
  // Geometry: the only hand-set sizes. All must be powers of two.
  // ---------------------------------------------------------------------------
  localparam int unsigned ADDR_W     = 32;           // byte address width
  localparam int unsigned WORD_W     = 32;           // CPU data width
  localparam int unsigned LINE_BYTES = 32;           // bytes per cache line
  localparam int unsigned SETS       = 64;           // sets per cache
  localparam int unsigned WAYS       = `CACHE_WAYS;  // ways per set

  // ---------------------------------------------------------------------------
  // Derived widths
  // ---------------------------------------------------------------------------
  localparam int unsigned WORD_BYTES     = WORD_W / 8;                    // 4
  localparam int unsigned STRB_W         = WORD_BYTES;                    // 4 byte enables per word
  localparam int unsigned LINE_W         = LINE_BYTES * 8;                // 256
  localparam int unsigned WORDS_PER_LINE = LINE_BYTES / WORD_BYTES;       // 8

  localparam int unsigned BYTE_OFF_W     = $clog2(WORD_BYTES);            // 2: byte within word
  localparam int unsigned WORD_OFF_W     = $clog2(WORDS_PER_LINE);        // 3: word within line
  localparam int unsigned OFFSET_W       = $clog2(LINE_BYTES);            // 5: byte within line
  localparam int unsigned INDEX_W        = $clog2(SETS);                  // 6
  localparam int unsigned TAG_W          = ADDR_W - INDEX_W - OFFSET_W;   // 21
  localparam int unsigned LINE_ADDR_W    = ADDR_W - OFFSET_W;             // 27 = TAG_W + INDEX_W

  // $clog2(1) = 0 would give a zero-width type; a 1-way cache keeps a 1-bit way index tied to 0.
  localparam int unsigned WAY_W          = (WAYS > 1) ? $clog2(WAYS) : 1;

  // ---------------------------------------------------------------------------
  // Types
  // ---------------------------------------------------------------------------
  typedef logic [ADDR_W-1:0]      addr_t;
  typedef logic [TAG_W-1:0]       tag_t;
  typedef logic [INDEX_W-1:0]     index_t;
  typedef logic [WORD_OFF_W-1:0]  word_off_t;
  typedef logic [LINE_ADDR_W-1:0] line_addr_t;
  typedef logic [WAY_W-1:0]       way_t;
  typedef logic [WORD_W-1:0]      word_t;
  typedef logic [STRB_W-1:0]      strb_t;
  typedef logic [LINE_W-1:0]      line_t;

  // Line state. I = 00 so the reset value means invalid.
  typedef enum logic [1:0] {
    MESI_I = 2'b00,
    MESI_S = 2'b01,
    MESI_E = 2'b10,
    MESI_M = 2'b11
  } mesi_e;

  // Line channel / bus command. Four commands fill 2 bits: no illegal encodings.
  typedef enum logic [1:0] {
    BUS_RD   = 2'd0,  // read, shared copy allowed
    BUS_RDX  = 2'd1,  // read for ownership: peers invalidate
    BUS_UPGR = 2'd2,  // S -> M, no data: peers invalidate
    BUS_WB   = 2'd3   // write a dirty line back to memory
  } bus_cmd_e;

  // ---------------------------------------------------------------------------
  // Address helpers
  //   addr = | tag [31:11] | index [10:5] | word [4:2] | byte [1:0] |
  //   line address = {tag, index} = addr[31:5]
  // ---------------------------------------------------------------------------
  function automatic tag_t get_tag(addr_t a);
    return a[ADDR_W-1 -: TAG_W];
  endfunction

  function automatic index_t get_index(addr_t a);
    return a[OFFSET_W +: INDEX_W];
  endfunction

  function automatic word_off_t get_word_off(addr_t a);
    return a[BYTE_OFF_W +: WORD_OFF_W];
  endfunction

  function automatic line_addr_t get_line_addr(addr_t a);
    return a[ADDR_W-1 -: LINE_ADDR_W];
  endfunction

  // Rebuild a line address from a stored tag and its set, e.g. for a victim writeback.
  function automatic line_addr_t make_line_addr(tag_t t, index_t i);
    return {t, i};
  endfunction

  // ---------------------------------------------------------------------------
  // State helpers
  // ---------------------------------------------------------------------------
  function automatic logic is_valid(mesi_e s);
    return s != MESI_I;
  endfunction

  function automatic logic is_dirty(mesi_e s);
    return s == MESI_M;
  endfunction

endpackage
