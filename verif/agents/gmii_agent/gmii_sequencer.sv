//==============================================================================
// Class: gmii_sequencer
// Description: UVM Sequencer for GMII transactions
//
// Purpose:
//   Standard UVM sequencer that manages the flow of gmii_frame transactions
//   from sequences to the GMII driver. Provides arbitration and flow control
//   for frame transmission.
//
// Features:
//   - Standard UVM sequencer functionality
//   - Manages gmii_frame sequence items
//   - Supports multiple concurrent sequences (with arbitration)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_sequencer extends uvm_sequencer #(gmii_frame);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(gmii_sequencer)

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "gmii_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction

endclass : gmii_sequencer
