# Source list, compile order, paths relative to the repo root.
# sim/run.sh reads this; lines starting with # are ignored.

# RTL
rtl/cache_pkg.sv
rtl/tag_array.sv
rtl/data_array.sv
rtl/cache_ctrl.sv
rtl/l1_cache.sv

# Testbench infrastructure
tb/env/line_if.sv
tb/env/cpu_if.sv
tb/sva/handshake_sva.sv
tb/sva/line_channel_sva.sv
tb/sva/cpu_port_sva.sv
tb/mem/mem_pkg.sv
tb/model/model_pkg.sv

# Test tops
tb/tests/tb_cache_pkg.sv
tb/tests/tb_mem_model.sv
tb/tests/tb_l1_read.sv
