//==============================================================================
// Class: mac_virtual_sequencer
// Description: Virtual sequencer for coordinating MAC verification
//
// Purpose:
//   Provides a central coordination point for running sequences across
//   multiple agents (GMII and AXI-Lite). Enables complex test scenarios
//   that require synchronized register programming and frame transmission.
//
// Responsibilities:
//   - Coordinate register programming via AXI-Lite
//   - Coordinate frame transmission via GMII
//   - Enable error injection scenarios
//   - No protocol logic (pure coordination)
//
// Sub-Sequencers:
//   - axi_lite_sqr:  AXI-Lite sequencer for register access
//   - gmii_sqr: GMII sequencer for frame transmission
//
// Usage:
//   Virtual sequences access sub-sequencers via handles:
//     `p_sequencer.axi_lite_sqr.start(...)
//     `p_sequencer.gmii_sqr.start(...)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_virtual_sequencer extends uvm_sequencer;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_virtual_sequencer)

    //==========================================================================
    // Sub-Sequencer Handles
    //==========================================================================
    
    // AXI-Lite sequencer for register access
    axi_lite_sequencer axi_lite_sqr;
    
    // GMII sequencer for frame transmission (RX to MAC)
    gmii_sequencer gmii_sqr;
    
    // AXI-Stream sequencer for TX/RX data path
    axi_stream_sequencer axis_sqr;


    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : mac_virtual_sequencer
