# Ethernet Controller IP - Accessible Registers

**Document Version:** 2.0  
**IP Version:** 2.0.0  
**Date:** January 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Register Map Summary](#2-register-map-summary)
3. [MAC Register Descriptions](#3-mac-register-descriptions)
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
4. [DMA Register Descriptions](#4-dma-register-descriptions)
   - [TX DMA Registers](#41-tx-dma-registers)
   - [RX DMA Registers](#42-rx-dma-registers)
   - [DMA Interrupt Registers](#43-dma-interrupt-registers)
5. [Access Types](#5-access-types)
6. [Reset Behavior](#6-reset-behavior)
7. [Programming Guidelines](#7-programming-guidelines)

---

## 1. Overview

This document describes the accessible registers of the Ethernet Controller IP. The IP includes the Gigabit Ethernet MAC and an optional DMA subsystem (enabled via the `DMA_ENABLE` parameter). All registers are accessible via a single AXI4-Lite slave interface. The register interface operates in the system clock domain (`sys_clk`).

### Interface Specifications

| Parameter | Value |
|-----------|-------|
| Interface Protocol | AXI4-Lite |
| Data Width | 32 bits |
| Address Width | 10 bits |
| Byte Addressing | Yes (word-aligned) |
| Endianness | Little-endian |
| Clock Domain | sys_clk |

### Register Space

| Region | Address Range | Description |
|--------|---------------|-------------|
| MAC Registers | 0x000 - 0x1FF | MAC configuration and status |
| DMA Registers | 0x200 - 0x3FF | DMA configuration (when DMA_ENABLE=1) |

**Note:** When `DMA_ENABLE=0`, accesses to addresses 0x200-0x3FF return DECERR.

---

## 2. Register Map Summary

### MAC Registers (0x000 - 0x1FF)

| Offset | Name | Width | Access | Reset Value | Description |
|--------|------|-------|--------|-------------|-------------|
| 0x000 | MAC_ADDR_LO | 32 | RW | 0x00000000 | MAC Address [31:0] |
| 0x004 | MAC_ADDR_HI | 16 | RW | 0x0000 | MAC Address [47:32] |
| 0x008 | CONTROL | 2 | RW | 0x00 | TX/RX Enable Control |
| 0x00C | STATUS | 2 | RO | 0x00 | TX/RX Active Status |
| 0x010 | INT_STATUS | 4 | RW1C | 0x0 | Interrupt Status |
| 0x014 | INT_MASK | 4 | RW | 0x0 | Interrupt Mask |
| 0x018 | TX_FRAME_CNT | 32 | RO | 0x00000000 | TX Frame Counter |
| 0x01C | RX_FRAME_CNT | 32 | RO | 0x00000000 | RX Frame Counter |
| 0x020 | RX_ERR_CNT | 32 | RO | 0x00000000 | RX Error Counter |
| 0x024 | VERSION | 32 | RO | 0x00020000 | IP Version |

### DMA Registers (0x200 - 0x3FF, when DMA_ENABLE=1)

#### TX DMA Registers (0x200 - 0x23F)

| Offset | Name | Width | Access | Reset Value | Description |
|--------|------|-------|--------|-------------|-------------|
| 0x200 | DMA_TX_CTRL | 3 | RW | 0x0 | TX DMA Control |
| 0x204 | DMA_TX_STATUS | 3 | RO | 0x0 | TX DMA Status |
| 0x208 | DMA_TX_DESC_LO | 32 | RW | 0x00000000 | TX Descriptor Ring Base Low |
| 0x20C | DMA_TX_DESC_HI | 32 | RW | 0x00000000 | TX Descriptor Ring Base High |
| 0x210 | DMA_TX_RING_SIZE | 16 | RW | 0x0100 | TX Ring Size (descriptors) |
| 0x214 | DMA_TX_HEAD_PTR | 16 | RW | 0x0000 | TX Head Pointer (SW writes) |
| 0x218 | DMA_TX_TAIL_PTR | 16 | RO | 0x0000 | TX Tail Pointer (HW updates) |
| 0x21C | DMA_TX_PKT_CNT | 32 | RO | 0x00000000 | TX DMA Packet Counter |

#### RX DMA Registers (0x240 - 0x27F)

| Offset | Name | Width | Access | Reset Value | Description |
|--------|------|-------|--------|-------------|-------------|
| 0x240 | DMA_RX_CTRL | 3 | RW | 0x0 | RX DMA Control |
| 0x244 | DMA_RX_STATUS | 3 | RO | 0x0 | RX DMA Status |
| 0x248 | DMA_RX_DESC_LO | 32 | RW | 0x00000000 | RX Descriptor Ring Base Low |
| 0x24C | DMA_RX_DESC_HI | 32 | RW | 0x00000000 | RX Descriptor Ring Base High |
| 0x250 | DMA_RX_RING_SIZE | 16 | RW | 0x0100 | RX Ring Size (descriptors) |
| 0x254 | DMA_RX_HEAD_PTR | 16 | RO | 0x0000 | RX Head Pointer (HW updates) |
| 0x258 | DMA_RX_TAIL_PTR | 16 | RW | 0x0000 | RX Tail Pointer (SW writes) |
| 0x25C | DMA_RX_PKT_CNT | 32 | RO | 0x00000000 | RX DMA Packet Counter |

#### DMA Interrupt Registers (0x280 - 0x29F)

| Offset | Name | Width | Access | Reset Value | Description |
|--------|------|-------|--------|-------------|-------------|
| 0x280 | DMA_INT_STATUS | 5 | RW1C | 0x0 | DMA Interrupt Status |
| 0x284 | DMA_INT_MASK | 5 | RW | 0x0 | DMA Interrupt Mask |
| 0x288 | DMA_INT_COALESCE | 32 | RW | 0x00010001 | Interrupt Coalescing Config |

---

## 3. MAC Register Descriptions

### 3.1 MAC_ADDR_LO - MAC Address Low

**Address:** 0x000  
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

**Address:** 0x004  
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

**Address:** 0x008  
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

**Address:** 0x00C  
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

**Address:** 0x010  
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

**Address:** 0x014  
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

**Address:** 0x018  
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

**Address:** 0x01C  
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

**Address:** 0x020  
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

**Address:** 0x024  
**Reset Value:** 0x00020000  
**Access:** Read-Only

This register contains the IP version number. Value is fixed at synthesis time.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [7:0] | PATCH | RO | 0x00 | Patch version number. |
| [15:8] | MINOR | RO | 0x00 | Minor version number. |
| [31:16] | MAJOR | RO | 0x0002 | Major version number. |

**Version Format:** MAJOR.MINOR.PATCH

**Current Version:** 2.0.0 (0x00020000)

**Programming Notes:**
- Use for driver compatibility checking.
- Value is configurable via RTL parameter.

---

## 4. DMA Register Descriptions

The DMA subsystem is optionally included based on the `DMA_ENABLE` parameter. When enabled, it provides scatter-gather DMA capabilities for efficient packet transfer between system memory and the MAC.

### 4.1 TX DMA Registers

#### 4.1.1 DMA_TX_CTRL - TX DMA Control

**Address:** 0x200  
**Reset Value:** 0x00000000  
**Access:** Read/Write

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | ENABLE | RW | 0 | TX DMA channel enable. |
| [1] | RESET | RW/SC | 0 | TX channel soft reset (self-clearing). |
| [2] | IRQ_EN | RW | 0 | TX interrupt enable. |
| [31:3] | RESERVED | RO | 0 | Reserved. |

#### 4.1.2 DMA_TX_STATUS - TX DMA Status

**Address:** 0x204  
**Reset Value:** 0x00000000  
**Access:** Read-Only

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | BUSY | RO | 0 | TX DMA is actively processing descriptors. |
| [1] | HALTED | RO | 0 | TX DMA is halted (disabled or error). |
| [2] | ERROR | RO | 0 | TX DMA encountered an error. |
| [31:3] | RESERVED | RO | 0 | Reserved. |

#### 4.1.3 DMA_TX_DESC_LO/HI - TX Descriptor Ring Base

**Address:** 0x208 (Low), 0x20C (High)  
**Reset Value:** 0x00000000  
**Access:** Read/Write

64-bit physical address of the TX descriptor ring in system memory.

#### 4.1.4 DMA_TX_RING_SIZE - TX Ring Size

**Address:** 0x210  
**Reset Value:** 0x00000100 (256 descriptors)  
**Access:** Read/Write

Number of descriptors in the TX ring. Must be power of 2.

#### 4.1.5 DMA_TX_HEAD_PTR - TX Head Pointer

**Address:** 0x214  
**Reset Value:** 0x00000000  
**Access:** Read/Write

Software writes this to indicate new descriptors are available.

#### 4.1.6 DMA_TX_TAIL_PTR - TX Tail Pointer

**Address:** 0x218  
**Reset Value:** 0x00000000  
**Access:** Read-Only

Hardware updates this as descriptors are processed.

#### 4.1.7 DMA_TX_PKT_CNT - TX Packet Counter

**Address:** 0x21C  
**Reset Value:** 0x00000000  
**Access:** Read-Only

32-bit counter of packets transmitted by DMA.

---

### 4.2 RX DMA Registers

#### 4.2.1 DMA_RX_CTRL - RX DMA Control

**Address:** 0x240  
**Reset Value:** 0x00000000  
**Access:** Read/Write

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | ENABLE | RW | 0 | RX DMA channel enable. |
| [1] | RESET | RW/SC | 0 | RX channel soft reset (self-clearing). |
| [2] | IRQ_EN | RW | 0 | RX interrupt enable. |
| [31:3] | RESERVED | RO | 0 | Reserved. |

#### 4.2.2 DMA_RX_STATUS - RX DMA Status

**Address:** 0x244  
**Reset Value:** 0x00000000  
**Access:** Read-Only

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | BUSY | RO | 0 | RX DMA is actively processing. |
| [1] | HALTED | RO | 0 | RX DMA is halted. |
| [2] | ERROR | RO | 0 | RX DMA error occurred. |
| [31:3] | RESERVED | RO | 0 | Reserved. |

#### 4.2.3 DMA_RX_DESC_LO/HI - RX Descriptor Ring Base

**Address:** 0x248 (Low), 0x24C (High)  
**Reset Value:** 0x00000000  
**Access:** Read/Write

64-bit physical address of the RX descriptor ring.

#### 4.2.4 DMA_RX_RING_SIZE - RX Ring Size

**Address:** 0x250  
**Reset Value:** 0x00000100 (256 descriptors)  
**Access:** Read/Write

Number of descriptors in the RX ring.

#### 4.2.5 DMA_RX_HEAD_PTR - RX Head Pointer

**Address:** 0x254  
**Reset Value:** 0x00000000  
**Access:** Read-Only

Hardware updates this as packets are received.

#### 4.2.6 DMA_RX_TAIL_PTR - RX Tail Pointer

**Address:** 0x258  
**Reset Value:** 0x00000000  
**Access:** Read/Write

Software writes this to indicate buffer descriptors are available.

#### 4.2.7 DMA_RX_PKT_CNT - RX Packet Counter

**Address:** 0x25C  
**Reset Value:** 0x00000000  
**Access:** Read-Only

32-bit counter of packets received by DMA.

---

### 4.3 DMA Interrupt Registers

#### 4.3.1 DMA_INT_STATUS - DMA Interrupt Status

**Address:** 0x280  
**Reset Value:** 0x00000000  
**Access:** Read/Write-1-to-Clear

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | TX_DONE | RW1C | 0 | TX packet complete. |
| [1] | TX_ERR | RW1C | 0 | TX error occurred. |
| [2] | RX_DONE | RW1C | 0 | RX packet complete. |
| [3] | RX_ERR | RW1C | 0 | RX error occurred. |
| [4] | DESC_ERR | RW1C | 0 | Descriptor fetch/write error. |
| [31:5] | RESERVED | RO | 0 | Reserved. |

#### 4.3.2 DMA_INT_MASK - DMA Interrupt Mask

**Address:** 0x284  
**Reset Value:** 0x00000000  
**Access:** Read/Write

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [4:0] | MASK | RW | 0 | Interrupt mask bits (1=enabled). |
| [31:5] | RESERVED | RO | 0 | Reserved. |

**DMA Interrupt Output:**
```
dma_irq = |(DMA_INT_STATUS & DMA_INT_MASK)
```

#### 4.3.3 DMA_INT_COALESCE - Interrupt Coalescing

**Address:** 0x288  
**Reset Value:** 0x00010001  
**Access:** Read/Write

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [15:0] | PKT_CNT | RW | 0x0001 | Packets before interrupt. |
| [31:16] | TIMEOUT | RW | 0x0001 | Timeout in microseconds. |

---

## 5. Access Types

| Type | Description |
|------|-------------|
| RO | Read-Only. Writes are ignored. |
| RW | Read/Write. Standard read and write access. |
| RW1C | Read/Write-1-to-Clear. Read returns current value. Write 1 clears bit, write 0 has no effect. |
| RW/SC | Read/Write, Self-Clearing. Bit clears automatically after action completes. |

---

## 6. Reset Behavior

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

## 7. Programming Guidelines

### Initial Configuration Sequence (MAC Only Mode)

1. Assert system reset.
2. Release system reset.
3. Read VERSION register to verify IP presence.
4. Program MAC_ADDR_LO register.
5. Program MAC_ADDR_HI register.
6. Configure INT_MASK for desired interrupts.
7. Enable TX and RX paths via CONTROL register.

### Initial Configuration Sequence (DMA Mode)

1. Assert system reset.
2. Release system reset.
3. Read VERSION register to verify IP presence (should be 2.x.x).
4. Program MAC_ADDR_LO and MAC_ADDR_HI.
5. Enable MAC TX and RX via CONTROL register.
6. **TX DMA Setup:**
   - Allocate descriptor ring in system memory.
   - Program DMA_TX_DESC_LO/HI with ring base address.
   - Program DMA_TX_RING_SIZE.
   - Initialize descriptors with OWN=0 (CPU owns).
   - Enable TX DMA via DMA_TX_CTRL.
7. **RX DMA Setup:**
   - Allocate descriptor ring and buffers in system memory.
   - Program DMA_RX_DESC_LO/HI with ring base address.
   - Program DMA_RX_RING_SIZE.
   - Initialize descriptors with OWN=1 (DMA owns) and buffer addresses.
   - Write DMA_RX_TAIL_PTR to indicate available descriptors.
   - Enable RX DMA via DMA_RX_CTRL.
8. Configure DMA_INT_MASK for desired DMA interrupts.

### Transmitting a Packet (DMA Mode)

1. Allocate buffer and copy packet data.
2. Set up TX descriptor with buffer address, length, OWN=1.
3. Advance DMA_TX_HEAD_PTR.
4. Wait for TX_DONE interrupt or poll DMA_TX_TAIL_PTR.
5. Check descriptor status for completion.

### Receiving a Packet (DMA Mode)

1. Wait for RX_DONE interrupt.
2. Read DMA_RX_HEAD_PTR to find completed descriptors.
3. Process received packets from descriptors.
4. Re-initialize processed descriptors with OWN=1.
5. Advance DMA_RX_TAIL_PTR to return descriptors to DMA.

### Interrupt Handling (Dual Interrupt)

The IP provides two interrupt outputs: `mac_irq` and `dma_irq`.

**MAC Interrupt Handler:**
1. Read INT_STATUS (0x010).
2. Handle TX_COMPLETE, RX_RECEIVED, error conditions.
3. Write back INT_STATUS to clear handled interrupts.

**DMA Interrupt Handler:**
1. Read DMA_INT_STATUS (0x280).
2. Handle TX_DONE, RX_DONE, error conditions.
3. Write back DMA_INT_STATUS to clear handled interrupts.

### Error Conditions

| Condition | Response |
|-----------|----------|
| Access to reserved address | AXI DECERR response |
| Write to RO register | Write ignored, AXI OKAY response |
| Access to DMA registers when DMA_ENABLE=0 | AXI DECERR response |

---

*End of Document*
