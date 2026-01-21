//==============================================================================
// Package: gmii_agent_pkg
// Description: UVM package for GMII agent components
//
// Purpose:
//   Consolidates all GMII agent classes into a single package for easy
//   import into testbench environments.
//
// Contents:
//   - gmii_frame:     Transaction class for Ethernet frames
//   - gmii_driver:    Driver for RX path (PHY -> MAC)
//   - gmii_monitor:   Monitor for TX path (MAC -> PHY)
//   - gmii_sequencer: Sequencer for frame transactions
//   - gmii_agent:     Agent container
//   - gmii_agent_config: Configuration object
//
// Usage:
//   import gmii_agent_pkg::*;
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package gmii_agent_pkg;

    //==========================================================================
    // Import UVM package
    //==========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //==========================================================================
    // Include agent files in dependency order
    //==========================================================================
    
    // Transaction class (no dependencies)
    `include "gmii_frame.sv"
    
    // Sequence (depends on gmii_frame)
    `include "gmii_sequence.sv"
    
    // Sequencer (depends on gmii_frame)
    `include "gmii_sequencer.sv"
    
    // Driver (depends on gmii_frame)
    `include "gmii_driver.sv"
    
    // Monitor (depends on gmii_frame)
    `include "gmii_monitor.sv"
    
    // Agent (depends on all above)
    `include "gmii_agent.sv"

endpackage : gmii_agent_pkg
