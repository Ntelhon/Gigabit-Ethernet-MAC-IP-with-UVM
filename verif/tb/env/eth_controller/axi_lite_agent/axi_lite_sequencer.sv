// File: tb/env/eth_controller/axi_lite_agent/axi_lite_sequencer.sv
class axi_lite_sequencer #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 32
) extends uvm_sequencer #(axi_lite_item#(ADDR_WIDTH, DATA_WIDTH));

  `uvm_component_param_utils(axi_lite_sequencer#(ADDR_WIDTH, DATA_WIDTH))

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : axi_lite_sequencer
