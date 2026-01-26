//==============================================================================
// File: axi4_pkg.sv
// Description: AXI4 Agent Package
//
// This package contains all components for the AXI4 VIP:
// - Transaction item (axi4_item)
// - Configuration object (axi4_config)
// - Driver (axi4_driver)
// - Monitor (axi4_monitor)
// - Sequencer (axi4_sequencer)
// - Agent (axi4_agent)
//
// Usage:
//   import uvm_pkg::*;
//   import axi4_pkg::*;
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package axi4_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // AXI4 Agent Includes
  `include "include/axi4_agent_includes.svh"

  // AXI4 Agent Components
  `include "src/axi4_item.sv"
  `include "src/axi4_config.sv"
  `include "src/axi4_driver.sv"
  `include "src/axi4_monitor.sv"
  `include "src/axi4_sequencer.sv"
  `include "src/axi4_agent.sv"

endpackage : axi4_pkg
