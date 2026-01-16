//==============================================================================
// Package: axi_stream_agent_pkg
// Description: UVM Package for AXI-Stream Agent
//
// Purpose:
//   Encapsulates all AXI-Stream agent components in a single package for
//   easy import into the verification environment.
//
// Contents:
//   - axi_stream_txn: Transaction class for Ethernet frames
//   - axi_stream_driver: Drives frames on TX interface
//   - axi_stream_monitor: Monitors TX and RX interfaces
//   - axi_stream_sequencer: Routes transactions to driver
//   - axi_stream_agent: Container agent
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package axi_stream_agent_pkg;

    //==========================================================================
    // Imports
    //==========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //==========================================================================
    // Include Files (in dependency order)
    //==========================================================================
    
    // Transaction class (no dependencies)
    `include "axi_stream_txn.sv"
    
    // Sequencer (depends on txn)
    `include "axi_stream_sequencer.sv"
    
    // Driver (depends on txn)
    `include "axi_stream_driver.sv"
    
    // Monitor (depends on txn)
    `include "axi_stream_monitor.sv"
    
    // Agent (depends on all above)
    `include "axi_stream_agent.sv"

endpackage : axi_stream_agent_pkg
