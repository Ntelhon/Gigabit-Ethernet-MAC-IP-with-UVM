//==============================================================================
// Package: eth_env_pkg
// Description: Top-level Ethernet Controller environment package
//
// Contents:
//   - eth_virtual_sequencer: Top-level virtual sequencer
//   - eth_env: Top-level environment (contains MAC and DMA sub-environments)
//
// Dependencies:
//   - uvm_pkg
//   - mac_sub_env_pkg
//   - dma_sub_env_pkg
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package eth_env_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import axi_lite_agent_pkg::*;   // Shared AXI-Lite agent
    import mac_sub_env_pkg::*;
    import dma_sub_env_pkg::*;
    
    // Top-level virtual sequencer
    `include "eth_virtual_sequencer.sv"
    
    // Top-level environment
    `include "eth_env.sv"

endpackage : eth_env_pkg
