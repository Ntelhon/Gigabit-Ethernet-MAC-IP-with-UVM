//==============================================================================
// File: dma_pkg.v
// Description: DMA Subsystem Parameters and Definitions
//
// Purpose:
//   Centralized parameters for the DMA subsystem. All DMA modules should
//   include this file for consistent configuration.
//
// Descriptor Format (Configurable):
//   RX Descriptor (16 bytes):
//     [31:0]  - Buffer address low
//     [63:32] - Buffer address high (if ADDR_WIDTH > 32)
//     [79:64] - Buffer length (max bytes to receive)
//     [95:80] - Actual length (written by DMA)
//     [127:96]- Status/Control bits
//
//   TX Descriptor (16 bytes):
//     [31:0]  - Buffer address low
//     [63:32] - Buffer address high (if ADDR_WIDTH > 32)
//     [79:64] - Packet length
//     [95:80] - Reserved
//     [127:96]- Status/Control bits
//
// Status/Control Bits:
//     [0]   - OWN (0=CPU owns, 1=DMA owns)
//     [1]   - DONE (set by DMA when complete)
//     [2]   - ERR (error occurred)
//     [3]   - LAST (last descriptor of packet)
//     [4]   - FIRST (first descriptor of packet)
//     [5]   - CRC_EN (TX only: append CRC)
//     [31:6]- Reserved
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

// Guard to prevent multiple inclusion in simulation
`ifndef DMA_PKG_V
`define DMA_PKG_V

//==============================================================================
// DMA Configuration Parameters (Override via module parameters)
//==============================================================================

// Address widths
`define DMA_ADDR_WIDTH          64      // AXI address width (32 or 64)
`define DMA_DATA_WIDTH          64      // AXI data width (32, 64, 128)
`define DMA_LEN_WIDTH           16      // Buffer length width

// Descriptor configuration
`define DMA_DESC_SIZE           16      // Descriptor size in bytes
`define DMA_DESC_RING_DEPTH     256     // Max descriptors per ring

// AXI burst parameters
`define DMA_MAX_BURST_LEN       16      // Max AXI burst length (1-256)
`define DMA_BURST_SIZE          3'b011  // 8 bytes (64-bit)

// FIFO depths
`define DMA_TX_FIFO_DEPTH       1024    // TX FIFO depth (bytes)
`define DMA_RX_FIFO_DEPTH       2048    // RX FIFO depth (bytes)

//==============================================================================
// Descriptor Status Bit Positions
//==============================================================================

`define DMA_DESC_OWN            0       // Ownership bit
`define DMA_DESC_DONE           1       // Transfer complete
`define DMA_DESC_ERR            2       // Error flag
`define DMA_DESC_LAST           3       // Last descriptor of packet
`define DMA_DESC_FIRST          4       // First descriptor of packet
`define DMA_DESC_CRC_EN         5       // TX: Append CRC

//==============================================================================
// DMA Register Offsets (from DMA base at 0x200)
//==============================================================================

// TX DMA Registers (0x200 - 0x23F)
`define DMA_TX_CTRL             8'h00   // TX DMA Control
`define DMA_TX_STATUS           8'h04   // TX DMA Status
`define DMA_TX_DESC_ADDR_LO     8'h08   // TX Descriptor Ring Base Low
`define DMA_TX_DESC_ADDR_HI     8'h0C   // TX Descriptor Ring Base High
`define DMA_TX_DESC_SIZE        8'h10   // TX Descriptor Ring Size
`define DMA_TX_HEAD_PTR         8'h14   // TX Head Pointer (SW writes)
`define DMA_TX_TAIL_PTR         8'h18   // TX Tail Pointer (HW writes)
`define DMA_TX_PKT_CNT          8'h1C   // TX Packet Counter

// RX DMA Registers (0x240 - 0x27F)
`define DMA_RX_CTRL             8'h40   // RX DMA Control
`define DMA_RX_STATUS           8'h44   // RX DMA Status
`define DMA_RX_DESC_ADDR_LO     8'h48   // RX Descriptor Ring Base Low
`define DMA_RX_DESC_ADDR_HI     8'h4C   // RX Descriptor Ring Base High
`define DMA_RX_DESC_SIZE        8'h50   // RX Descriptor Ring Size
`define DMA_RX_HEAD_PTR         8'h54   // RX Head Pointer (HW writes)
`define DMA_RX_TAIL_PTR         8'h58   // RX Tail Pointer (SW writes)
`define DMA_RX_PKT_CNT          8'h5C   // RX Packet Counter

// DMA Interrupt Registers (0x280 - 0x29F)
`define DMA_INT_STATUS          8'h80   // DMA Interrupt Status (RW1C)
`define DMA_INT_MASK            8'h84   // DMA Interrupt Mask
`define DMA_INT_COALESCE        8'h88   // Interrupt Coalescing Config

//==============================================================================
// DMA Control Register Bits
//==============================================================================

`define DMA_CTRL_ENABLE         0       // DMA channel enable
`define DMA_CTRL_RESET          1       // Soft reset channel
`define DMA_CTRL_IRQ_EN         2       // Interrupt enable

//==============================================================================
// DMA Status Register Bits
//==============================================================================

`define DMA_STAT_BUSY           0       // DMA channel busy
`define DMA_STAT_HALTED         1       // Channel halted
`define DMA_STAT_ERROR          2       // Error condition

//==============================================================================
// DMA Interrupt Bits
//==============================================================================

`define DMA_INT_TX_DONE         0       // TX packet complete
`define DMA_INT_TX_ERR          1       // TX error
`define DMA_INT_RX_DONE         2       // RX packet complete
`define DMA_INT_RX_ERR          3       // RX error
`define DMA_INT_DESC_ERR        4       // Descriptor error

`endif // DMA_PKG_V
