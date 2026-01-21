//==============================================================================
// Package: dma_seq_lib_pkg
// Description: DMA sequence library package
//
// Contents:
//   - DMA base sequence
//   - DMA configuration sequences
//   - DMA TX/RX sequences
//   - DMA loopback sequences
//
// Dependencies:
//   - uvm_pkg
//   - axi_lite_agent_pkg
//   - axi_mm_agent_pkg
//   - axi_stream_agent_pkg
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package dma_seq_lib_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import axi_lite_agent_pkg::*;
    import axi_mm_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    
    // DMA register and descriptor definitions
    `include "dma_reg_defines.svh"
    
    // DMA sequences (base sequence must be included first)
    `include "dma_base_seq.sv"
    `include "dma_config_seq.sv"
    `include "dma_tx_seq.sv"
    `include "dma_rx_seq.sv"
    `include "dma_loopback_seq.sv"

endpackage : dma_seq_lib_pkg
