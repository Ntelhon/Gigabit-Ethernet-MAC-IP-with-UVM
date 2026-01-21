//==============================================================================
// Class: mac_base_test
// Description: Base test class for all MAC directed tests
//
// Purpose:
//   Provides common setup and configuration for MAC-only tests.
//   This extends eth_base_test with MAC-only configuration and provides
//   convenient access to MAC sequencers.
//
// Features:
//   - MAC-only testing (DMA disabled)
//   - Inherits all eth_base_test functionality
//   - Provides mac_sqr handle for easy sequence starting
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_base_test extends eth_base_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_base_test)

    //==========================================================================
    // Convenience Handles for MAC Sequences
    //==========================================================================
    mac_virtual_sequencer mac_sqr;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_base_test", uvm_component parent = null);
        super.new(name, parent);
        // Configure for MAC-only testing
        enable_mac = 1;
        enable_dma = 0;
    endfunction

    //==========================================================================
    // Connect Phase - Set up convenience handles
    //==========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (env.v_sqr.mac_sqr != null) begin
            mac_sqr = env.v_sqr.mac_sqr;
        end else begin
            `uvm_warning("TEST", "MAC sequencer not available")
        end
    endfunction

endclass : mac_base_test
