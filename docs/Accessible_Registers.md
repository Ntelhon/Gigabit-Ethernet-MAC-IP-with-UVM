# Gigabit Ethernet MAC IP - Accessible Registers

**Document Version:** 1.0  
**IP Version:** 1.0.0  
**Date:** January 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Register Map Summary](#2-register-map-summary)
3. [Register Descriptions](#3-register-descriptions)
   - [MAC_ADDR_LO](#31-mac_addr_lo---mac-address-low)
   - [MAC_ADDR_HI](#32-mac_addr_hi---mac-address-high)
   - [CONTROL](#33-control---control-register)
   - [STATUS](#34-status---status-register)
   - [INT_STATUS](#35-int_status---interrupt-status-register)
   - [INT_MASK](#36-int_mask---interrupt-mask-register)
   - [TX_FRAME_CNT](#37-tx_frame_cnt---tx-frame-counter)
   - [RX_FRAME_CNT](#38-rx_frame_cnt---rx-frame-counter)
   - [RX_ERR_CNT](#39-rx_err_cnt---rx-error-counter)
   - [VERSION](#310-version---version-register)
4. [Access Types](#4-access-types)
5. [Reset Behavior](#5-reset-behavior)
6. [Programming Guidelines](#6-programming-guidelines)

---

## 1. Overview

This document describes the accessible registers of the Gigabit Ethernet MAC IP. All registers are accessible via the AXI4-Lite slave interface. The register interface operates in the system clock domain (`sys_clk`).

### Interface Specifications

| Parameter | Value |
|-----------|-------|
| Interface Protocol | AXI4-Lite |
| Data Width | 32 bits |
| Address Width | 8 bits (configurable) |
| Byte Addressing | Yes (word-aligned) |
| Endianness | Little-endian |
| Clock Domain | sys_clk |

### Register Space

| Parameter | Value |
|-----------|-------|
| Base Address | Configurable by SoC |
| Address Range | 0x00 - 0x24 |
| Total Registers | 10 |
| Reserved Space | 0x28 - 0xFF |

---

## 2. Register Map Summary

| Offset | Name | Width | Access | Reset Value | Description |
|--------|------|-------|--------|-------------|-------------|
| 0x00 | MAC_ADDR_LO | 32 | RW | 0x00000000 | MAC Address [31:0] |
| 0x04 | MAC_ADDR_HI | 16 | RW | 0x0000 | MAC Address [47:32] |
| 0x08 | CONTROL | 2 | RW | 0x00 | TX/RX Enable Control |
| 0x0C | STATUS | 2 | RO | 0x00 | TX/RX Active Status |
| 0x10 | INT_STATUS | 4 | RW1C | 0x0 | Interrupt Status |
| 0x14 | INT_MASK | 4 | RW | 0x0 | Interrupt Mask |
| 0x18 | TX_FRAME_CNT | 32 | RO | 0x00000000 | TX Frame Counter |
| 0x1C | RX_FRAME_CNT | 32 | RO | 0x00000000 | RX Frame Counter |
| 0x20 | RX_ERR_CNT | 32 | RO | 0x00000000 | RX Error Counter |
| 0x24 | VERSION | 32 | RO | 0x00010000 | IP Version |

---

## 3. Register Descriptions

### 3.1 MAC_ADDR_LO - MAC Address Low

**Address:** 0x00  
**Reset Value:** 0x00000000  
**Access:** Read/Write

This register holds the lower 32 bits of the 48-bit MAC address. The MAC address is used for source address insertion in transmitted frames.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | MAC_ADDR[31:0] | RW | 0x00000000 | Lower 32 bits of MAC address. Byte order: [7:0]=Byte 0, [15:8]=Byte 1, [23:16]=Byte 2, [31:24]=Byte 3. |

**Programming Notes:**
- Program this register before enabling the TX path.
- Changes take effect on the next transmitted frame.
- No side effects on read operations.

---

### 3.2 MAC_ADDR_HI - MAC Address High

**Address:** 0x04  
**Reset Value:** 0x00000000  
**Access:** Read/Write

This register holds the upper 16 bits of the 48-bit MAC address. Bits [31:16] are reserved and read as zero.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [15:0] | MAC_ADDR[47:32] | RW | 0x0000 | Upper 16 bits of MAC address. Byte order: [7:0]=Byte 4, [15:8]=Byte 5. |
| [31:16] | RESERVED | RO | 0x0000 | Reserved. Reads as zero. Writes are ignored. |

**Programming Notes:**
- Program this register before enabling the TX path.
- Write strobe for bits [31:16] is ignored.

---

### 3.3 CONTROL - Control Register

**Address:** 0x08  
**Reset Value:** 0x00000000  
**Access:** Read/Write

This register controls the TX and RX data paths. Both paths are disabled after reset.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | TX_ENABLE | RW | 0 | TX Path Enable. 0=Disabled, 1=Enabled. When disabled, no frames are transmitted. |
| [1] | RX_ENABLE | RW | 0 | RX Path Enable. 0=Disabled, 1=Enabled. When disabled, incoming frames are ignored. |
| [31:2] | RESERVED | RO | 0 | Reserved. Reads as zero. Writes are ignored. |

**Field Details:**

**TX_ENABLE (Bit 0):**
| Value | Description |
|-------|-------------|
| 0 | TX path disabled. Frames in TX FIFO are not transmitted. GMII TX outputs are idle. |
| 1 | TX path enabled. Frames are transmitted from TX FIFO to GMII interface. |

**RX_ENABLE (Bit 1):**
| Value | Description |
|-------|-------------|
| 0 | RX path disabled. Incoming GMII frames are discarded. |
| 1 | RX path enabled. Valid frames are received and passed to RX FIFO. |

**Programming Notes:**
- Enable TX/RX paths only after MAC address is configured.
- Disable TX path before reconfiguring MAC address.
- Allow 3 clock cycles for enable signal synchronization to GMII domain.

---

### 3.4 STATUS - Status Register

**Address:** 0x0C  
**Reset Value:** 0x00000000  
**Access:** Read-Only

This register provides real-time status of the TX and RX paths.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | TX_ACTIVE | RO | 0 | TX path is actively transmitting a frame. |
| [1] | RX_ACTIVE | RO | 0 | RX path is actively receiving a frame. |
| [31:2] | RESERVED | RO | 0 | Reserved. Reads as zero. |

**Field Details:**

**TX_ACTIVE (Bit 0):**
| Value | Description |
|-------|-------------|
| 0 | TX path idle. No frame transmission in progress. |
| 1 | TX path active. Frame transmission in progress (preamble, data, FCS, or IFG). |

**RX_ACTIVE (Bit 1):**
| Value | Description |
|-------|-------------|
| 0 | RX path idle. No frame reception in progress. |
| 1 | RX path active. Frame reception in progress. |

**Programming Notes:**
- These bits are synchronized from GMII clock domain.
- Status reflects real-time hardware state.
- Use for diagnostics and debug purposes.

---

### 3.5 INT_STATUS - Interrupt Status Register

**Address:** 0x10  
**Reset Value:** 0x00000000  
**Access:** Read/Write-1-to-Clear (RW1C)

This register indicates pending interrupts. Write a 1 to a bit position to clear that interrupt.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | TX_COMPLETE | RW1C | 0 | TX frame transmission complete. Set when a frame is successfully transmitted. |
| [1] | RX_RECEIVED | RW1C | 0 | RX frame received. Set when a valid frame is received. |
| [2] | RX_CRC_ERR | RW1C | 0 | RX CRC error. Set when a received frame fails CRC check. |
| [3] | RX_RUNT | RW1C | 0 | RX runt frame. Set when a received frame is smaller than 64 bytes. |
| [31:4] | RESERVED | RO | 0 | Reserved. Reads as zero. |

**Interrupt Conditions:**

| Bit | Interrupt | Trigger Condition |
|-----|-----------|-------------------|
| 0 | TX_COMPLETE | Rising edge when frame FCS transmission completes |
| 1 | RX_RECEIVED | Rising edge when valid frame is committed to RX FIFO |
| 2 | RX_CRC_ERR | Rising edge when CRC check fails on received frame |
| 3 | RX_RUNT | Rising edge when received frame is < 64 bytes |

**Programming Notes:**
- Interrupt bits are set by hardware, cleared by software.
- Write 1 to clear; write 0 has no effect.
- Multiple bits can be cleared in a single write.
- Reading does not clear the register.

---

### 3.6 INT_MASK - Interrupt Mask Register

**Address:** 0x14  
**Reset Value:** 0x00000000  
**Access:** Read/Write

This register masks interrupt sources. The `irq` output is the logical OR of all unmasked, pending interrupts.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | TX_COMPLETE_MASK | RW | 0 | TX complete interrupt mask. 0=Masked, 1=Enabled. |
| [1] | RX_RECEIVED_MASK | RW | 0 | RX received interrupt mask. 0=Masked, 1=Enabled. |
| [2] | RX_CRC_ERR_MASK | RW | 0 | RX CRC error interrupt mask. 0=Masked, 1=Enabled. |
| [3] | RX_RUNT_MASK | RW | 0 | RX runt frame interrupt mask. 0=Masked, 1=Enabled. |
| [31:4] | RESERVED | RO | 0 | Reserved. Reads as zero. |

**Interrupt Output Logic:**
```
irq = (INT_STATUS[0] & INT_MASK[0]) |
      (INT_STATUS[1] & INT_MASK[1]) |
      (INT_STATUS[2] & INT_MASK[2]) |
      (INT_STATUS[3] & INT_MASK[3])
```

**Programming Notes:**
- All interrupts are masked by default (reset value 0x0).
- Enable desired interrupts by writing 1 to corresponding mask bits.
- Masking does not clear pending interrupt status.

---

### 3.7 TX_FRAME_CNT - TX Frame Counter

**Address:** 0x18  
**Reset Value:** 0x00000000  
**Access:** Read-Only

This register counts the number of successfully transmitted frames.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | TX_FRAME_CNT | RO | 0x00000000 | 32-bit counter. Increments for each successfully transmitted frame. |

**Counter Behavior:**
- Increments when frame FCS transmission completes.
- Wraps to zero after 0xFFFFFFFF.
- Not affected by TX_ENABLE changes.
- Cleared only by reset.

**Programming Notes:**
- Read periodically for statistics collection.
- Software must handle 32-bit wrap-around.
- Counter is in sys_clk domain (synchronized from GTX domain).

---

### 3.8 RX_FRAME_CNT - RX Frame Counter

**Address:** 0x1C  
**Reset Value:** 0x00000000  
**Access:** Read-Only

This register counts the number of successfully received frames.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | RX_FRAME_CNT | RO | 0x00000000 | 32-bit counter. Increments for each valid received frame. |

**Counter Behavior:**
- Increments when a frame passes CRC check and is committed.
- Does not count errored or runt frames.
- Wraps to zero after 0xFFFFFFFF.
- Cleared only by reset.

**Programming Notes:**
- Read periodically for statistics collection.
- Compare with RX_ERR_CNT for error rate calculation.
- Counter is in sys_clk domain (synchronized from RX domain).

---

### 3.9 RX_ERR_CNT - RX Error Counter

**Address:** 0x20  
**Reset Value:** 0x00000000  
**Access:** Read-Only

This register counts the number of received frames with errors.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | RX_ERR_CNT | RO | 0x00000000 | 32-bit counter. Increments for each errored frame. |

**Error Conditions Counted:**
- CRC check failure
- Runt frame (< 64 bytes including FCS)
- GMII RX_ER assertion during frame

**Counter Behavior:**
- Increments once per errored frame (not per error type).
- Wraps to zero after 0xFFFFFFFF.
- Cleared only by reset.

**Programming Notes:**
- Use INT_STATUS for error type differentiation.
- Error rate = RX_ERR_CNT / (RX_FRAME_CNT + RX_ERR_CNT).

---

### 3.10 VERSION - Version Register

**Address:** 0x24  
**Reset Value:** 0x00010000  
**Access:** Read-Only

This register contains the IP version number. Value is fixed at synthesis time.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [7:0] | PATCH | RO | 0x00 | Patch version number. |
| [15:8] | MINOR | RO | 0x00 | Minor version number. |
| [31:16] | MAJOR | RO | 0x0001 | Major version number. |

**Version Format:** MAJOR.MINOR.PATCH

**Current Version:** 1.0.0 (0x00010000)

**Programming Notes:**
- Use for driver compatibility checking.
- Value is configurable via RTL parameter.

---

## 4. Access Types

| Type | Description |
|------|-------------|
| RO | Read-Only. Writes are ignored. |
| RW | Read/Write. Standard read and write access. |
| RW1C | Read/Write-1-to-Clear. Read returns current value. Write 1 clears bit, write 0 has no effect. |

---

## 5. Reset Behavior

### System Reset (sys_rst_n)

When `sys_rst_n` is asserted (active low):
- All RW registers reset to their default values.
- All counters reset to zero.
- Interrupt status clears.
- TX and RX paths are disabled.

### Reset Timing

| Signal | Reset Requirement |
|--------|-------------------|
| sys_rst_n | Minimum 2 sys_clk cycles |
| gtx_rst_n | Minimum 2 gtx_clk cycles |
| rx_rst_n | Minimum 2 rx_clk cycles |

---

## 6. Programming Guidelines

### Initial Configuration Sequence

1. Assert system reset.
2. Release system reset.
3. Read VERSION register to verify IP presence.
4. Program MAC_ADDR_LO register.
5. Program MAC_ADDR_HI register.
6. Configure INT_MASK for desired interrupts.
7. Enable TX and RX paths via CONTROL register.

### Interrupt Handling

1. Read INT_STATUS to determine interrupt source.
2. Service the interrupt (e.g., read received frame).
3. Write back INT_STATUS value to clear handled interrupts.
4. Return from interrupt handler.

### Statistics Collection

1. Periodically read TX_FRAME_CNT, RX_FRAME_CNT, RX_ERR_CNT.
2. Store values and compute deltas for rate calculations.
3. Handle 32-bit counter wrap-around in software.

### Error Conditions

| Condition | Response |
|-----------|----------|
| Access to reserved address | AXI DECERR response |
| Write to RO register | Write ignored, AXI OKAY response |
| Read from unimplemented address | Returns 0x00000000, AXI DECERR response |

---

*End of Document*
