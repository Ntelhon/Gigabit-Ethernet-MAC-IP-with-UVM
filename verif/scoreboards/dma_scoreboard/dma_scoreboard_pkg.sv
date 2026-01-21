//==============================================================================
// Package: dma_scoreboard_pkg
// Description: DMA scoreboard package
//
// Contents:
//   - dma_scoreboard: DMA transaction scoreboard
//
// Dependencies:
//   - uvm_pkg
//   - axi_mm_agent_pkg
//   - axi_stream_agent_pkg
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package dma_scoreboard_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import axi_mm_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    
    // DMA scoreboard
    `include "dma_scoreboard.sv"

endpackage : dma_scoreboard_pkg
