//==============================================================================
// DMA Test Sequences Package
//==============================================================================

`ifndef DMA_SEQS_PKG_SV
`define DMA_SEQS_PKG_SV

package dma_seqs_pkg;
    
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import axi_lite_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import axi_mm_agent_pkg::*;
    
    //--------------------------------------------------------------------------
    // DMA Register Offsets (base address 0x200)
    //--------------------------------------------------------------------------
    parameter DMA_BASE          = 32'h0000_0200;
    
    // Control/Status
    parameter DMA_CTRL          = DMA_BASE + 32'h00;
    parameter DMA_STATUS        = DMA_BASE + 32'h04;
    parameter DMA_IRQ_EN        = DMA_BASE + 32'h08;
    parameter DMA_IRQ_STATUS    = DMA_BASE + 32'h0C;
    
    // TX Descriptor Ring
    parameter DMA_TX_DESC_LO    = DMA_BASE + 32'h10;
    parameter DMA_TX_DESC_HI    = DMA_BASE + 32'h14;
    parameter DMA_TX_DESC_SIZE  = DMA_BASE + 32'h18;
    parameter DMA_TX_HEAD       = DMA_BASE + 32'h1C;
    parameter DMA_TX_TAIL       = DMA_BASE + 32'h20;
    
    // RX Descriptor Ring
    parameter DMA_RX_DESC_LO    = DMA_BASE + 32'h40;
    parameter DMA_RX_DESC_HI    = DMA_BASE + 32'h44;
    parameter DMA_RX_DESC_SIZE  = DMA_BASE + 32'h48;
    parameter DMA_RX_HEAD       = DMA_BASE + 32'h4C;
    parameter DMA_RX_TAIL       = DMA_BASE + 32'h50;
    
    // Interrupt Coalescing
    parameter DMA_INT_COAL_TX   = DMA_BASE + 32'h80;
    parameter DMA_INT_COAL_RX   = DMA_BASE + 32'h84;
    
    // Statistics
    parameter DMA_TX_PKT_CNT    = DMA_BASE + 32'h60;
    parameter DMA_TX_BYTE_CNT   = DMA_BASE + 32'h64;
    parameter DMA_RX_PKT_CNT    = DMA_BASE + 32'h70;
    parameter DMA_RX_BYTE_CNT   = DMA_BASE + 32'h74;
    
    //--------------------------------------------------------------------------
    // DMA Control Bits
    //--------------------------------------------------------------------------
    parameter DMA_CTRL_TX_EN    = 32'h0000_0001;
    parameter DMA_CTRL_RX_EN    = 32'h0000_0002;
    parameter DMA_CTRL_TX_RST   = 32'h0000_0100;
    parameter DMA_CTRL_RX_RST   = 32'h0000_0200;
    
    //--------------------------------------------------------------------------
    // Descriptor Format (16 bytes)
    //--------------------------------------------------------------------------
    // Word 0: addr_lo[31:0]
    // Word 1: addr_hi[31:0]
    // Word 2: length[15:0], reserved[15:0]
    // Word 3: status[31:0] - OWN[31], DONE[30], ERR[29], LAST[28], FIRST[27]
    //--------------------------------------------------------------------------
    parameter DESC_OWN_BIT      = 31;
    parameter DESC_DONE_BIT     = 30;
    parameter DESC_ERR_BIT      = 29;
    parameter DESC_LAST_BIT     = 28;
    parameter DESC_FIRST_BIT    = 27;
    
    //--------------------------------------------------------------------------
    // Include sequence files
    //--------------------------------------------------------------------------
    `include "dma_base_seq.sv"
    `include "dma_config_seq.sv"
    `include "dma_tx_seq.sv"
    `include "dma_rx_seq.sv"
    `include "dma_loopback_seq.sv"
    
endpackage : dma_seqs_pkg

`endif // DMA_SEQS_PKG_SV
