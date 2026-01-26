//==============================================================================
// File: axi_stream_pkg.sv
// Description: AXI-Stream Agent Package
//
// This package contains all components for the AXI-Stream VIP:
// - Transaction item (axi_stream_item)
// - Configuration object (axi_stream_config)
// - Driver (axi_stream_driver)
// - Monitor (axi_stream_monitor)
// - Sequencer (axi_stream_sequencer)
// - Agent (axi_stream_agent)
//
// Usage:
//   import uvm_pkg::*;
//   import axi_stream_pkg::*;
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package axi_stream_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // AXI-Stream Agent Includes
 `include "include/axi_stream_agent_includes.svh"
  
  // AXI-Stream Agent Components
  `include "src/axi_stream_item.sv"
  `include "src/axi_stream_config.sv"
  `include "src/axi_stream_driver.sv"
  `include "src/axi_stream_monitor.sv"
  `include "src/axi_stream_sequencer.sv"
  `include "src/axi_stream_agent.sv"

endpackage : axi_stream_pkg
