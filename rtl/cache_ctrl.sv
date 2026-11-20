// cache_ctrl: lookup, hit/miss, miss path and CPU response. All cache policy
// lives here; tag_array and data_array are storage only.
//
// Hit (load or store): accept and compare tags in cycle 0, respond in cycle 1.
//   A load muxes the data RAM output in cycle 1. A store writes its bytes and
//   sets M at the end of cycle 0.
// Miss: IDLE -> REQ -> WAIT. REQ sends cmd_q until accepted; WAIT waits for the
//   response. A dirty victim is written back first: cmd_q = WriteBack, and its
//   response marks the victim I and sends the FSM back to REQ with the fill
//   command (BusRd for a load, BusRdX for a store). The fill writes the whole
//   line once, with a store's bytes merged in, and the CPU response follows.
//
// WriteBack data is the data RAM's output register. The lookup read in cycle 0
// leaves the victim set there, and the RAM is enabled only by req_hs (IDLE) and
// fill_hs (WAIT, not a WriteBack), so nothing can change it while the WriteBack
// is pending. No line buffer is needed.
// mem_req_valid comes straight from the state flop, so it cannot depend on ready.

module cache_ctrl
  import cache_pkg::*;
(
  input  logic                  clk,
  input  logic                  rst,

  // CPU port
  input  logic                  cpu_req_valid,
  output logic                  cpu_req_ready,
  input  logic                  cpu_req_we,
  input  addr_t                 cpu_req_addr,
  input  word_t                 cpu_req_wdata,
  input  strb_t                 cpu_req_strb,
  output logic                  cpu_resp_valid,
  output word_t                 cpu_resp_rdata,

  // Tag array
  output index_t                tag_rd_index,
  input  tag_t                  tag_rd_tag   [WAYS],
  input  mesi_e                 tag_rd_state [WAYS],
  output logic                  tag_wr_en,
  output index_t                tag_wr_index,
  output way_t                  tag_wr_way,
  output tag_t                  tag_wr_tag,
  output mesi_e                 tag_wr_state,

  // Data array
  output logic                  data_en,
  output index_t                data_addr,
  output line_strb_t            data_we    [WAYS],
  output line_t                 data_wdata,
  input  line_t                 data_rdata [WAYS],

  // Line channel to memory (master)
  output logic                  mem_req_valid,
  input  logic                  mem_req_ready,
  output bus_cmd_e              mem_req_cmd,
  output line_addr_t            mem_req_addr,
  output line_t                 mem_req_wdata,
  input  logic                  mem_resp_valid,
  output logic                  mem_resp_ready,
  input  line_t                 mem_resp_rdata,
  input  logic                  mem_resp_shared
);

  typedef enum logic [1:0] {
    IDLE,  // accept and look up a request
    REQ,   // memory request valid, waiting for ready
    WAIT   // waiting for the memory response
  } state_e;

  state_e state_q, state_d;

  // Request registers (datapath: no reset)
  addr_t    req_addr_q;
  logic     req_we_q;
  word_t    req_wdata_q;
  strb_t    req_strb_q;
  way_t     way_q;             // hit way on a hit, victim/fill way on a miss
  tag_t     victim_tag_q;      // WriteBack address; the tag read port follows the CPU address
  bus_cmd_e cmd_q;             // command REQ sends: WriteBack, then the fill
  logic     resp_from_fill_q;  // response word comes from fill_word_q, not the data RAM
  word_t    fill_word_q;

  // Control registers
  logic     resp_valid_q;

  // Lookup and handshake signals
  logic             req_hs;
  logic             resp_hs;
  logic             wb_done;
  logic             fill_hs;
  logic [WAYS-1:0]  way_hit;
  logic             hit;
  logic             store_hit;
  way_t             hit_way;
  way_t             victim_way;
  logic             victim_dirty;

  function automatic bus_cmd_e fill_cmd(logic we);
    return we ? BUS_RDX : BUS_RD;
  endfunction

  // ---------------------------------------------------------------------------
  // Lookup (cycle 0)
  // ---------------------------------------------------------------------------
  assign cpu_req_ready = (state_q == IDLE);
  assign req_hs        = cpu_req_valid && cpu_req_ready;
  assign tag_rd_index  = get_index(cpu_req_addr);

  always_comb begin
    way_hit = '0;
    for (int unsigned w = 0; w < WAYS; w++)
      way_hit[w] = is_valid(tag_rd_state[w]) && (tag_rd_tag[w] == get_tag(cpu_req_addr));
  end

  assign hit = |way_hit;
  // Stage 6: a store to an S line is not a write hit; it needs BusUpgr.
  assign store_hit = req_hs && hit && cpu_req_we;

  always_comb begin
    hit_way = '0;
    for (int unsigned w = 0; w < WAYS; w++)
      if (way_hit[w]) hit_way = way_t'(w);
  end

  // Direct-mapped: the only way. Stage 3: first invalid way, else LRU.
  assign victim_way   = '0;
  assign victim_dirty = is_dirty(tag_rd_state[victim_way]);

  // ---------------------------------------------------------------------------
  // FSM
  // ---------------------------------------------------------------------------
  // Both a WriteBack and a fill end with a response in WAIT; cmd_q tells them apart.
  assign resp_hs = mem_resp_valid && mem_resp_ready;
  assign wb_done = resp_hs && (cmd_q == BUS_WB);
  assign fill_hs = resp_hs && (cmd_q != BUS_WB);

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      IDLE: if (req_hs && !hit) state_d = REQ;
      REQ:  if (mem_req_ready)  state_d = WAIT;
      WAIT: if (wb_done)        state_d = REQ;   // victim written back: request the fill
            else if (fill_hs)   state_d = IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q      <= IDLE;
      resp_valid_q <= 1'b0;
    end else begin
      state_q      <= state_d;
      resp_valid_q <= (req_hs && hit) || fill_hs;
    end
  end

  always_ff @(posedge clk) begin
    if (req_hs) begin
      req_addr_q   <= cpu_req_addr;
      req_we_q     <= cpu_req_we;
      req_wdata_q  <= cpu_req_wdata;
      req_strb_q   <= cpu_req_strb;
      way_q        <= hit ? hit_way : victim_way;
      victim_tag_q <= tag_rd_tag[victim_way];
      cmd_q        <= victim_dirty ? BUS_WB : fill_cmd(cpu_req_we);
    end else if (wb_done) begin
      cmd_q        <= fill_cmd(req_we_q);
    end
    if (fill_hs) fill_word_q <= get_word(mem_resp_rdata, get_word_off(req_addr_q));
    resp_from_fill_q <= fill_hs;
  end

  // ---------------------------------------------------------------------------
  // Memory request (REQ) and response (WAIT)
  // ---------------------------------------------------------------------------
  assign mem_req_valid  = (state_q == REQ);
  assign mem_req_cmd    = cmd_q;
  assign mem_req_addr   = (cmd_q == BUS_WB) ? make_line_addr(victim_tag_q, get_index(req_addr_q))
                                            : get_line_addr(req_addr_q);
  assign mem_req_wdata  = data_rdata[way_q];  // used only by WriteBack; held by the RAM
  assign mem_resp_ready = (state_q == WAIT);

  // ---------------------------------------------------------------------------
  // Arrays
  //   data: lookup read and store-hit write in IDLE, fill write in WAIT
  //   tags: store hit -> M, WriteBack done -> victim I, fill -> E/S (load) or M (store)
  // ---------------------------------------------------------------------------
  assign data_en    = req_hs || fill_hs;  // FSM-gated: never enabled in REQ or during a WriteBack
  assign data_addr  = (state_q == IDLE) ? get_index(cpu_req_addr) : get_index(req_addr_q);
  assign data_wdata = (state_q == IDLE)
                    ? {WORDS_PER_LINE{cpu_req_wdata}}
                    : merge_line(mem_resp_rdata, req_wdata_q,
                                 req_we_q ? line_strb(get_word_off(req_addr_q), req_strb_q) : '0);

  always_comb begin
    for (int unsigned w = 0; w < WAYS; w++) data_we[w] = '0;
    if (store_hit) data_we[hit_way] = line_strb(get_word_off(cpu_req_addr), cpu_req_strb);
    if (fill_hs)   data_we[way_q]   = '1;
  end

  always_comb begin
    tag_wr_en    = 1'b0;
    tag_wr_index = get_index(req_addr_q);
    tag_wr_way   = way_q;
    tag_wr_tag   = get_tag(req_addr_q);
    tag_wr_state = MESI_I;
    if (store_hit) begin
      tag_wr_en    = 1'b1;
      tag_wr_index = get_index(cpu_req_addr);
      tag_wr_way   = hit_way;
      tag_wr_tag   = get_tag(cpu_req_addr);
      tag_wr_state = MESI_M;
    end else if (wb_done) begin
      tag_wr_en    = 1'b1;
      tag_wr_tag   = victim_tag_q;
      tag_wr_state = MESI_I;
    end else if (fill_hs) begin
      tag_wr_en    = 1'b1;
      tag_wr_state = req_we_q ? MESI_M : (mem_resp_shared ? MESI_S : MESI_E);
    end
  end

  // ---------------------------------------------------------------------------
  // CPU response (cycle after a hit or a fill). Store responses carry no data.
  // ---------------------------------------------------------------------------
  assign cpu_resp_valid = resp_valid_q;
  assign cpu_resp_rdata = resp_from_fill_q ? fill_word_q
                                           : get_word(data_rdata[way_q], get_word_off(req_addr_q));

endmodule
