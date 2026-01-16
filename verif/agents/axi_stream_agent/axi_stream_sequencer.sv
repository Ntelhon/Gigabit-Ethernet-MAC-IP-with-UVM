//==============================================================================
// Class: axi_stream_sequencer
// Description: UVM Sequencer for AXI-Stream transactions
//
// Purpose:
//   Standard UVM sequencer for routing axi_stream_txn objects from sequences
//   to the AXI-Stream driver.
//
// Features:
//   - Standard UVM sequencer functionality
//   - Handles axi_stream_txn transactions
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_stream_sequencer extends uvm_sequencer #(axi_stream_txn);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(axi_stream_sequencer)

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_stream_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : axi_stream_sequencer
