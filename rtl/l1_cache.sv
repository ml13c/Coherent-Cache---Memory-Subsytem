// l1_cache: one L1 data cache. Wires the controller to its two storage arrays.
// This is the unit verified on its own (Stages 1-4) and synthesized (Stage 5).

module l1_cache
  import cache_pkg::*;
(
  input  logic       clk,
  input  logic       rst,

  // CPU port (loads)
  input  logic       cpu_req_valid,
  output logic       cpu_req_ready,
  input  addr_t      cpu_req_addr,
  output logic       cpu_resp_valid,
  output word_t      cpu_resp_rdata,

  // Line channel to memory (master)
  output logic       mem_req_valid,
  input  logic       mem_req_ready,
  output bus_cmd_e   mem_req_cmd,
  output line_addr_t mem_req_addr,
  output line_t      mem_req_wdata,
  input  logic       mem_resp_valid,
  output logic       mem_resp_ready,
  input  line_t      mem_resp_rdata,
  input  logic       mem_resp_shared
);

  index_t                tag_rd_index;
  tag_t                  tag_rd_tag   [WAYS];
  mesi_e                 tag_rd_state [WAYS];
  logic                  tag_wr_en;
  index_t                tag_wr_index;
  way_t                  tag_wr_way;
  tag_t                  tag_wr_tag;
  mesi_e                 tag_wr_state;

  logic                  data_en;
  index_t                data_addr;
  logic [LINE_BYTES-1:0] data_we    [WAYS];
  line_t                 data_wdata;
  line_t                 data_rdata [WAYS];

  tag_array u_tags (
    .clk, .rst,
    .rd_index (tag_rd_index), .rd_tag  (tag_rd_tag), .rd_state(tag_rd_state),
    .wr_en    (tag_wr_en),    .wr_index(tag_wr_index), .wr_way(tag_wr_way),
    .wr_tag   (tag_wr_tag),   .wr_state(tag_wr_state)
  );

  data_array u_data (
    .clk,
    .en(data_en), .addr(data_addr), .we(data_we), .wdata(data_wdata), .rdata(data_rdata)
  );

  cache_ctrl u_ctrl (.*);

endmodule
