// File: tb/agents/gmii/gmii_sequencer.sv
class gmii_sequencer extends uvm_sequencer #(gmii_item);
  `uvm_component_utils(gmii_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : gmii_sequencer
