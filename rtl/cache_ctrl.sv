// cache_ctrl: lookup, hit/miss, miss path and CPU response. All cache policy
// lives here; tag_array and data_array are storage only.
//
// Load hit:  accept and compare tags in cycle 0, data RAM output muxed in cycle 1.
// Load miss: IDLE -> REQ (BusRd until accepted) -> WAIT (until the line returns).
//            The fill writes the line and tag, and the word is registered and
//            returned the next cycle, when the controller is back in IDLE.
// mem_req_valid comes straight from the state flop, so it cannot depend on ready.

module cache_ctrl
  import cache_pkg::*;
(
  input  logic                  clk,
  input  logic                  rst,

  // CPU port (loads)
  input  logic                  cpu_req_valid,
  output logic                  cpu_req_ready,
  input  addr_t                 cpu_req_addr,
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
  output logic [LINE_BYTES-1:0] data_we    [WAYS],
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
  addr_t  req_addr_q;
  way_t   way_q;             // hit way on a hit, fill way on a miss
  logic   resp_from_fill_q;  // response word comes from fill_word_q, not the data RAM
  word_t  fill_word_q;

  // Control registers
  logic   resp_valid_q;

  // Lookup signals
  logic             req_hs;
  logic             fill_hs;
  logic [WAYS-1:0]  way_hit;
  logic             hit;
  way_t             hit_way;
  way_t             victim_way;

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

  always_comb begin
    hit_way = '0;
    for (int unsigned w = 0; w < WAYS; w++)
      if (way_hit[w]) hit_way = way_t'(w);
  end

  // Direct-mapped: the only way. Stage 3: first invalid way, else LRU.
  assign victim_way = '0;

  // ---------------------------------------------------------------------------
  // FSM
  // ---------------------------------------------------------------------------
  assign fill_hs = mem_resp_valid && mem_resp_ready;

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      IDLE: if (req_hs && !hit) state_d = REQ;
      REQ:  if (mem_req_ready)  state_d = WAIT;
      WAIT: if (fill_hs)        state_d = IDLE;
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
      req_addr_q <= cpu_req_addr;
      way_q      <= hit ? hit_way : victim_way;
    end
    if (fill_hs) fill_word_q <= get_word(mem_resp_rdata, get_word_off(req_addr_q));
    resp_from_fill_q <= fill_hs;
  end

  // ---------------------------------------------------------------------------
  // Memory request (REQ) and response (WAIT)
  // ---------------------------------------------------------------------------
  assign mem_req_valid  = (state_q == REQ);
  assign mem_req_cmd    = BUS_RD;
  assign mem_req_addr   = get_line_addr(req_addr_q);
  assign mem_req_wdata  = '0;  // Stage 2: victim line for WriteBack
  assign mem_resp_ready = (state_q == WAIT);

  // ---------------------------------------------------------------------------
  // Arrays: lookup read in IDLE, fill write in WAIT
  // ---------------------------------------------------------------------------
  assign data_en    = req_hs || fill_hs;
  assign data_addr  = (state_q == WAIT) ? get_index(req_addr_q) : get_index(cpu_req_addr);
  assign data_wdata = mem_resp_rdata;

  always_comb begin
    for (int unsigned w = 0; w < WAYS; w++)
      data_we[w] = (fill_hs && way_q == way_t'(w)) ? '1 : '0;
  end

  assign tag_wr_en    = fill_hs;
  assign tag_wr_index = get_index(req_addr_q);
  assign tag_wr_way   = way_q;
  assign tag_wr_tag   = get_tag(req_addr_q);
  assign tag_wr_state = mem_resp_shared ? MESI_S : MESI_E;

  // ---------------------------------------------------------------------------
  // CPU response (cycle after a hit or a fill)
  // ---------------------------------------------------------------------------
  assign cpu_resp_valid = resp_valid_q;
  assign cpu_resp_rdata = resp_from_fill_q ? fill_word_q
                                           : get_word(data_rdata[way_q], get_word_off(req_addr_q));

endmodule
