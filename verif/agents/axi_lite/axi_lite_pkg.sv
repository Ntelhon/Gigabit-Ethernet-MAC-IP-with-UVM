//==============================================================================
// File: axi_lite_pkg.sv
// Description: AXI-Lite Agent Package
//
// This package contains all components for the AXI-Lite VIP:
// - Transaction item (axi_lite_item)
// - Configuration object (axi_lite_config)
// - Driver (axi_lite_driver)
// - Monitor (axi_lite_monitor)
// - Sequencer (axi_lite_sequencer)
// - Agent (axi_lite_agent)
//
// Usage:
//   import uvm_pkg::*;
//   import axi_lite_pkg::*;
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package axi_lite_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // AXI-Lite Register Definitions
  `include "include/mac_reg_defines.svh"
  `include "include/dma_reg_defines.svh"
  `include "include/axi_lite_agent_includes.svh"
  
  // AXI-Lite Agent Components
  `include "src/axi_lite_item.sv"
  `include "src/axi_lite_config.sv"
  `include "src/axi_lite_driver.sv"
  `include "src/axi_lite_monitor.sv"
  `include "src/axi_lite_sequencer.sv"
  `include "src/axi_lite_agent.sv"

endpackage : axi_lite_pkg
