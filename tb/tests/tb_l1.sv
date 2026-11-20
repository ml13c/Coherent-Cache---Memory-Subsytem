// tb_l1: test of one l1_cache against the reference model (model_pkg).
//
// Directed phase, set of A (direct-mapped):
//   loads:  cold miss, hits, conflict miss, re-miss, back-to-back hits
//   stores: hit on an E line (E -> M) with a back-to-back load of the same word,
//           eviction of that line (dirty WriteBack, then BusRd), store miss with a
//           clean victim (no WriteBack) and a partial strobe (merge into the fill),
//           store miss with a dirty victim (WriteBack, then BusRdX), load miss
//           with a dirty victim, and reloads of every written word.
//   Its hit and WriteBack patterns are also checked against fixed lists, which
//   validates the reference model itself.
// Random phase: STORE_PCT% stores with random non-zero strobes, addresses from
// four modes (hot lines, same-index conflict, sequential, uniform), about half
// issued back-to-back.
//
// Checks per request:
//   - a load returns the architectural value (every earlier store applied)
//   - a hit responds exactly 1 cycle after acceptance
//   - memory traffic is exactly the predicted list: a WriteBack of the victim
//     (address and data) if it was dirty, then BusRd/BusRdX of the line; nothing
//     on a hit. A missing or an extra request both fail.
// Protocol and line-state assertions are bound into l1_cache and tag_array.
// Plusargs: +N_REQ= +STORE_PCT= +MIN_LAT= +MAX_LAT= +REQ_READY_PCT=

module tb_l1;
  import cache_pkg::*;
  import mem_pkg::*;
  import model_pkg::*;

  localparam realtime     CLK_PERIOD = 10ns;
  localparam int unsigned TIMEOUT    = 1000;  // cycles waiting on one handshake = hang
  localparam int unsigned N_HOT      = 4;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #(CLK_PERIOD / 2) clk = ~clk;

  cpu_if  cif (.clk, .rst);
  line_if lif (.clk, .rst);

  l1_cache dut (
    .clk, .rst,
    .cpu_req_valid  (cif.req_valid),  .cpu_req_ready  (cif.req_ready),
    .cpu_req_we     (cif.req_we),     .cpu_req_addr   (cif.req_addr),
    .cpu_req_wdata  (cif.req_wdata),  .cpu_req_strb   (cif.req_strb),
    .cpu_resp_valid (cif.resp_valid), .cpu_resp_rdata (cif.resp_rdata),
    .mem_req_valid  (lif.req_valid),  .mem_req_ready  (lif.req_ready),
    .mem_req_cmd    (lif.req_cmd),    .mem_req_addr   (lif.req_addr),
    .mem_req_wdata  (lif.req_wdata),
    .mem_resp_valid (lif.resp_valid), .mem_resp_ready (lif.resp_ready),
    .mem_resp_rdata (lif.resp_rdata), .mem_resp_shared(lif.resp_shared)
  );

  bind l1_cache line_channel_sva #(.NAME("l1.mem")) u_mem_sva (
    .clk, .rst,
    .req_valid (mem_req_valid),  .req_ready (mem_req_ready),  .req_cmd   (mem_req_cmd),
    .req_addr  (mem_req_addr),   .req_wdata (mem_req_wdata),
    .resp_valid(mem_resp_valid), .resp_ready(mem_resp_ready), .resp_rdata(mem_resp_rdata),
    .resp_shared(mem_resp_shared)
  );

  bind l1_cache cpu_port_sva #(.NAME("l1.cpu")) u_cpu_sva (
    .clk, .rst,
    .req_valid(cpu_req_valid), .req_ready(cpu_req_ready), .req_we(cpu_req_we),
    .req_addr (cpu_req_addr),  .req_wdata(cpu_req_wdata), .req_strb(cpu_req_strb),
    .resp_valid(cpu_resp_valid)
  );

  bind tag_array tag_state_sva #(.NAME("l1.tags")) u_state_sva (
    .clk, .rst, .wr_en, .wr_index, .wr_way, .wr_tag, .wr_state,
    .old_tag(tags[wr_index][wr_way]), .old_state(states[wr_index][wr_way])
  );

  mem_model   mem;
  cache_model model;

  typedef struct {
    addr_t           addr;
    logic            we;
    longint unsigned cycle;
    access_t         pred;
  } pending_t;

  typedef struct {
    bus_cmd_e   cmd;
    line_addr_t addr;
    line_t      wdata;
  } mem_req_t;

  pending_t        pending[$];   // accepted, not yet answered (at most one)
  mem_req_t        seen[$];      // memory requests since the last CPU response
  logic            hit_log[$];   // predicted hit per access, in order
  logic            wb_log[$];    // predicted WriteBack per access, in order
  longint unsigned cycle;
  int unsigned     n_req     = 3000;
  int unsigned     store_pct = 40;
  int unsigned     errors;

  // Whole run
  int unsigned n_issued, n_resp, tot_fill, tot_wb;
  // Current phase (cleared after the directed phase)
  int unsigned n_ld_hit, n_ld_miss, n_st_hit, n_st_miss;
  int unsigned n_cold, n_clean_evict, n_wb_ld, n_wb_st, n_b2b, n_wb_stall;

  // Every non-zero strobe pattern, grouped by kind. Zero is illegal (a_strb_nonzero).
  covergroup strb_cg with function sample(strb_t s);
    coverpoint s {
      bins full           = {4'b1111};
      bins one_byte[]     = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
      bins two_contig[]   = {4'b0011, 4'b0110, 4'b1100};
      bins three_contig[] = {4'b0111, 4'b1110};
      bins non_contig[]   = {4'b0101, 4'b1010, 4'b1001, 4'b1011, 4'b1101};
      illegal_bins zero   = {4'b0000};
    }
  endgroup
  strb_cg strb_cov = new();

  // ---------------------------------------------------------------------------
  // Monitors. Memory requests and CPU responses are watched by separate
  // processes; this is race-free because a miss's memory handshakes are always at
  // least 2 edges before its CPU response, so they never share an edge.
  // ---------------------------------------------------------------------------
  initial begin : mem_monitor
    forever begin
      @(lif.mon_cb);
      if (lif.mon_cb.rst) continue;
      if (lif.mon_cb.req_valid && lif.mon_cb.req_ready)
        seen.push_back('{lif.mon_cb.req_cmd, lif.mon_cb.req_addr, lif.mon_cb.req_wdata});
      if (lif.mon_cb.req_valid && !lif.mon_cb.req_ready && lif.mon_cb.req_cmd == BUS_WB)
        n_wb_stall++;
    end
  end

  initial begin : cpu_monitor
    forever begin
      @(cif.mon_cb);
      cycle++;
      if (cif.mon_cb.rst) continue;

      // A response belongs to an earlier request, so handle it before an accept.
      if (cif.mon_cb.resp_valid) check_response(cif.mon_cb.resp_rdata);

      if (cif.mon_cb.req_valid && cif.mon_cb.req_ready) begin
        pending_t p;
        if (cif.mon_cb.resp_valid) n_b2b++;
        p.addr  = cif.mon_cb.req_addr;
        p.we    = cif.mon_cb.req_we;
        p.cycle = cycle;
        p.pred  = model.access(p.addr, p.we);
        if (p.we) begin
          model.store(p.addr, cif.mon_cb.req_wdata, cif.mon_cb.req_strb);
          strb_cov.sample(cif.mon_cb.req_strb);
        end
        hit_log.push_back(p.pred.hit);
        wb_log.push_back(p.pred.wb);
        pending.push_back(p);
      end
    end
  end

  function automatic void fail(string msg);
    errors++;
    $error("%s", msg);
  endfunction

  function automatic string fmt_reqs(mem_req_t q[$]);
    string s = "";
    foreach (q[i]) s = {s, (i != 0) ? ", " : "", $sformatf("%s 0x%0h", q[i].cmd.name(), q[i].addr)};
    return (q.size() == 0) ? "none" : s;
  endfunction

  function automatic void check_response(word_t rdata);
    pending_t p;
    word_t    exp;
    mem_req_t exp_reqs[$];
    string    what;

    if (pending.size() == 0) begin
      fail("CPU response with no accepted request");
      return;
    end
    p    = pending.pop_front();
    what = $sformatf("%s 0x%08h", p.we ? "Store" : "Load", p.addr);
    n_resp++;

    if (!p.we) begin
      exp = model.load_value(p.addr);
      if (rdata !== exp)
        fail($sformatf("%s: got 0x%08h, expected 0x%08h", what, rdata, exp));
    end

    if (p.pred.hit && cycle - p.cycle != 1)
      fail($sformatf("%s: hit answered after %0d cycles, expected 1", what, cycle - p.cycle));

    // Traffic: exactly the predicted requests, in order.
    if (p.pred.wb)   exp_reqs.push_back('{BUS_WB, p.pred.evict_addr, p.pred.wb_data});
    if (p.pred.fill) exp_reqs.push_back('{p.pred.fill_cmd, p.pred.fill_addr, '0});
    if (seen.size() != exp_reqs.size()) begin
      fail($sformatf("%s: expected memory requests [%s], saw [%s]",
                     what, fmt_reqs(exp_reqs), fmt_reqs(seen)));
    end else begin
      foreach (exp_reqs[i]) begin
        if (seen[i].cmd != exp_reqs[i].cmd || seen[i].addr != exp_reqs[i].addr)
          fail($sformatf("%s: expected memory requests [%s], saw [%s]",
                         what, fmt_reqs(exp_reqs), fmt_reqs(seen)));
        else if (seen[i].cmd == BUS_WB && seen[i].wdata !== exp_reqs[i].wdata)
          fail($sformatf("%s: WriteBack of line 0x%0h has data 0x%064h, expected 0x%064h",
                         what, seen[i].addr, seen[i].wdata, exp_reqs[i].wdata));
      end
    end
    seen.delete();

    if (p.pred.hit) begin
      if (p.we) n_st_hit++; else n_ld_hit++;
    end else begin
      if (p.we) n_st_miss++; else n_ld_miss++;
      tot_fill++;
      if      (!p.pred.evict) n_cold++;
      else if (!p.pred.wb)    n_clean_evict++;
      else if (p.we)          n_wb_st++;
      else                    n_wb_ld++;
      if (p.pred.wb) tot_wb++;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------------------
  // Present one request and hold it until accepted. If wait_resp is 0, return at
  // acceptance so the next request can follow back-to-back.
  task automatic issue(addr_t a, bit we, word_t wdata, strb_t strb, bit wait_resp);
    int unsigned waited = 0;

    n_issued++;
    cif.drv_cb.req_valid <= 1'b1;
    cif.drv_cb.req_we    <= we;
    cif.drv_cb.req_addr  <= a;
    cif.drv_cb.req_wdata <= we ? wdata : '0;
    cif.drv_cb.req_strb  <= we ? strb  : '0;
    do begin
      @(cif.drv_cb);
      if (++waited > TIMEOUT) $fatal(1, "Request 0x%08h not accepted within %0d cycles", a, TIMEOUT);
    end while (!cif.drv_cb.req_ready);
    cif.drv_cb.req_valid <= 1'b0;

    if (wait_resp) begin
      waited = 0;
      do begin
        @(cif.drv_cb);
        if (++waited > TIMEOUT) $fatal(1, "Request 0x%08h not answered within %0d cycles", a, TIMEOUT);
      end while (!cif.drv_cb.resp_valid);
      repeat ($urandom_range(2)) @(cif.drv_cb);
    end
  endtask

  task automatic load(addr_t a, bit wait_resp = 1);
    issue(a, 1'b0, '0, '0, wait_resp);
  endtask

  task automatic store(addr_t a, word_t d, strb_t s, bit wait_resp = 1);
    issue(a, 1'b1, d, s, wait_resp);
  endtask

  task automatic drain();
    int unsigned waited = 0;
    while (pending.size() != 0) begin
      @(cif.drv_cb);
      if (++waited > TIMEOUT) $fatal(1, "Outstanding request never answered");
    end
  endtask

  function automatic addr_t aligned(addr_t a);
    return {a[ADDR_W-1:BYTE_OFF_W], {BYTE_OFF_W{1'b0}}};
  endfunction

  addr_t hot[N_HOT];

  // Next random address. Modes: hot lines (hits), same index as the previous
  // address with a new tag (conflict misses), sequential, uniform.
  function automatic addr_t next_addr(addr_t prev);
    int unsigned mode = $urandom_range(99);
    tag_t        t;

    if (mode < 35) begin
      return aligned(hot[$urandom_range(N_HOT - 1)] | addr_t'($urandom_range(LINE_BYTES - 1)));
    end else if (mode < 55) begin
      // Half the time flip exactly one tag bit: a tag compare that ignores any
      // single bit only fails when two tags differ in just that bit. Otherwise a
      // nonzero offset guarantees a different tag without a retry loop
      // (and avoids an xsim bug with single-statement do-while, docs/bugs.md #2).
      if ($urandom_range(1)) t = get_tag(prev) ^ (tag_t'(1) << $urandom_range(TAG_W - 1));
      else                   t = get_tag(prev) + tag_t'($urandom_range((1 << TAG_W) - 1, 1));
      return aligned({t, get_index(prev), OFFSET_W'($urandom())});
    end else if (mode < 80) begin
      return prev + WORD_BYTES;
    end else begin
      return aligned($urandom());
    end
  endfunction

  task automatic require(bit cond, string what);
    if (!cond) fail($sformatf("Not reached: %s", what));
  endtask

  function automatic void clear_phase_stats();
    n_ld_hit = 0; n_ld_miss = 0; n_st_hit = 0; n_st_miss = 0;
    n_cold = 0; n_clean_evict = 0; n_wb_ld = 0; n_wb_st = 0; n_b2b = 0; n_wb_stall = 0;
  endfunction

  function automatic void print_stats(string phase);
    $display("STATS %s: loads=%0d (hit %0d) stores=%0d (hit %0d) cold=%0d clean_evict=%0d dirty_evict=%0d (load %0d, store %0d) back_to_back=%0d wb_stall_cycles=%0d",
             phase, n_ld_hit + n_ld_miss, n_ld_hit, n_st_hit + n_st_miss, n_st_hit,
             n_cold, n_clean_evict, n_wb_ld + n_wb_st, n_wb_ld, n_wb_st, n_b2b, n_wb_stall);
  endfunction

  // ---------------------------------------------------------------------------
  // Test
  // ---------------------------------------------------------------------------
  localparam addr_t A        = 32'h0000_1040;
  localparam addr_t CONFLICT = A + SETS * LINE_BYTES;  // same set, next tag
  //                       loads                     stores
  logic exp_hits[] = '{0, 1, 1, 0, 0, 1, 1, 1,   1, 1, 0, 0, 1, 1, 0, 0, 1};
  logic exp_wbs[]  = '{0, 0, 0, 0, 0, 0, 0, 0,   0, 0, 1, 0, 0, 0, 1, 1, 0};

  initial begin
    addr_t a;
    bit    we;

    mem   = new(lif);
    model = new();
    // if, not void'(): xsim warns when a system function's result is discarded.
    if ($value$plusargs("N_REQ=%d",         n_req))             $display("PLUSARG: N_REQ");
    if ($value$plusargs("STORE_PCT=%d",     store_pct))         $display("PLUSARG: STORE_PCT");
    if ($value$plusargs("MIN_LAT=%d",       mem.min_lat))       $display("PLUSARG: MIN_LAT");
    if ($value$plusargs("MAX_LAT=%d",       mem.max_lat))       $display("PLUSARG: MAX_LAT");
    if ($value$plusargs("REQ_READY_PCT=%d", mem.req_ready_pct)) $display("PLUSARG: REQ_READY_PCT");
    $display("CONFIG: WAYS=%0d n_req=%0d store_pct=%0d lat=[%0d,%0d] mem req_ready=%0d%%",
             WAYS, n_req, store_pct, mem.min_lat, mem.max_lat, mem.req_ready_pct);

    cif.req_valid = 1'b0;
    fork mem.run(); join_none

    // RESET: marks where warnings stop being tolerated. Before the first reset edge
    // the FSM state is X, so cache_ctrl's unique case warns; sim/run.sh fails on any
    // warning printed after this line.
    repeat (5) @(cif.drv_cb);
    rst <= 1'b0;
    $display("RESET: released at %0d ns", $time);
    @(cif.drv_cb);

    // Directed phase: loads. A (cold), A, A+4 (hits), CONFLICT, A (conflict misses),
    // then A+8, A+12, A+28 back-to-back (hits). A ends in E.
    load(A);
    load(A);
    load(A + 4);
    load(CONFLICT);
    load(A);
    load(A + 8, 0);
    load(A + 12, 0);
    load(A + 28);

    // Directed phase: stores.
    store(A + 4, 32'hA1B2_C3D4, 4'b1111, 0);  // hit on E: A becomes M
    load(A + 4);                              // back-to-back hit sees the store
    load(CONFLICT);                           // dirty victim A: WriteBack A, BusRd
    store(A + 16, 32'h1122_3344, 4'b0101);    // clean victim: no WriteBack; BusRdX, merge 2 bytes
    load(A + 16);                             // hit: merged bytes
    load(A + 4);                              // hit: the store survived WriteBack + refetch
    store(CONFLICT + 8, 32'h5566_7788, 4'b1000);  // dirty victim A: WriteBack A, BusRdX
    load(A);                                  // dirty victim CONFLICT: WriteBack, BusRd
    load(A + 16);                             // hit: merged bytes after a second round trip
    drain();

    if (hit_log.size() != exp_hits.size()) begin
      fail($sformatf("Directed: %0d accesses logged, expected %0d", hit_log.size(), exp_hits.size()));
    end else begin
      foreach (exp_hits[i]) begin
        if (hit_log[i] !== exp_hits[i])
          fail($sformatf("Directed access %0d: model predicted hit=%b, expected %b", i, hit_log[i], exp_hits[i]));
        if (wb_log[i] !== exp_wbs[i])
          fail($sformatf("Directed access %0d: model predicted WriteBack=%b, expected %b", i, wb_log[i], exp_wbs[i]));
      end
    end
    print_stats("directed");
    clear_phase_stats();

    // Random phase
    foreach (hot[i]) hot[i] = {get_line_addr(addr_t'($urandom())), OFFSET_W'(0)};
    a = aligned($urandom());
    for (int unsigned n = 0; n < n_req; n++) begin
      a  = next_addr(a);
      we = ($urandom_range(99) < store_pct);
      if (we) store(a, $urandom(), strb_t'($urandom_range((1 << STRB_W) - 1, 1)), bit'($urandom_range(1)));
      else    load(a, bit'($urandom_range(1)));
    end
    drain();

    print_stats("random");
    $display("STATS run: requests=%0d fills=%0d writebacks=%0d mem_reads=%0d mem_writes=%0d strobe_coverage=%0.1f%%",
             n_issued, tot_fill, tot_wb, mem.n_reads, mem.n_writes, strb_cov.get_coverage());

    // Whole run
    require(n_resp == n_issued,        "every request answered");
    require(mem.n_reads == tot_fill,   "one memory read per miss");
    require(mem.n_writes == tot_wb,    "one memory write per dirty eviction");
    // Random phase
    require(n_cold > 0,                "cold miss");
    require(n_clean_evict + n_wb_ld + n_wb_st > 0, "conflict miss");
    require(n_b2b > 0,                 "back-to-back request");
    if (store_pct < 100) begin
      require(n_ld_hit > 0,            "load hit");
      require(n_ld_miss > 0,           "load miss");
    end
    if (store_pct > 0) begin
      require(n_st_hit > 0,            "store hit");
      require(n_st_miss > 0,           "store miss");
      require(n_wb_st > 0,             "dirty eviction by a store miss");
      require(strb_cov.get_coverage() == 100.0, "every strobe pattern");
      if (mem.req_ready_pct < 100)
        require(n_wb_stall > 0,        "WriteBack held by backpressure");
    end
    if (store_pct > 0 && store_pct < 100) begin
      require(n_wb_ld > 0,             "dirty eviction by a load miss");
      require(n_clean_evict > 0,       "clean eviction");
    end
    if (store_pct == 0)
      require(n_wb_ld + n_wb_st == 0,  "no WriteBack without stores");

    if (errors == 0) $display("TEST PASSED: tb_l1");
    else             $fatal(1, "TEST FAILED: tb_l1, %0d errors", errors);
    $finish;
  end

endmodule
