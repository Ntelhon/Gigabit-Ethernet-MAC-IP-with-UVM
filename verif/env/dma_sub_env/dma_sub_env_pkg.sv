//==============================================================================
// Package: dma_sub_env_pkg
// Description: DMA sub-environment package
//
// Contents:
//   - dma_virtual_sequencer: DMA virtual sequencer
//   - dma_sub_env: DMA sub-environment
//
// Dependencies:
//   - uvm_pkg
//   - axi_mm_agent_pkg
//   - axi_stream_agent_pkg
//   - dma_scoreboard_pkg
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package dma_sub_env_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import axi_lite_agent_pkg::*;   // Shared AXI-Lite agent
    import axi_mm_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import dma_scoreboard_pkg::*;
    
    // DMA virtual sequencer
    `include "dma_virtual_sequencer.sv"
    
    // DMA sub-environment
    `include "dma_sub_env.sv"

endpackage : dma_sub_env_pkg
