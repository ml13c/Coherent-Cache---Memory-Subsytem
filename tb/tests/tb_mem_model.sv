// tb_mem_model: random test of the memory model on its own.
// A master that obeys the handshake rules sends random BusRd/BusRdX/WriteBack
// requests with random gaps and random response backpressure. Checks:
//   - read data matches a shadow memory (written lines) or mem_init_line (never written)
//   - latency stays within [min_lat, max_lat]
//   - handshake and pairing rules (line_channel_sva, bound below)
//   - the stress actually happened: both latency extremes, stalls on both channels,
//     reads of written and never-written lines
// Plusargs: +N_TXN= +MIN_LAT= +MAX_LAT= +REQ_READY_PCT= +RESP_READY_PCT=

module tb_mem_model;
  import cache_pkg::*;
  import mem_pkg::*;

  localparam realtime     CLK_PERIOD = 10ns;   // 100 MHz
  localparam int unsigned HOT_LINES  = 8;      // small address pool so reads hit written lines
  localparam int unsigned TIMEOUT    = 1000;   // cycles waiting on one handshake = hang

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #(CLK_PERIOD / 2) clk = ~clk;

  line_if lif (.clk, .rst);

  // Protocol checker on the channel. An interface cannot hold module instances,
  // so it is instantiated here; from Stage 1 it is bound into l1_cache's memory port.
  line_channel_sva #(.NAME("mem_if")) u_line_sva (
    .clk, .rst,
    .req_valid (lif.req_valid),  .req_ready (lif.req_ready),  .req_cmd (lif.req_cmd),
    .req_addr  (lif.req_addr),   .req_wdata (lif.req_wdata),
    .resp_valid(lif.resp_valid), .resp_ready(lif.resp_ready), .resp_rdata(lif.resp_rdata),
    .resp_shared(lif.resp_shared)
  );

  mem_model mem;

  // Test configuration
  int unsigned n_txn          = 2000;
  int unsigned resp_ready_pct = 60;

  // Shadow memory and statistics
  line_t       shadow[line_addr_t];
  line_addr_t  hot[HOT_LINES];
  int unsigned errors;
  int unsigned n_rd_written, n_rd_init, n_req_stalls, n_resp_stalls;
  int unsigned lat_min_seen = '1, lat_max_seen = 0;

  // ---------------------------------------------------------------------------
  // Master side: one request at a time, rules from docs/architecture.md
  // ---------------------------------------------------------------------------
  task automatic do_txn(bus_cmd_e cmd, line_addr_t la, line_t wdata);
    int unsigned lat, waited;
    bit          rready;
    line_t       exp;

    // Random idle gap before the request.
    repeat ($urandom_range(3)) @(lif.mst_cb);

    lif.mst_cb.req_valid <= 1'b1;
    lif.mst_cb.req_cmd   <= cmd;
    lif.mst_cb.req_addr  <= la;
    lif.mst_cb.req_wdata <= wdata;

    // Hold valid and payload until ready.
    waited = 0;
    do begin
      @(lif.mst_cb);
      if (!lif.mst_cb.req_ready) begin
        n_req_stalls++;
        if (++waited > TIMEOUT) $fatal(1, "Request not accepted within %0d cycles", TIMEOUT);
      end
    end while (!lif.mst_cb.req_ready);

    lif.mst_cb.req_valid <= 1'b0;
    lif.mst_cb.req_wdata <= 'x;  // payload is don't-care once valid drops

    // Wait for the response, counting cycles from acceptance.
    // resp_ready is a clocking-block output and cannot be read back, so keep a copy.
    lat    = 0;
    waited = 0;
    do begin
      rready = ($urandom_range(99) < resp_ready_pct);
      lif.mst_cb.resp_ready <= rready;
      @(lif.mst_cb);
      if (!lif.mst_cb.resp_valid) lat++;
      else if (!rready)           n_resp_stalls++;
      if (++waited > TIMEOUT) $fatal(1, "Response not completed within %0d cycles (line 0x%0h)", TIMEOUT, la);
    end while (!(lif.mst_cb.resp_valid && rready));
    lif.mst_cb.resp_ready <= 1'b0;

    // lat counts cycles with resp_valid low after acceptance = the model's L.
    if (lat < mem.min_lat || lat > mem.max_lat) begin
      errors++;
      $error("Latency %0d outside [%0d, %0d]", lat, mem.min_lat, mem.max_lat);
    end
    if (lat < lat_min_seen) lat_min_seen = lat;
    if (lat > lat_max_seen) lat_max_seen = lat;

    if (lif.mst_cb.resp_shared !== 1'b0) begin
      errors++;
      $error("Memory drove resp_shared = %b", lif.mst_cb.resp_shared);
    end

    if (cmd == BUS_WB) begin
      shadow[la] = wdata;
    end else begin
      if (shadow.exists(la)) begin exp = shadow[la]; n_rd_written++; end
      else                   begin exp = mem_init_line(la); n_rd_init++; end
      if (lif.mst_cb.resp_rdata !== exp) begin
        errors++;
        $error("Read 0x%0h: got %h, expected %h", la, lif.mst_cb.resp_rdata, exp);
      end
    end
  endtask

  function automatic line_t rand_line();
    line_t l;
    for (int unsigned i = 0; i < LINE_W / 32; i++) l[i*32 +: 32] = $urandom();
    return l;
  endfunction

  // Stress evidence: a passing run must show the behavior it claims to test.
  task automatic require(bit cond, string what);
    if (!cond) begin
      errors++;
      $error("Stress not reached: %s", what);
    end
  endtask

  initial begin
    bus_cmd_e   cmd;
    line_addr_t la;
    int unsigned pick;

    mem = new(lif);
    void'($value$plusargs("N_TXN=%d",          n_txn));
    void'($value$plusargs("MIN_LAT=%d",        mem.min_lat));
    void'($value$plusargs("MAX_LAT=%d",        mem.max_lat));
    void'($value$plusargs("REQ_READY_PCT=%d",  mem.req_ready_pct));
    void'($value$plusargs("RESP_READY_PCT=%d", resp_ready_pct));
    $display("CONFIG: n_txn=%0d lat=[%0d,%0d] req_ready=%0d%% resp_ready=%0d%%",
             n_txn, mem.min_lat, mem.max_lat, mem.req_ready_pct, resp_ready_pct);

    foreach (hot[i]) hot[i] = line_addr_t'($urandom());

    lif.req_valid  = 1'b0;
    lif.resp_ready = 1'b0;

    fork mem.run(); join_none

    // Release reset, then idle one cycle: the edge that releases rst still samples
    // it high, and valid must be low in the cycle after any reset cycle.
    // Wait only on the clocking block: mixing @(posedge clk) and @(lif.mst_cb) in one
    // process lets both return in the same timestep (docs/bugs.md #1).
    repeat (5) @(lif.mst_cb);
    rst <= 1'b0;
    @(lif.mst_cb);

    for (int unsigned t = 0; t < n_txn; t++) begin
      pick = $urandom_range(99);
      cmd  = (pick < 40) ? BUS_RD : (pick < 60) ? BUS_RDX : BUS_WB;
      la   = ($urandom_range(99) < 70) ? hot[$urandom_range(HOT_LINES - 1)]
                                       : line_addr_t'($urandom());
      do_txn(cmd, la, rand_line());
    end

    $display("STATS: reads=%0d (written %0d, init %0d) writes=%0d lat_seen=[%0d,%0d] req_stalls=%0d resp_stalls=%0d",
             mem.n_reads, n_rd_written, n_rd_init, mem.n_writes, lat_min_seen, lat_max_seen,
             n_req_stalls, n_resp_stalls);

    require(mem.n_reads + mem.n_writes == n_txn, "every request served once");
    require(n_rd_written > 0,                   "read of a written line");
    require(n_rd_init > 0,                      "read of a never-written line");
    require(lat_min_seen == mem.min_lat,        "minimum latency");
    require(lat_max_seen == mem.max_lat,        "maximum latency");
    if (mem.req_ready_pct < 100) require(n_req_stalls > 0,  "request backpressure");
    if (resp_ready_pct < 100)    require(n_resp_stalls > 0, "response backpressure");
    if (mem.n_upgr_errors != 0) errors++;

    if (errors == 0) $display("TEST PASSED: tb_mem_model");
    else             $fatal(1, "TEST FAILED: tb_mem_model, %0d errors", errors);
    $finish;
  end

endmodule
