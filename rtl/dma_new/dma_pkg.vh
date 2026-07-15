//==============================================================================
// File: dma_pkg.vh
// Description: DMA Subsystem Shared Definitions (include file, NOT a module)
//
// Purpose:
//   Central location for register offsets, control/status/interrupt bit
//   positions and descriptor field bit positions. No logic, no modules.
//   Included by every DMA RTL file that references these constants.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`ifndef DMA_PKG_VH
`define DMA_PKG_VH

//==============================================================================
// DMA Register Offsets (byte offsets within the DMA CSR space)
//==============================================================================

// TX DMA registers (0x00 - 0x3F)
`define DMA_TX_CTRL             8'h00   // TX DMA Control
`define DMA_TX_STATUS           8'h04   // TX DMA Status (RO)
`define DMA_TX_DESC_LO          8'h08   // TX Descriptor Ring Base Low
`define DMA_TX_DESC_HI          8'h0C   // TX Descriptor Ring Base High
`define DMA_TX_RING_SIZE        8'h10   // TX Ring Size (descriptors)
`define DMA_TX_HEAD_PTR         8'h14   // TX Head Pointer (SW writes)
`define DMA_TX_TAIL_PTR         8'h18   // TX Tail Pointer (HW updates, RO)
`define DMA_TX_PKT_CNT          8'h1C   // TX Packet Counter (RO)

// RX DMA registers (0x40 - 0x7F)
`define DMA_RX_CTRL             8'h40   // RX DMA Control
`define DMA_RX_STATUS           8'h44   // RX DMA Status (RO)
`define DMA_RX_DESC_LO          8'h48   // RX Descriptor Ring Base Low
`define DMA_RX_DESC_HI          8'h4C   // RX Descriptor Ring Base High
`define DMA_RX_RING_SIZE        8'h50   // RX Ring Size (descriptors)
`define DMA_RX_HEAD_PTR         8'h54   // RX Head Pointer (HW updates, RO)
`define DMA_RX_TAIL_PTR         8'h58   // RX Tail Pointer (SW writes)
`define DMA_RX_PKT_CNT          8'h5C   // RX Packet Counter (RO)

// Interrupt / misc registers (0x80 - 0xFF)
`define DMA_INT_STATUS          8'h80   // Interrupt Status (RW1C)
`define DMA_INT_MASK            8'h84   // Interrupt Mask
`define DMA_INT_COALESCE        8'h88   // Interrupt Coalescing Config
`define DMA_VERSION             8'h8C   // DMA IP Version (RO)
`define DMA_RX_DROP_CNT         8'h90   // RX Dropped Packet Counter (RO)
`define DMA_TX_BYTE_CNT         8'h94   // TX Byte Counter (RO)
`define DMA_RX_BYTE_CNT         8'h98   // RX Byte Counter (RO)

//==============================================================================
// Control Register Bits (TX_CTRL / RX_CTRL)
//==============================================================================

`define DMA_CTRL_ENABLE         0       // Channel enable
`define DMA_CTRL_RESET          1       // Channel soft reset (self-clearing)
`define DMA_CTRL_IRQ_EN         2       // Channel interrupt enable

//==============================================================================
// Status Register Bits (TX_STATUS / RX_STATUS)
//==============================================================================

`define DMA_STAT_BUSY           0       // Channel busy
`define DMA_STAT_HALTED         1       // Channel halted (fatal error)
`define DMA_STAT_ERROR          2       // Error occurred (sticky)

//==============================================================================
// Interrupt Bits (INT_STATUS / INT_MASK)
//==============================================================================

`define DMA_INT_TX_DONE         0       // TX descriptor completed (IRQ_EN set)
`define DMA_INT_TX_ERR          1       // TX error
`define DMA_INT_RX_DONE         2       // RX packet stored (IRQ_EN set)
`define DMA_INT_RX_ERR          3       // RX error
`define DMA_INT_DESC_ERR        4       // Descriptor engine error

//==============================================================================
// Descriptor CTRL/STS Word Bit Positions (word at descriptor bytes 12-15)
//==============================================================================

// Software -> hardware control bits
`define DESC_OWN                31      // 1 = descriptor owned by hardware
`define DESC_SOP                30      // First buffer of packet (TX only)
`define DESC_EOP                29      // Last buffer of packet (TX only)
`define DESC_IRQ_EN             28      // Interrupt on completion

// Hardware -> software status bits (writeback)
`define DESC_DONE               15      // Descriptor processed
`define DESC_ERR                14      // TX: any error / RX: CRC error (tuser)
`define DESC_ERR_CRC            14      // RX: MAC flagged error at tlast
`define DESC_ERR_TRUNC          13      // RX: packet truncated to buffer size
`define DESC_ERR_AXI            12      // AXI response error during data move

//==============================================================================
// Version
//==============================================================================

`define DMA_VERSION_VALUE       32'h0002_0000

`endif // DMA_PKG_VH
