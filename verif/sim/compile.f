# File: sim/compile.f

# UVM Library
+incdir+$UVM_HOME/src
$UVM_HOME/src/uvm_pkg.sv

# Interfaces
tb/top/clk_rst_if.sv
tb/agents/axi_stream/axi_stream_if.sv
tb/agents/axi4/axi4_if.sv
tb/env/eth_controller/axi_lite_agent/axi_lite_if.sv
tb/agents/gmii/gmii_if.sv

# Package
tb/top/eth_pkg.sv

# Testbench Top
tb/top/eth_tb_top.sv

# RTL Files (add actual RTL paths)
# rtl/mac/mac_top.sv
# rtl/dma/dma_top.sv
# rtl/eth_controller_wrapper.sv
