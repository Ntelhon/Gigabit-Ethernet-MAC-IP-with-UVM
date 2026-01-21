//==============================================================================
// File: dma_reg_defines.svh
// Description: DMA Register and Descriptor Definitions
//
// Purpose:
//   Defines register addresses, descriptor bit fields, and constants for
//   DMA configuration and descriptor ring management
//
// Usage:
//   `include "dma_reg_defines.svh"
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`ifndef DMA_REG_DEFINES_SVH
`define DMA_REG_DEFINES_SVH

//==============================================================================
// DMA Register Addresses (match Accessible_Registers.md v2.0)
// DMA Region: 0x200 - 0x3FF (when DMA_ENABLE=1)
//==============================================================================

//------------------------------------------------------------------------------
// TX DMA Registers (0x200 - 0x23F)
//------------------------------------------------------------------------------
parameter bit [31:0] DMA_TX_CTRL       = 32'h0000_0200;  // TX DMA Control
parameter bit [31:0] DMA_TX_STATUS     = 32'h0000_0204;  // TX DMA Status
parameter bit [31:0] DMA_TX_DESC_LO    = 32'h0000_0208;  // TX Descriptor Ring Base Low
parameter bit [31:0] DMA_TX_DESC_HI    = 32'h0000_020C;  // TX Descriptor Ring Base High
parameter bit [31:0] DMA_TX_RING_SIZE  = 32'h0000_0210;  // TX Ring Size (descriptors)
parameter bit [31:0] DMA_TX_HEAD_PTR   = 32'h0000_0214;  // TX Head Pointer (SW writes)
parameter bit [31:0] DMA_TX_TAIL_PTR   = 32'h0000_0218;  // TX Tail Pointer (HW updates)
parameter bit [31:0] DMA_TX_PKT_CNT    = 32'h0000_021C;  // TX DMA Packet Counter

//------------------------------------------------------------------------------
// RX DMA Registers (0x240 - 0x27F)
//------------------------------------------------------------------------------
parameter bit [31:0] DMA_RX_CTRL       = 32'h0000_0240;  // RX DMA Control
parameter bit [31:0] DMA_RX_STATUS     = 32'h0000_0244;  // RX DMA Status
parameter bit [31:0] DMA_RX_DESC_LO    = 32'h0000_0248;  // RX Descriptor Ring Base Low
parameter bit [31:0] DMA_RX_DESC_HI    = 32'h0000_024C;  // RX Descriptor Ring Base High
parameter bit [31:0] DMA_RX_RING_SIZE  = 32'h0000_0250;  // RX Ring Size (descriptors)
parameter bit [31:0] DMA_RX_HEAD_PTR   = 32'h0000_0254;  // RX Head Pointer (HW updates)
parameter bit [31:0] DMA_RX_TAIL_PTR   = 32'h0000_0258;  // RX Tail Pointer (SW writes)
parameter bit [31:0] DMA_RX_PKT_CNT    = 32'h0000_025C;  // RX DMA Packet Counter

//------------------------------------------------------------------------------
// DMA Interrupt Registers (0x280 - 0x29F)
//------------------------------------------------------------------------------
parameter bit [31:0] DMA_INT_STATUS    = 32'h0000_0280;  // DMA Interrupt Status (RW1C)
parameter bit [31:0] DMA_INT_MASK      = 32'h0000_0284;  // DMA Interrupt Mask
parameter bit [31:0] DMA_INT_COALESCE  = 32'h0000_0288;  // Interrupt Coalescing Config

// Legacy aliases for backward compatibility
parameter bit [31:0] DMA_CTRL           = DMA_TX_CTRL;      // Legacy - maps to TX CTRL
parameter bit [31:0] DMA_STATUS         = DMA_TX_STATUS;    // Legacy - maps to TX STATUS
parameter bit [31:0] DMA_TX_DESC_BASE_L = DMA_TX_DESC_LO;
parameter bit [31:0] DMA_TX_DESC_BASE_H = DMA_TX_DESC_HI;
parameter bit [31:0] DMA_TX_DESC_COUNT  = DMA_TX_RING_SIZE;
parameter bit [31:0] DMA_TX_DESC_HEAD   = DMA_TX_HEAD_PTR;
parameter bit [31:0] DMA_TX_DESC_TAIL   = DMA_TX_TAIL_PTR;
parameter bit [31:0] DMA_TX_DESC_SIZE   = DMA_TX_RING_SIZE;
parameter bit [31:0] DMA_TX_HEAD        = DMA_TX_HEAD_PTR;
parameter bit [31:0] DMA_TX_TAIL        = DMA_TX_TAIL_PTR;
parameter bit [31:0] DMA_RX_DESC_BASE_L = DMA_RX_DESC_LO;
parameter bit [31:0] DMA_RX_DESC_BASE_H = DMA_RX_DESC_HI;
parameter bit [31:0] DMA_RX_DESC_COUNT  = DMA_RX_RING_SIZE;
parameter bit [31:0] DMA_RX_DESC_HEAD   = DMA_RX_HEAD_PTR;
parameter bit [31:0] DMA_RX_DESC_TAIL   = DMA_RX_TAIL_PTR;
parameter bit [31:0] DMA_RX_DESC_SIZE   = DMA_RX_RING_SIZE;
parameter bit [31:0] DMA_RX_HEAD        = DMA_RX_HEAD_PTR;
parameter bit [31:0] DMA_RX_TAIL        = DMA_RX_TAIL_PTR;
parameter bit [31:0] DMA_INT_COAL_TX    = DMA_INT_COALESCE;  // Legacy
parameter bit [31:0] DMA_INT_COAL_RX    = DMA_INT_COALESCE;  // Legacy
parameter bit [31:0] DMA_IRQ_EN         = DMA_INT_MASK;      // Legacy
parameter bit [31:0] DMA_IRQ_STATUS     = DMA_INT_STATUS;    // Legacy

//==============================================================================
// Descriptor Bit Fields (Status/Control Word)
//==============================================================================

// Status/Control bits in descriptor
parameter int DESC_OWN_BIT    = 31;  // Ownership bit (1=HW owns, 0=SW owns)
parameter int DESC_FIRST_BIT  = 30;  // First descriptor in frame
parameter int DESC_LAST_BIT   = 29;  // Last descriptor in frame
parameter int DESC_IRQ_BIT    = 28;  // Generate IRQ on completion
parameter int DESC_ERROR_BIT  = 27;  // Error flag
parameter int DESC_DONE_BIT   = 26;  // Descriptor processing done

// Descriptor length mask
parameter bit [31:0] DESC_LEN_MASK = 32'h0000_FFFF;  // Length in lower 16 bits

//==============================================================================
// DMA TX/RX Control Register Bit Fields (Offset 0x200/0x240)
//==============================================================================
parameter int DMA_CTRL_ENABLE_BIT   = 0;   // DMA channel enable (1=enabled, 0=disabled)
parameter int DMA_CTRL_RESET_BIT    = 1;   // DMA channel soft reset (self-clearing)
parameter int DMA_CTRL_IRQ_EN_BIT   = 2;   // DMA interrupt enable (1=enabled)

// Legacy aliases for backward compatibility
parameter int DMA_CTRL_TX_EN_BIT    = DMA_CTRL_ENABLE_BIT;
parameter int DMA_CTRL_RX_EN_BIT    = DMA_CTRL_ENABLE_BIT;

// Control register bit masks
parameter bit [31:0] DMA_CTRL_ENABLE = (1 << DMA_CTRL_ENABLE_BIT);
parameter bit [31:0] DMA_CTRL_RESET  = (1 << DMA_CTRL_RESET_BIT);
parameter bit [31:0] DMA_CTRL_IRQ_EN = (1 << DMA_CTRL_IRQ_EN_BIT);

// Legacy bit masks
parameter bit [31:0] DMA_CTRL_TX_EN  = DMA_CTRL_ENABLE;
parameter bit [31:0] DMA_CTRL_RX_EN  = DMA_CTRL_ENABLE;
parameter bit [31:0] DMA_CTRL_TX_RST = (1 << 16);  // Legacy TX reset bit
parameter bit [31:0] DMA_CTRL_RX_RST = (1 << 17);  // Legacy RX reset bit

//==============================================================================
// DMA TX/RX Status Register Bit Fields (Offset 0x204/0x244)
//==============================================================================
parameter int DMA_STATUS_BUSY_BIT   = 0;   // DMA is actively processing
parameter int DMA_STATUS_HALTED_BIT = 1;   // DMA is halted (disabled or error)
parameter int DMA_STATUS_ERROR_BIT  = 2;   // DMA encountered an error

// Legacy aliases for backward compatibility
parameter int DMA_STATUS_TX_BUSY_BIT = DMA_STATUS_BUSY_BIT;
parameter int DMA_STATUS_RX_BUSY_BIT = DMA_STATUS_BUSY_BIT;
parameter int DMA_STATUS_TX_IRQ_BIT  = 8;  // TX IRQ pending (legacy)
parameter int DMA_STATUS_RX_IRQ_BIT  = 9;  // RX IRQ pending (legacy)

//==============================================================================
// DMA Interrupt Status Register Bit Fields (Offset 0x280) - RW1C
//==============================================================================
parameter int DMA_INT_TX_DONE_BIT   = 0;   // TX packet complete
parameter int DMA_INT_TX_ERR_BIT    = 1;   // TX error occurred
parameter int DMA_INT_RX_DONE_BIT   = 2;   // RX packet complete
parameter int DMA_INT_RX_ERR_BIT    = 3;   // RX error occurred
parameter int DMA_INT_DESC_ERR_BIT  = 4;   // Descriptor fetch/write error

//==============================================================================
// DMA Interrupt Mask Register Bit Fields (Offset 0x284)
//==============================================================================
parameter int DMA_INT_TX_DONE_MASK_BIT  = 0;   // TX done interrupt mask
parameter int DMA_INT_TX_ERR_MASK_BIT   = 1;   // TX error interrupt mask
parameter int DMA_INT_RX_DONE_MASK_BIT  = 2;   // RX done interrupt mask
parameter int DMA_INT_RX_ERR_MASK_BIT   = 3;   // RX error interrupt mask
parameter int DMA_INT_DESC_ERR_MASK_BIT = 4;   // Descriptor error interrupt mask

//==============================================================================
// DMA Interrupt Coalescing Register Bit Fields (Offset 0x288)
//==============================================================================
// [15:0]  PKT_CNT  - Number of packets before generating interrupt
// [31:16] TIMEOUT  - Timeout in microseconds before generating interrupt
parameter bit [31:0] DMA_INT_COAL_PKT_CNT_MASK = 32'h0000_FFFF;
parameter bit [31:0] DMA_INT_COAL_TIMEOUT_MASK = 32'hFFFF_0000;

`endif // DMA_REG_DEFINES_SVH
