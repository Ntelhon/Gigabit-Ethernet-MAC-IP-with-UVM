//==============================================================================
// Package: axi_lite_agent_pkg
// Description: UVM package for AXI4-Lite agent components
//
// Purpose:
//   Consolidates all AXI-Lite agent classes into a single package for easy
//   import into testbench environments.
//
// Contents:
//   - axi_lite_txn:       Transaction class for register access
//   - axi_lite_driver:    Master driver for read/write
//   - axi_lite_monitor:   Transaction monitor
//   - axi_lite_sequencer: Transaction sequencer
//   - axi_lite_agent:     Agent container
//   - axi_lite_agent_config: Configuration object
//
// Usage:
//   import axi_lite_agent_pkg::*;
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package axi_lite_agent_pkg;

    //==========================================================================
    // Import UVM package
    //==========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //==========================================================================
    // Include agent files in dependency order
    //==========================================================================
    `include "mac_reg_defines.svh"  // AXI-Lite register definitions
    `include "dma_reg_defines.svh"  // AXI-Lite register definitions

    // Transaction class (no dependencies)
    `include "axi_lite_txn.sv"
    
    // Sequencer (depends on axi_lite_txn)
    `include "axi_lite_sequencer.sv"
    
    // Driver (depends on axi_lite_txn)
    `include "axi_lite_driver.sv"
    
    // Monitor (depends on axi_lite_txn)
    `include "axi_lite_monitor.sv"
    
    // Agent (depends on all above)
    `include "axi_lite_agent.sv"

endpackage : axi_lite_agent_pkg
