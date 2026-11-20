// tb_l1_read: Stage 1 test of l1_cache loads (direct-mapped).
//
// Directed phase: cold miss, hit, hit to another word, conflict miss, re-miss,
// back-to-back hits. Its hit/miss pattern is also checked against a fixed list,
// which validates the reference model itself.
// Random phase: loads from four address modes (hot lines, same-index conflict,
// sequential, uniform), sometimes issued back-to-back without waiting.
//
// Checks per load (reference model, model_pkg):
//   - data equals the architectural value
//   - a hit responds exactly 1 cycle after acceptance
//   - memory traffic: one BusRd for the predicted line on a miss, none on a hit
// Protocol assertions on both ports are bound into l1_cache.
// Plusargs: +N_REQ= +MIN_LAT= +MAX_LAT= +REQ_READY_PCT=

module tb_l1_read;
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
    .cpu_req_addr   (cif.req_addr),
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
    .req_valid(cpu_req_valid), .req_ready(cpu_req_ready), .req_addr(cpu_req_addr),
    .resp_valid(cpu_resp_valid)
  );

  mem_model   mem;
  cache_model model;

  typedef struct {
    addr_t           addr;
    longint unsigned cycle;
    access_t         pred;
  } pending_t;

  typedef struct {
    bus_cmd_e   cmd;
    line_addr_t addr;
  } mem_req_t;

  pending_t        pending[$];   // accepted, not yet answered (at most one)
  mem_req_t        seen[$];      // memory requests since the last CPU response
  logic            hit_log[$];   // predicted hit/miss per access, in order
  longint unsigned cycle;
  int unsigned     n_req = 3000;
  int unsigned     errors;
  int unsigned     n_resp, n_hits, n_cold, n_conflict, n_b2b;

  // ---------------------------------------------------------------------------
  // Monitors. Memory requests and CPU responses are watched by separate
  // processes; this is race-free because a miss's memory handshake is always at
  // least 2 edges before its CPU response, so the two never share an edge.
  // ---------------------------------------------------------------------------
  initial begin : mem_monitor
    forever begin
      @(lif.mon_cb);
      if (!lif.mon_cb.rst && lif.mon_cb.req_valid && lif.mon_cb.req_ready)
        seen.push_back('{lif.mon_cb.req_cmd, lif.mon_cb.req_addr});
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
        p.cycle = cycle;
        p.pred  = model.access(p.addr);
        hit_log.push_back(p.pred.hit);
        pending.push_back(p);
      end
    end
  end

  function automatic void fail(string msg);
    errors++;
    $error("%s", msg);
  endfunction

  function automatic void check_response(word_t rdata);
    pending_t p;
    word_t    exp;

    if (pending.size() == 0) begin
      fail("CPU response with no accepted request");
      return;
    end
    p   = pending.pop_front();
    exp = model.load_value(p.addr);
    n_resp++;

    if (rdata !== exp)
      fail($sformatf("Load 0x%08h: got 0x%08h, expected 0x%08h", p.addr, rdata, exp));

    if (p.pred.hit && cycle - p.cycle != 1)
      fail($sformatf("Hit 0x%08h answered after %0d cycles, expected 1", p.addr, cycle - p.cycle));

    if (p.pred.fill) begin
      if (seen.size() != 1 || seen[0].cmd != BUS_RD || seen[0].addr != p.pred.fill_addr)
        fail($sformatf("Miss 0x%08h: expected one BusRd of line 0x%0h, saw %0d request(s)%s",
                       p.addr, p.pred.fill_addr, seen.size(),
                       seen.size() != 0 ? $sformatf(", first %s 0x%0h", seen[0].cmd.name(), seen[0].addr) : ""));
    end else if (seen.size() != 0) begin
      fail($sformatf("Hit 0x%08h caused %0d memory request(s)", p.addr, seen.size()));
    end
    seen.delete();

    if      (p.pred.hit)   n_hits++;
    else if (p.pred.evict) n_conflict++;
    else                   n_cold++;
  endfunction

  // ---------------------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------------------
  // Present one load and hold it until accepted. If wait_resp is 0, return at
  // acceptance so the next load can follow back-to-back.
  task automatic issue(addr_t a, bit wait_resp);
    int unsigned waited = 0;

    cif.drv_cb.req_valid <= 1'b1;
    cif.drv_cb.req_addr  <= a;
    do begin
      @(cif.drv_cb);
      if (++waited > TIMEOUT) $fatal(1, "Load 0x%08h not accepted within %0d cycles", a, TIMEOUT);
    end while (!cif.drv_cb.req_ready);
    cif.drv_cb.req_valid <= 1'b0;

    if (wait_resp) begin
      waited = 0;
      do begin
        @(cif.drv_cb);
        if (++waited > TIMEOUT) $fatal(1, "Load 0x%08h not answered within %0d cycles", a, TIMEOUT);
      end while (!cif.drv_cb.resp_valid);
      repeat ($urandom_range(2)) @(cif.drv_cb);
    end
  endtask

  task automatic drain();
    int unsigned waited = 0;
    while (pending.size() != 0) begin
      @(cif.drv_cb);
      if (++waited > TIMEOUT) $fatal(1, "Outstanding load never answered");
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

  // ---------------------------------------------------------------------------
  // Test
  // ---------------------------------------------------------------------------
  // Directed: A (cold), A, A+4 (hits), A+2K (conflict), A (conflict),
  // then A+8, A+12, A+28 back-to-back (hits).
  localparam addr_t A        = 32'h0000_1040;
  localparam addr_t CONFLICT = A + SETS * LINE_BYTES;  // same set, next tag
  logic exp_hits[] = '{0, 1, 1, 0, 0, 1, 1, 1};

  initial begin
    addr_t a;

    mem   = new(lif);
    model = new();
    // if, not void'(): xsim warns when a system function's result is discarded.
    if ($value$plusargs("N_REQ=%d",         n_req))             $display("PLUSARG: N_REQ");
    if ($value$plusargs("MIN_LAT=%d",       mem.min_lat))       $display("PLUSARG: MIN_LAT");
    if ($value$plusargs("MAX_LAT=%d",       mem.max_lat))       $display("PLUSARG: MAX_LAT");
    if ($value$plusargs("REQ_READY_PCT=%d", mem.req_ready_pct)) $display("PLUSARG: REQ_READY_PCT");
    $display("CONFIG: WAYS=%0d n_req=%0d lat=[%0d,%0d] mem req_ready=%0d%%",
             WAYS, n_req, mem.min_lat, mem.max_lat, mem.req_ready_pct);

    cif.req_valid = 1'b0;
    fork mem.run(); join_none

    // RESET: marks where warnings stop being tolerated. Before the first reset edge
    // the FSM state is X, so cache_ctrl's unique case warns; sim/run.sh fails on any
    // warning printed after this line.
    repeat (5) @(cif.drv_cb);
    rst <= 1'b0;
    $display("RESET: released at %0d ns", $time);
    @(cif.drv_cb);

    // Directed phase
    issue(A, 1);
    issue(A, 1);
    issue(A + 4, 1);
    issue(CONFLICT, 1);
    issue(A, 1);
    issue(A + 8, 0);
    issue(A + 12, 0);
    issue(A + 28, 1);
    drain();

    if (hit_log.size() != exp_hits.size()) begin
      fail($sformatf("Directed: %0d accesses logged, expected %0d", hit_log.size(), exp_hits.size()));
    end else begin
      foreach (exp_hits[i])
        if (hit_log[i] !== exp_hits[i])
          fail($sformatf("Directed access %0d: model predicted hit=%b, expected %b", i, hit_log[i], exp_hits[i]));
    end

    // Random phase
    foreach (hot[i]) hot[i] = {get_line_addr(addr_t'($urandom())), OFFSET_W'(0)};
    a = aligned($urandom());
    for (int unsigned n = 0; n < n_req; n++) begin
      a = next_addr(a);
      issue(a, bit'($urandom_range(1)));
    end
    drain();

    $display("STATS: loads=%0d hits=%0d cold=%0d conflict=%0d back_to_back=%0d mem_reads=%0d",
             n_resp, n_hits, n_cold, n_conflict, n_b2b, mem.n_reads);

    require(n_resp == n_req + unsigned'(exp_hits.size()), "every load answered");
    require(n_hits > 0,                         "hit");
    require(n_cold > 0,                         "cold miss");
    require(n_conflict > 0,                     "conflict miss");
    require(n_b2b > 0,                          "back-to-back request");
    require(mem.n_reads == n_cold + n_conflict, "one memory read per miss");
    require(mem.n_writes == 0,                  "no memory writes (loads only)");

    if (errors == 0) $display("TEST PASSED: tb_l1_read");
    else             $fatal(1, "TEST FAILED: tb_l1_read, %0d errors", errors);
    $finish;
  end

endmodule
