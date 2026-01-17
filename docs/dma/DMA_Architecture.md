# Ethernet DMA Architecture

**Document Version:** 1.0  
**Date:** January 2026  
**Author:** AI-IP Generator

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture Philosophy](#2-architecture-philosophy)
3. [Block-Level Architecture](#3-block-level-architecture)
4. [DMA Subsystem Modules](#4-dma-subsystem-modules)
5. [Integration Modes](#5-integration-modes)
6. [Descriptor Format](#6-descriptor-format)
7. [Register Map](#7-register-map)
8. [Data Flow](#8-data-flow)
9. [Clock and Reset](#9-clock-and-reset)
10. [How to Bypass DMA](#10-how-to-bypass-dma)

---

## 1. Overview

The Ethernet DMA subsystem is a **completely optional**, **removable** add-on to the existing Gigabit Ethernet MAC IP. It provides descriptor-based DMA for embedded systems that require zero-copy packet processing with system memory.

### Key Principles

1. **MAC Independence**: The MAC core has NO knowledge of DMA existence
2. **Optional at Compile Time**: `DMA_ENABLE` parameter controls inclusion
3. **Separate Address Space**: DMA registers are independent of MAC registers
4. **Standard Interfaces**: AXI4-Stream to MAC, AXI4 to memory, AXI4-Lite for control

### Design Inspiration

This DMA follows the architectural patterns found in:
- **Synopsys DesignWare Ethernet QoS**
- **Cadence Tensilica Ethernet Controller**
- **ARM CoreLink NIC-400 Network Interconnect**
- **Intel FPGA Triple-Speed Ethernet**

---

## 2. Architecture Philosophy

### 2.1 Separation of Concerns

```
┌─────────────────────────────────────────────────────────────┐
│                 Ethernet Controller Top                     │
│                                                             │
│  ┌──────────────────┐              ┌───────────────────┐    │
│  │   MAC CORE       │              │   DMA SUBSYSTEM   │    │
│  │                  │  AXI-Stream  │                   │    │
│  │  - TX Engine     │◄────────────►│  - TX DMA         │    │
│  │  - RX Engine     │              │  - RX DMA         │    │
│  │  - CRC           │              │  - Desc Manager   │    │
│  │  - CDC FIFOs     │              │  - AXI4 Master    │    │
│  │  - Registers     │              │  - Interrupt Ctrl │    │
│  └────────┬─────────┘              └─────────┬─────────┘    │
│           │                                  │              │
│       GMII/RGMII                       AXI4 Memory          │
└───────────┼──────────────────────────────────┼──────────────┘
            │                                  │
          PHY                              DDR/SRAM
```

**Critical Rule**: The MAC can be used **without DMA** in these scenarios:
- FPGA streaming applications (direct AXI-Stream connection)
- Custom datapath implementations
- Software-based packet processing
- Test and verification environments

### 2.2 Why This Matters

Unlike monolithic Ethernet controllers where DMA is baked into the MAC:
- **Reusability**: Use the MAC in non-DMA contexts
- **Area Efficiency**: Don't synthesize unused DMA logic
- **Verification**: Test MAC independently of DMA
- **Flexibility**: Replace DMA with custom engines

---

## 3. Block-Level Architecture

### 3.1 Complete System (DMA_ENABLE=1)

```
                                    ┌──────────────────────────────────┐
                                    │   eth_controller_top             │
                                    │                                  │
    ┌────────────────┐              │   ┌──────────────────────────┐   │
    │  CPU/Software  │              │   │     mac_top              │   │
    │                │              │   │                          │   │
    │  AXI-Lite      │──────────────┼──►│  MAC Registers           │   │
    │  (MAC Regs)    │              │   │  TX/RX Engines           │   │
    └────────────────┘              │   │  CRC, CDC FIFOs          │   │
                                    │   └──────────┬───────────────┘   │
    ┌────────────────┐              │              │ AXI-Stream        │
    │  CPU/Software  │              │   ┌──────────▼───────────────┐   │
    │                │              │   │     eth_dma_top          │   │
    │  AXI-Lite      │──────────────┼──►│                          │   │
    │  (DMA Regs)    │              │   │  ┌────────────────────┐  │   │
    └────────────────┘              │   │  │  eth_tx_dma        │  │   │
                                    │   │  │  - Desc fetch      │  │   │
    ┌────────────────┐              │   │  │  - Data read       │  │   │
    │  System Memory │◄─────────────┼───┤  │  - Stream to MAC   │  │   │
    │  (DDR/SRAM)    │  AXI4 Master │   │  └────────────────────┘  │   │
    │                │              │   │                          │   │
    │  - Descriptors │              │   │  ┌────────────────────┐  │   │
    │  - Packet Data │              │   │  │  eth_rx_dma        │  │   │
    └────────────────┘              │   │  │  - Receive from MAC│  │   │
                                    │   │  │  - Data write      │  │   │
                                    │   │  │  - Desc writeback  │  │   │
                                    │   │  └────────────────────┘  │   │
                                    │   │                          │   │
                                    │   │  ┌────────────────────┐  │   │
                                    │   │  │  eth_dma_desc      │  │   │
                                    │   │  │  - AXI4 Master     │  │   │
                                    │   │  │  - Arbitration     │  │   │
                                    │   │  │  - Burst Engine    │  │   │
                                    │   │  └────────────────────┘  │   │
                                    │   └──────────────────────────┘   │
                                    └──────────────────────────────────┘
```

### 3.2 MAC-Only System (DMA_ENABLE=0)

```
                                    ┌──────────────────────────────────┐
                                    │   eth_controller_top             │
                                    │                                  │
    ┌────────────────┐              │   ┌──────────────────────────┐   │
    │  CPU/Software  │              │   │     mac_top              │   │
    │                │              │   │                          │   │
    │  AXI-Lite      │──────────────┼──►│  MAC Registers           │   │
    │  (MAC Regs)    │              │   │  TX/RX Engines           │   │
    └────────────────┘              │   │  CRC, CDC FIFOs          │   │
                                    │   └──────────┬───────────────┘   │
    ┌────────────────┐              │              │ AXI-Stream        │
    │  Application   │              │              │ (Direct)          │
    │                │              │   ┌──────────▼───────────────┐   │
    │  AXI-Stream TX │──────────────┼──►│  DMA Bypassed           │   │
    │  AXI-Stream RX │◄─────────────┼───┤  (Passthrough)          │   │
    │                │              │   └──────────────────────────┘   │
    └────────────────┘              │                                  │
                                    │   DMA registers return DECERR     │
                                    │   AXI4 memory interface tied off  │
                                    └──────────────────────────────────┘
```

---

## 4. DMA Subsystem Modules

### 4.1 eth_dma_top.v
**Top-level DMA wrapper with bypass logic**

- **Functionality**: 
  - Instantiates all DMA submodules when `DMA_ENABLE=1`
  - Provides direct passthrough when `DMA_ENABLE=0`
  - Connects MAC AXI-Stream to either DMA or user interfaces
  
- **Key Feature**: 
  - Generate block conditionally instantiates DMA
  - Zero area overhead when DMA_ENABLE=0

### 4.2 eth_tx_dma.v
**TX DMA Engine**

- **Responsibilities**:
  1. Fetch TX descriptors from memory
  2. Check ownership bit (CPU → DMA transfer)
  3. Read packet payload from memory
  4. Stream to MAC via AXI-Stream (assert `tlast` on last byte)
  5. Update descriptor with completion status
  6. Generate TX completion interrupt

- **State Machine**:
  ```
  IDLE → FETCH_DESC → WAIT_DESC → CHECK_OWN → READ_MEM → 
  STREAM_DATA → WRITEBACK → NEXT_DESC → IDLE
  ```

### 4.3 eth_rx_dma.v
**RX DMA Engine**

- **Responsibilities**:
  1. Fetch RX descriptors from memory
  2. Check ownership bit (CPU → DMA transfer)
  3. Receive packet from MAC (monitor `tlast`)
  4. Accumulate bytes (8-bit → 64-bit data width conversion)
  5. Write packet to memory
  6. Update descriptor with actual length and frame status
  7. Generate RX completion interrupt

- **State Machine**:
  ```
  IDLE → FETCH_DESC → WAIT_DESC → CHECK_OWN → RECEIVE → 
  ACCUMULATE → WRITE_MEM → WRITEBACK → NEXT_DESC → IDLE
  ```

### 4.4 eth_dma_desc.v
**Descriptor Manager and AXI4 Master**

- **Responsibilities**:
  1. Centralized AXI4 master for all memory access
  2. Arbitrate between TX/RX descriptor fetches
  3. Arbitrate between TX/RX data transfers
  4. Handle descriptor reads (128-bit = 2 x 64-bit beats)
  5. Handle descriptor writebacks
  6. Burst optimization for data transfers

- **Priority** (highest to lowest):
  1. Descriptor fetches (avoid starvation)
  2. Descriptor writebacks
  3. RX data writes (prevent overflow)
  4. TX data reads

### 4.5 eth_dma_regs.v
**DMA Control Registers (AXI4-Lite)**

- **Functionality**:
  - Configure descriptor ring base addresses
  - Set ring sizes
  - Enable/disable TX/RX DMA
  - Interrupt status and mask
  - Statistics counters

### 4.6 eth_dma_irq.v
**Interrupt Controller**

- **Functionality**:
  - Combine interrupt sources
  - Apply interrupt masks
  - Generate separate and combined interrupt outputs

---

## 5. Integration Modes

### Mode 1: Full DMA (Embedded Systems)

**Use Case**: ARM/RISC-V SoC with DDR memory

```verilog
eth_controller_top #(
    .DMA_ENABLE         (1),
    .M_AXI_ADDR_WIDTH   (32),
    .M_AXI_DATA_WIDTH   (64),
    .DESC_RING_DEPTH    (8)   // 256 descriptors
) u_eth (
    // Connect all interfaces
    .s_axi_mac_*        (/* MAC register interface */),
    .s_axi_dma_*        (/* DMA register interface */),
    .m_axi_mem_*        (/* Connect to memory controller */),
    .gmii_*             (/* Connect to PHY */),
    .irq_*              (/* Connect to interrupt controller */)
);
```

**Address Map Example**:
- `0x4000_0000`: MAC registers (256 bytes)
- `0x4000_1000`: DMA registers (256 bytes)

### Mode 2: MAC-Only (FPGA Streaming)

**Use Case**: FPGA with custom packet processing logic

```verilog
eth_controller_top #(
    .DMA_ENABLE         (0)    // Disable DMA
) u_eth (
    // MAC register interface
    .s_axi_mac_*        (/* MAC register interface */),
    
    // User streaming interface
    .s_axis_user_tx_*   (/* From packet generator */),
    .m_axis_user_rx_*   (/* To packet processor */),
    
    // DMA interfaces tied off or ignored
    .s_axi_dma_*        (/* Returns DECERR */),
    .m_axi_mem_*        (/* Tied to safe values */),
    
    .gmii_*             (/* Connect to PHY */)
);
```

### Mode 3: Verification Environment

**Use Case**: UVM testbench

```verilog
// Instantiate with DMA disabled for MAC-only tests
eth_controller_top #(
    .DMA_ENABLE         (0)
) dut (...);

// Or with DMA enabled for full system tests
eth_controller_top #(
    .DMA_ENABLE         (1)
) dut (...);
```

---

## 6. Descriptor Format

### 6.1 TX Descriptor (128 bits)

```
Offset | Bits      | Field          | Type | Description
-------|-----------|----------------|------|----------------------------------
0x00   | [63:0]    | buffer_addr    | RW   | Physical address of TX buffer
0x08   | [79:64]   | buffer_len     | RW   | Length of packet (bytes)
       | [95:80]   | reserved       | -    | Reserved
       | [96]      | OWN            | RW   | 0=CPU, 1=DMA
       | [97]      | LAST           | RW   | Last descriptor in packet
       | [98]      | CRC_EN         | RW   | Enable CRC (unused, MAC handles)
       | [99]      | INT_EN         | RW   | Generate interrupt on completion
       | [111:100] | reserved       | -    | Reserved
       | [112]     | DONE           | RO   | Transmission complete (DMA writes)
       | [113]     | ERR            | RO   | Transmission error (DMA writes)
       | [127:114] | reserved       | -    | Reserved
```

### 6.2 RX Descriptor (128 bits)

```
Offset | Bits      | Field          | Type | Description
-------|-----------|----------------|------|----------------------------------
0x00   | [63:0]    | buffer_addr    | RW   | Physical address of RX buffer
0x08   | [79:64]   | buffer_len     | RW   | Size of RX buffer (max packet)
       | [95:80]   | reserved       | -    | Reserved
       | [96]      | OWN            | RW   | 0=CPU, 1=DMA
       | [97]      | WRAP           | RW   | Wrap to start of ring
       | [98]      | INT_EN         | RW   | Generate interrupt on reception
       | [111:99]  | reserved       | -    | Reserved
       | [112]     | DONE           | RO   | Reception complete (DMA writes)
       | [113]     | ERR            | RO   | Reception error (DMA writes)
       | [114]     | CRC_ERR        | RO   | CRC error detected (DMA writes)
       | [127:115] | actual_len     | RO   | Actual received length (DMA writes)
```

### 6.3 Descriptor Ring Structure

```
Memory Layout:
┌─────────────────────┐ ← base_addr
│  Descriptor 0       │
│  (16 bytes)         │
├─────────────────────┤ ← base_addr + 0x10
│  Descriptor 1       │
│  (16 bytes)         │
├─────────────────────┤ ← base_addr + 0x20
│  Descriptor 2       │
│  ...                │
├─────────────────────┤
│  Descriptor N-1     │
│  (16 bytes)         │
└─────────────────────┘ ← base_addr + (N * 16)
          ↓
    Wraps to Descriptor 0
```

**Ring Size**: Configured via `DESC_RING_SIZE` register (log2 of number of descriptors)

---

## 7. Register Map

### 7.1 DMA Control Registers

```
Offset | Name                | Access | Reset      | Description
-------|---------------------|--------|------------|---------------------------
0x00   | DMA_CONTROL         | RW     | 0x00000000 | DMA enable/reset control
0x04   | DMA_STATUS          | RO     | 0x00000000 | DMA status
0x08   | TX_DESC_BASE_LO     | RW     | 0x00000000 | TX descriptor base [31:0]
0x0C   | TX_DESC_BASE_HI     | RW     | 0x00000000 | TX descriptor base [63:32]
0x10   | TX_DESC_RING_SIZE   | RW     | 0x00000000 | TX ring size (log2)
0x14   | RX_DESC_BASE_LO     | RW     | 0x00000000 | RX descriptor base [31:0]
0x18   | RX_DESC_BASE_HI     | RW     | 0x00000000 | RX descriptor base [63:32]
0x1C   | RX_DESC_RING_SIZE   | RW     | 0x00000000 | RX ring size (log2)
0x20   | INT_STATUS          | RW1C   | 0x00000000 | Interrupt status
0x24   | INT_MASK            | RW     | 0x00000000 | Interrupt mask
0x28   | TX_PKT_COUNT        | RO     | 0x00000000 | TX packet counter
0x2C   | RX_PKT_COUNT        | RO     | 0x00000000 | RX packet counter
0x30   | TX_ERR_COUNT        | RO     | 0x00000000 | TX error counter
0x34   | RX_ERR_COUNT        | RO     | 0x00000000 | RX error counter
0x38   | DMA_VERSION         | RO     | 0x00010000 | DMA IP version
```

### 7.2 DMA_CONTROL Register (0x00)

```
Bits   | Field      | Type | Description
-------|------------|------|------------------------------------------
[0]    | TX_ENABLE  | RW   | Enable TX DMA (0=disabled, 1=enabled)
[1]    | RX_ENABLE  | RW   | Enable RX DMA (0=disabled, 1=enabled)
[2]    | DMA_RESET  | RW   | Software reset (self-clearing)
[31:3] | RESERVED   | RO   | Reserved (read as 0)
```

### 7.3 INT_STATUS / INT_MASK Registers (0x20, 0x24)

```
Bits   | Field      | Description
-------|------------|--------------------------------------------------
[0]    | TX_DONE    | TX descriptor complete
[1]    | RX_DONE    | RX descriptor complete
[2]    | TX_ERROR   | TX DMA error (AXI error, invalid descriptor)
[3]    | RX_ERROR   | RX DMA error (AXI error, buffer overflow)
[31:4] | RESERVED   | Reserved
```

---

## 8. Data Flow

### 8.1 TX Data Flow

```
1. Software Setup:
   ┌─────────────────┐
   │ CPU prepares:   │
   │ - Packet data   │──► Memory
   │ - TX descriptor │──► Descriptor Ring
   │ - Sets OWN=1    │
   └─────────────────┘

2. DMA Operation:
   ┌──────────────────────────────────────────────────────┐
   │  eth_tx_dma:                                         │
   │  1. Fetch descriptor (OWN=1?)                        │
   │  2. Read packet from memory via eth_dma_desc         │
   │  3. Stream to MAC via AXI-Stream                     │
   │     - Assert tuser=1 on first byte (SOF)            │
   │     - Assert tlast=1 on last byte (EOF)             │
   │  4. Wait for MAC completion                          │
   │  5. Update descriptor (OWN=0, DONE=1)                │
   │  6. Generate interrupt (if INT_EN=1)                 │
   └──────────────────────────────────────────────────────┘

3. MAC Transmission:
   ┌─────────────────┐
   │  mac_top:       │
   │  - Add preamble │
   │  - Add CRC      │──► GMII
   │  - Add padding  │──► PHY
   └─────────────────┘
```

### 8.2 RX Data Flow

```
1. Software Setup:
   ┌─────────────────┐
   │ CPU prepares:   │
   │ - RX buffer     │──► Memory
   │ - RX descriptor │──► Descriptor Ring
   │ - Sets OWN=1    │
   └─────────────────┘

2. MAC Reception:
   ┌─────────────────┐
   │  mac_top:       │
   │  - Strip        │
   │    preamble     │◄── GMII
   │  - Check CRC    │◄── PHY
   │  - Stream to DMA│
   └─────────────────┘

3. DMA Operation:
   ┌──────────────────────────────────────────────────────┐
   │  eth_rx_dma:                                         │
   │  1. Fetch descriptor (OWN=1?)                        │
   │  2. Receive from MAC via AXI-Stream                  │
   │     - Monitor tlast for end of packet               │
   │     - Capture tuser for frame status                │
   │  3. Accumulate bytes (8-bit → 64-bit)                │
   │  4. Write to memory via eth_dma_desc                 │
   │  5. Update descriptor (OWN=0, DONE=1, actual_len)    │
   │  6. Generate interrupt (if INT_EN=1)                 │
   └──────────────────────────────────────────────────────┘
```

---

## 9. Clock and Reset

### 9.1 Clock Domains

The DMA operates in the **system clock domain only**:

```
Clock Domain   | Modules
---------------|--------------------------------------------------
sys_clk        | - All DMA modules
               | - MAC AXI-Stream interfaces (TX/RX FIFOs)
               | - MAC register interface
               | - DMA register interface
               | - AXI4 memory interface
---------------|--------------------------------------------------
gtx_clk        | - MAC TX engine (inside mac_top)
               | - GMII TX interface
---------------|--------------------------------------------------
rx_clk         | - MAC RX engine (inside mac_top)
               | - GMII RX interface
```

**Key Point**: DMA does NOT cross clock domains. All clock crossing is handled by CDC FIFOs **inside the MAC**.

### 9.2 Reset Strategy

```
Reset Signal   | Scope
---------------|--------------------------------------------------
sys_rst_n      | - All DMA logic
               | - MAC system domain (registers, AXI-Stream)
gtx_rst_n      | - MAC TX domain (inside mac_top)
rx_rst_n       | - MAC RX domain (inside mac_top)
```

---

## 10. How to Bypass DMA

### 10.1 Compile-Time Bypass

Set the `DMA_ENABLE` parameter to 0:

```verilog
eth_controller_top #(
    .DMA_ENABLE (0)   // ← Disable DMA
) u_eth (
    // MAC interfaces remain functional
    .s_axi_mac_*        (/* Active */),
    .s_axis_user_tx_*   (/* Active - connect your TX source */),
    .m_axis_user_rx_*   (/* Active - connect your RX sink */),
    .gmii_*             (/* Active */),
    
    // DMA interfaces are disabled
    .s_axi_dma_*        (/* Returns DECERR */),
    .m_axi_mem_*        (/* Tied to safe idle values */),
    .irq_dma_*          (/* All zeros */)
);
```

### 10.2 What Happens When DMA is Bypassed?

1. **AXI-Stream Paths**:
   - `s_axis_user_tx_*` → `mac_tx_*` (Direct passthrough)
   - `mac_rx_*` → `m_axis_user_rx_*` (Direct passthrough)

2. **AXI4-Lite DMA Interface**:
   - All reads return 0x00000000
   - All writes are ignored
   - Response is DECERR (0x11)

3. **AXI4 Memory Interface**:
   - All signals tied to safe idle states
   - No memory transactions

4. **Interrupts**:
   - `irq_dma_tx_done = 0`
   - `irq_dma_rx_done = 0`
   - `irq_dma_tx_error = 0`
   - `irq_dma_rx_error = 0`
   - `irq_dma_combined = 0`

5. **Area Impact**:
   - DMA logic is **not synthesized** (inside generate block)
   - Only passthrough muxes remain (minimal area)

### 10.3 Synthesis Reports

Expected area when `DMA_ENABLE=0`:
- DMA modules: **0 LUTs, 0 FFs** (not instantiated)
- Passthrough logic: **~10 LUTs** (for AXI-Stream routing)

---

## Summary

This DMA subsystem provides:

✅ **Commercial-grade** architecture (inspired by Synopsys, Cadence, ARM)  
✅ **Completely optional** - MAC works standalone  
✅ **Zero area overhead** when disabled  
✅ **Standard interfaces** - AXI4-Stream, AXI4, AXI4-Lite  
✅ **Descriptor-based** operation with ring buffers  
✅ **Flexible configuration** via parameters  
✅ **Professional quality** - one module per file, clean separation  

The DMA can be:
- **Enabled** for embedded systems (ARM/RISC-V SoC)
- **Disabled** for FPGA streaming applications
- **Replaced** with custom DMA engines
- **Verified** independently via UVM

This is **NOT** a monolithic Ethernet controller - it's a **reusable MAC with optional DMA**.
