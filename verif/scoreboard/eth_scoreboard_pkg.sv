//==============================================================================
// Package: eth_scoreboard_pkg
// Description: UVM package for Ethernet scoreboard and CRC model
//
// Purpose:
//   Consolidates scoreboard and reference model classes for easy import.
//
// Contents:
//   - eth_crc_model:   CRC32 reference model
//   - eth_scoreboard:  Frame comparison scoreboard for MAC
//   - dma_scoreboard:  DMA transaction scoreboard
//
// Dependencies:
//   - gmii_agent_pkg (for gmii_frame)
//   - axi_stream_agent_pkg (for axi_stream_item)
//   - axi_mm_agent_pkg (for axi_mm_item)
//
// Usage:
//   import eth_scoreboard_pkg::*;
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package eth_scoreboard_pkg;

    //==========================================================================
    // Import UVM and dependent packages
    //==========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // Import GMII agent for gmii_frame class
    import gmii_agent_pkg::*;
    
    // Import AXI-Stream agent for packet items
    import axi_stream_agent_pkg::*;
    
    // Import AXI-MM agent for DMA memory transactions
    import axi_mm_agent_pkg::*;

    //==========================================================================
    // Include scoreboard files in dependency order
    //==========================================================================
    
    // CRC reference model (no dependencies)
    `include "eth_crc_model.sv"
    
    // Scoreboard (depends on eth_crc_model and gmii_frame)
    `include "eth_scoreboard.sv"
    
    // DMA scoreboard (depends on axi_mm_item and axi_stream_item)
    `include "dma_scoreboard.sv"

endpackage : eth_scoreboard_pkg
