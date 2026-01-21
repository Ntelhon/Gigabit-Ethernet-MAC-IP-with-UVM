//==============================================================================
// Class: dma_virtual_sequencer
// Description: DMA sub-environment virtual sequencer
//
// Purpose:
//   Coordinates DMA-related sequences across AXI-MM and optional AXI-Stream
//   interfaces.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class dma_virtual_sequencer extends uvm_sequencer;

    `uvm_component_utils(dma_virtual_sequencer)

    //==========================================================================
    // Sequencer Handles
    //==========================================================================
    
    // AXI-Lite sequencer (shared, set by parent eth_env)
    axi_lite_sequencer axi_lite_sqr;
    
    // AXI-Stream sequencer (optional)
    axi_stream_sequencer axis_sqr;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "dma_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : dma_virtual_sequencer
