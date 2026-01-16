//==============================================================================
// Class: axi_lite_sequencer
// Description: UVM Sequencer for AXI4-Lite transactions
//
// Purpose:
//   Standard UVM sequencer that manages the flow of axi_lite_txn transactions
//   from sequences to the AXI-Lite driver.
//
// Features:
//   - Standard UVM sequencer functionality
//   - Manages axi_lite_txn sequence items
//   - In-order transaction delivery (no reordering)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_lite_sequencer extends uvm_sequencer #(axi_lite_txn);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(axi_lite_sequencer)

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_lite_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction

endclass : axi_lite_sequencer
