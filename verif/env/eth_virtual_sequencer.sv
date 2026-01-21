//==============================================================================
// Class: eth_virtual_sequencer
// Description: Top-level virtual sequencer for Ethernet Controller
//
// Purpose:
//   Coordinates sequences across MAC and DMA sub-environments, providing
//   a unified control point for complex test scenarios.
//
// Hierarchy:
//   eth_virtual_sequencer (Top)
//     ├── mac_sqr  → MAC sub-environment virtual sequencer
//     └── dma_sqr  → DMA sub-environment virtual sequencer
//
// Usage:
//   Sequences running on this sequencer can access:
//   - p_sequencer.mac_sqr.gmii_sqr
//   - p_sequencer.mac_sqr.axi_lite_sqr
//   - p_sequencer.dma_sqr.axi_mm_sqr
//   - etc.
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim, Xcelium
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class eth_virtual_sequencer extends uvm_sequencer;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(eth_virtual_sequencer)

    //==========================================================================
    // Sub-Environment Sequencer Handles
    //==========================================================================
    
    // MAC sub-environment virtual sequencer
    mac_virtual_sequencer mac_sqr;
    
    // DMA sub-environment virtual sequencer
    dma_virtual_sequencer dma_sqr;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "eth_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : eth_virtual_sequencer
