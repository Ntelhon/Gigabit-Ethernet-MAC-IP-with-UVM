//==============================================================================
// File: mac_reg_defines.svh
// Description: MAC Register Address and Bit Field Definitions
//
// Purpose:
//   Defines register addresses and bit field constants for MAC configuration
//   and status registers. These match the RTL register map in mac_regs.v
//
// Usage:
//   `include "mac_reg_defines.svh"
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`ifndef MAC_REG_DEFINES_SVH
`define MAC_REG_DEFINES_SVH

//==============================================================================
// Register Addresses (match Accessible_Registers.md v2.0)
//==============================================================================

// MAC Configuration Registers
parameter bit [31:0] MAC_ADDR_LO     = 32'h0000_0000;  // MAC address [31:0]
parameter bit [31:0] MAC_ADDR_HI     = 32'h0000_0004;  // MAC address [47:32]
parameter bit [31:0] CONTROL         = 32'h0000_0008;  // TX/RX Enable Control
parameter bit [31:0] STATUS          = 32'h0000_000C;  // TX/RX Active Status
parameter bit [31:0] INT_STATUS      = 32'h0000_0010;  // Interrupt Status (RW1C)
parameter bit [31:0] INT_MASK        = 32'h0000_0014;  // Interrupt Mask

// MAC Statistics Registers
parameter bit [31:0] TX_FRAME_CNT    = 32'h0000_0018;  // TX frame counter
parameter bit [31:0] RX_FRAME_CNT    = 32'h0000_001C;  // RX frame counter
parameter bit [31:0] RX_ERR_CNT      = 32'h0000_0020;  // RX error counter
parameter bit [31:0] VERSION         = 32'h0000_0024;  // IP Version

// Legacy aliases for backward compatibility
parameter bit [31:0] MAC_LO_REG         = MAC_ADDR_LO;
parameter bit [31:0] MAC_HI_REG         = MAC_ADDR_HI;
parameter bit [31:0] MAC_CONTROL_REG    = CONTROL;
parameter bit [31:0] MAC_STATUS_REG     = STATUS;
parameter bit [31:0] MAC_INT_STATUS_REG = INT_STATUS;
parameter bit [31:0] MAC_INT_MASK_REG   = INT_MASK;
parameter bit [31:0] MAC_TX_CNT_REG     = TX_FRAME_CNT;
parameter bit [31:0] MAC_RX_CNT_REG     = RX_FRAME_CNT;
parameter bit [31:0] MAC_RX_ERR_REG     = RX_ERR_CNT;
parameter bit [31:0] MAC_VERSION_REG    = VERSION;

//==============================================================================
// CONTROL Register Bit Fields (Offset 0x008)
//==============================================================================
parameter int CTRL_TX_ENABLE_BIT   = 0;   // TX path enable (1=enabled, 0=disabled)
parameter int CTRL_RX_ENABLE_BIT   = 1;   // RX path enable (1=enabled, 0=disabled)

// Legacy aliases for backward compatibility
parameter int MAC_CTRL_TX_EN_BIT   = CTRL_TX_ENABLE_BIT;
parameter int MAC_CTRL_RX_EN_BIT   = CTRL_RX_ENABLE_BIT;

//==============================================================================
// STATUS Register Bit Fields (Offset 0x00C)
//==============================================================================
parameter int STATUS_TX_ACTIVE_BIT = 0;   // TX path is actively transmitting
parameter int STATUS_RX_ACTIVE_BIT = 1;   // RX path is actively receiving

// Legacy aliases for backward compatibility
parameter int MAC_STATUS_TX_BUSY_BIT = STATUS_TX_ACTIVE_BIT;
parameter int MAC_STATUS_RX_BUSY_BIT = STATUS_RX_ACTIVE_BIT;

//==============================================================================
// INT_STATUS Register Bit Fields (Offset 0x010) - RW1C
//==============================================================================
parameter int INT_TX_COMPLETE_BIT  = 0;   // TX frame transmission complete
parameter int INT_RX_RECEIVED_BIT  = 1;   // RX frame received successfully
parameter int INT_RX_CRC_ERR_BIT   = 2;   // RX CRC error detected
parameter int INT_RX_RUNT_BIT      = 3;   // RX runt frame (< 64 bytes)

// Legacy aliases for backward compatibility  
parameter int MAC_INT_TX_COMPLETE_BIT = INT_TX_COMPLETE_BIT;
parameter int MAC_INT_RX_RECEIVED_BIT = INT_RX_RECEIVED_BIT;
parameter int MAC_INT_RX_CRC_ERR_BIT  = INT_RX_CRC_ERR_BIT;
parameter int MAC_INT_RX_RUNT_BIT     = INT_RX_RUNT_BIT;

//==============================================================================
// INT_MASK Register Bit Fields (Offset 0x014)
//==============================================================================
parameter int INT_TX_COMPLETE_MASK_BIT = 0;   // TX complete interrupt mask
parameter int INT_RX_RECEIVED_MASK_BIT = 1;   // RX received interrupt mask
parameter int INT_RX_CRC_ERR_MASK_BIT  = 2;   // RX CRC error interrupt mask
parameter int INT_RX_RUNT_MASK_BIT     = 3;   // RX runt frame interrupt mask

`endif // MAC_REG_DEFINES_SVH
