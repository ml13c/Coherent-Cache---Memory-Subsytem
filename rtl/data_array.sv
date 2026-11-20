// data_array: line data, one block RAM per way. Storage only, no policy.
// Registered read (data arrives the cycle after en), one write enable per byte.
// All ways share the address so a lookup reads every way of the set at once.
// Port B for snoop reads is added in Stage 6.

module data_array
  import cache_pkg::*;
(
  input  logic                  clk,
  input  logic                  en,
  input  index_t                addr,
  input  logic [LINE_BYTES-1:0] we    [WAYS],
  input  line_t                 wdata,
  output line_t                 rdata [WAYS]
);

  for (genvar w = 0; w < WAYS; w++) begin : g_way
    line_t mem [SETS];

    always_ff @(posedge clk) begin
      if (en) begin
        for (int unsigned b = 0; b < LINE_BYTES; b++)
          if (we[w][b]) mem[addr][b*8 +: 8] <= wdata[b*8 +: 8];
        rdata[w] <= mem[addr];
      end
    end
  end

endmodule
