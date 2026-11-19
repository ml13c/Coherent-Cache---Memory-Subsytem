# Source list, compile order, paths relative to the repo root.
# sim/run.sh reads this; lines starting with # are ignored.

# RTL
rtl/cache_pkg.sv

# Testbench infrastructure
tb/env/line_if.sv
tb/sva/handshake_sva.sv
tb/sva/line_channel_sva.sv
tb/mem/mem_pkg.sv

# Test tops
tb/tests/tb_cache_pkg.sv
tb/tests/tb_mem_model.sv
