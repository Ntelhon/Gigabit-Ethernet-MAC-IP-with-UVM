//==============================================================================
// Package: axi4_mem_agent_pkg
// Description: UVM agent package for AXI4 full memory interface
//
// This agent models an AXI4 full (memory-mapped) interface for DMA operations
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package axi4_mem_agent_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Transaction class
    `include "axi4_mem_txn.sv"
    
    // Agent components
    `include "axi4_mem_sequencer.sv"
    `include "axi4_mem_driver.sv"
    `include "axi4_mem_monitor.sv"
    `include "axi4_mem_agent.sv"

endpackage : axi4_mem_agent_pkg
