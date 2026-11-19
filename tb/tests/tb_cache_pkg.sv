// tb_cache_pkg: self-checking test for cache_pkg.
// Every bit-slice helper is compared against a model built from division and
// modulo, so a wrong slice cannot agree with its own reference.

module tb_cache_pkg;
  import cache_pkg::*;

  localparam int unsigned N_RANDOM = 10000;

  int unsigned errors = 0;

  // Report a mismatch with enough context to reproduce it.
  task automatic check(string what, longint unsigned got, longint unsigned exp, addr_t a);
    if (got !== exp) begin
      errors++;
      $error("%s mismatch for addr 0x%08h: got 0x%0h, expected 0x%0h", what, a, got, exp);
    end
  endtask

  // Reference model: field values from arithmetic on the byte address.
  task automatic check_addr(addr_t a);
    longint unsigned ua = 64'(a);
    addr_t           rebuilt;

    check("tag",       64'(get_tag(a)),       ua / (SETS * LINE_BYTES),           a);
    check("index",     64'(get_index(a)),     (ua / LINE_BYTES) % SETS,           a);
    check("word_off",  64'(get_word_off(a)),  (ua / WORD_BYTES) % WORDS_PER_LINE, a);
    check("line_addr", 64'(get_line_addr(a)), ua / LINE_BYTES,                    a);

    // Round trip: {tag, index} + word offset + byte 0 rebuilds the word-aligned address.
    rebuilt = {make_line_addr(get_tag(a), get_index(a)), get_word_off(a), {BYTE_OFF_W{1'b0}}};
    check("round trip", 64'(rebuilt), ua - (ua % WORD_BYTES), a);
  endtask

  initial begin
    // Derived widths must tile the address exactly and match the geometry.
    check("TAG+INDEX+OFFSET", TAG_W + INDEX_W + OFFSET_W, ADDR_W, '0);
    check("LINE_ADDR_W",      LINE_ADDR_W, TAG_W + INDEX_W, '0);
    check("2**INDEX_W",       1 << INDEX_W, SETS, '0);
    check("2**OFFSET_W",      1 << OFFSET_W, LINE_BYTES, '0);
    check("2**WORD_OFF_W",    1 << WORD_OFF_W, WORDS_PER_LINE, '0);
    check("2**BYTE_OFF_W",    1 << BYTE_OFF_W, WORD_BYTES, '0);
    check("LINE_W",           WORDS_PER_LINE * WORD_W, LINE_W, '0);
    check("WAY_W covers WAYS", (1 << WAY_W) >= WAYS, 1, '0);

    // Directed edges: all zeros, all ones, each field boundary.
    check_addr(32'h0000_0000);
    check_addr(32'hFFFF_FFFF);
    check_addr(32'h0000_001C);  // last word of line 0
    check_addr(32'h0000_0020);  // first word of set 1
    check_addr(32'h0000_07E0);  // set 63
    check_addr(32'h0000_0800);  // tag 1, set 0: same set as address 0
    check_addr(32'h1234_5678);

    // Random addresses (seed from -sv_seed).
    repeat (N_RANDOM) check_addr($urandom());

    // State helpers.
    check("is_valid(I)", is_valid(MESI_I), 0, '0);
    check("is_valid(S)", is_valid(MESI_S), 1, '0);
    check("is_valid(E)", is_valid(MESI_E), 1, '0);
    check("is_valid(M)", is_valid(MESI_M), 1, '0);
    check("is_dirty(I)", is_dirty(MESI_I), 0, '0);
    check("is_dirty(S)", is_dirty(MESI_S), 0, '0);
    check("is_dirty(E)", is_dirty(MESI_E), 0, '0);
    check("is_dirty(M)", is_dirty(MESI_M), 1, '0);

    if (errors == 0) $display("TEST PASSED: tb_cache_pkg (WAYS=%0d, %0d random addresses)", WAYS, N_RANDOM);
    else             $fatal(1, "TEST FAILED: tb_cache_pkg, %0d errors", errors);
    $finish;
  end
endmodule
