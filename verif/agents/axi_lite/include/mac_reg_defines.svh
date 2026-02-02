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
parameter bit [31:0] MAC_ADDR_LO_REG     = 32'h0000_0000;  // MAC address [31:0]
parameter bit [31:0] MAC_ADDR_HI_REG     = 32'h0000_0004;  // MAC address [47:32]
parameter bit [31:0] MAC_CONTROL_REG     = 32'h0000_0008;  // TX/RX Enable Control
parameter bit [31:0] MAC_STATUS_REG      = 32'h0000_000C;  // TX/RX Active Status
parameter bit [31:0] MAC_INT_STATUS_REG  = 32'h0000_0010;  // Interrupt Status (RW1C)
parameter bit [31:0] MAC_INT_MASK_REG    = 32'h0000_0014;  // Interrupt Mask

// MAC Statistics Registers
parameter bit [31:0] MAC_TX_CNT_REG      = 32'h0000_0018;  // TX frame counter
parameter bit [31:0] MAC_RX_CNT_REG      = 32'h0000_001C;  // RX frame counter
parameter bit [31:0] MAC_RX_ERR_REG      = 32'h0000_0020;  // RX error counter
parameter bit [31:0] MAC_VERSION_REG     = 32'h0000_0024;  // IP Version

//==============================================================================
// CONTROL Register Bit Fields (Offset 0x008)
//==============================================================================
parameter int MAC_CTRL_TX_EN_BITMASK     = 32'h0000_0001;   // TX path enable (1=enabled, 0=disabled)
parameter int MAC_CTRL_RX_EN_BITMASK     = 32'h0000_0002;   // RX path enable (1=enabled, 0=disabled)

//==============================================================================
// STATUS Register Bit Fields (Offset 0x00C)
//==============================================================================
parameter int MAC_STATUS_TX_BUSY_BITMASK = 32'h0000_0001;   // TX path is actively transmitting
parameter int MAC_STATUS_RX_BUSY_BITMASK = 32'h0000_0002;   // RX path is actively receiving

//==============================================================================
// INT_STATUS Register Bit Fields (Offset 0x010) - RW1C
//==============================================================================
parameter int MAC_INT_TX_COMPLETE_BITMASK  = 32'h0000_0001;   // TX frame transmission complete
parameter int MAC_INT_RX_RECEIVED_BITMASK  = 32'h0000_0002;   // RX frame received successfully
parameter int MAC_INT_RX_CRC_ERR_BITMASK   = 32'h0000_0004;   // RX CRC error detected
parameter int MAC_INT_RX_RUNT_BITMASK      = 32'h0000_0008;   // RX runt frame (< 64 bytes)

`endif // MAC_REG_DEFINES_SVH
