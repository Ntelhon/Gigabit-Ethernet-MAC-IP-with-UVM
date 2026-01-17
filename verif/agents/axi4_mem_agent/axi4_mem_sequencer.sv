//==============================================================================
// Class: axi4_mem_sequencer
// Description: Sequencer for AXI4 memory transactions
//==============================================================================

class axi4_mem_sequencer extends uvm_sequencer #(axi4_mem_txn);
    `uvm_component_utils(axi4_mem_sequencer)

    function new(string name = "axi4_mem_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : axi4_mem_sequencer
