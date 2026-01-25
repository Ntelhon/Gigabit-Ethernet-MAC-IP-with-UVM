// File: tb/agents/axi4/axi4_sequencer.sv
class axi4_sequencer #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 64,
  int ID_WIDTH   = 4,
  int USER_WIDTH = 1
) extends uvm_sequencer #(axi4_item#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH));

  `uvm_component_param_utils(axi4_sequencer#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH))

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : axi4_sequencer
