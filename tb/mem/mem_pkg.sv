// mem_pkg: testbench memory model for the line channel.
// Slave side of one line_if. One request at a time, random latency, random
// request backpressure. Sparse storage: lines never written read back a fixed
// pattern computed from the address (mem_init_line), so the reference model can
// predict any line without sharing state with this model.

package mem_pkg;
  import cache_pkg::*;

  // Initial content of every word: its own byte address with the upper half
  // inverted. Readable in waveforms (low half = address) but never equal to the
  // address, so a bug that routes address into data cannot pass.
  function automatic word_t mem_init_word(line_addr_t la, word_off_t w);
    addr_t a = {la, w, {BYTE_OFF_W{1'b0}}};
    return word_t'(a) ^ {{(WORD_W/2){1'b1}}, {(WORD_W/2){1'b0}}};
  endfunction

  function automatic line_t mem_init_line(line_addr_t la);
    line_t l;
    for (int unsigned w = 0; w < WORDS_PER_LINE; w++)
      l[w*WORD_W +: WORD_W] = mem_init_word(la, word_off_t'(w));
    return l;
  endfunction

  class mem_model;

    // ---- Configuration (set before run) --------------------------------------
    // Latency L: resp_valid rises L cycles after the earliest possible cycle,
    // which is the cycle right after the request is accepted.
    int unsigned min_lat       = 1;
    int unsigned max_lat       = 10;
    int unsigned req_ready_pct = 70;  // chance per idle cycle that req_ready is high

    // ---- Statistics -----------------------------------------------------------
    int unsigned n_reads;
    int unsigned n_writes;
    int unsigned n_upgr_errors;

    virtual line_if vif;
    local line_t    mem[line_addr_t];

    function new(virtual line_if vif);
      this.vif = vif;
    endfunction

    // Backdoor access, no timing. Tests use these to inspect or preload memory.
    function line_t peek(line_addr_t la);
      return mem.exists(la) ? mem[la] : mem_init_line(la);
    endfunction

    function void poke(line_addr_t la, line_t data);
      mem[la] = data;
    endfunction

    local function bit coin(int unsigned pct);
      return ($urandom_range(99) < pct);
    endfunction

    // Response to drive for an accepted request. A WriteBack response carries
    // random data so a master that wrongly uses it gets garbage, not a plausible line.
    local function line_t serve(bus_cmd_e cmd, line_addr_t la, line_t wdata);
      unique case (cmd)
        BUS_RD, BUS_RDX: begin
          n_reads++;
          return peek(la);
        end
        BUS_WB: begin
          n_writes++;
          poke(la, wdata);
          return {(LINE_W/32){$urandom()}};
        end
        BUS_UPGR: begin
          n_upgr_errors++;
          $error("mem_model: BusUpgr reached memory (line 0x%0h)", la);
          return {(LINE_W/32){$urandom()}};
        end
      endcase
    endfunction

    task run();
      bit          ready_q = 1'b0;  // req_ready as driven for the cycle just sampled
      bit          busy    = 1'b0;  // a request has been accepted, response not yet done
      bit          resp_q  = 1'b0;  // resp_valid as driven for the cycle just sampled
      int unsigned wait_cycles;
      line_t       resp_data;

      vif.slv_cb.req_ready   <= 1'b0;
      vif.slv_cb.resp_valid  <= 1'b0;
      vif.slv_cb.resp_rdata  <= 'x;
      vif.slv_cb.resp_shared <= 1'b0;

      forever begin
        @(vif.slv_cb);

        if (vif.slv_cb.rst) begin
          ready_q = 1'b0; busy = 1'b0; resp_q = 1'b0;
          vif.slv_cb.req_ready  <= 1'b0;
          vif.slv_cb.resp_valid <= 1'b0;
          vif.slv_cb.resp_rdata <= 'x;
          continue;
        end

        // Response handshake completes at this edge.
        if (resp_q && vif.slv_cb.resp_ready) begin
          resp_q = 1'b0;
          busy   = 1'b0;
          vif.slv_cb.resp_valid <= 1'b0;
          vif.slv_cb.resp_rdata <= 'x;
        end

        // Request handshake completes at this edge.
        if (!busy && ready_q && vif.slv_cb.req_valid) begin
          busy        = 1'b1;
          resp_data   = serve(vif.slv_cb.req_cmd, vif.slv_cb.req_addr, vif.slv_cb.req_wdata);
          wait_cycles = $urandom_range(max_lat, min_lat);
        end else if (busy && !resp_q && wait_cycles > 0) begin
          wait_cycles--;
        end

        // Raise the response once the latency has elapsed; hold it until accepted.
        if (busy && !resp_q && wait_cycles == 0) begin
          resp_q = 1'b1;
          vif.slv_cb.resp_valid <= 1'b1;
          vif.slv_cb.resp_rdata <= resp_data;
        end

        // Ready only while idle, randomly. It may rise without valid (allowed by the rules).
        ready_q = !busy && coin(req_ready_pct);
        vif.slv_cb.req_ready <= ready_q;
      end
    endtask

  endclass

endpackage
