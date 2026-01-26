//==============================================================================
// File: gmii_pkg.sv
// Description: GMII Agent Package
//
// This package contains all components for the GMII VIP:
// - Transaction item (gmii_item)
// - Configuration object (gmii_config)
// - Driver (gmii_driver)
// - Monitor (gmii_monitor)
// - Sequencer (gmii_sequencer)
// - Agent (gmii_agent)
//
// Usage:
//   import uvm_pkg::*;
//   import gmii_pkg::*;
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package gmii_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // GMII Agent Includes
  `include "include/gmii_agent_includes.svh"

  // GMII Agent Components
  `include "src/gmii_item.sv"
  `include "src/gmii_config.sv"
  `include "src/gmii_driver.sv"
  `include "src/gmii_monitor.sv"
  `include "src/gmii_sequencer.sv"
  `include "src/gmii_agent.sv"

endpackage : gmii_pkg
