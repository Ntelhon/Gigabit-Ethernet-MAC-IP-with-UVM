# Ethernet Controller IP - Hardware Features

**Document Version:** 2.0  
**IP Version:** 2.0.0  
**Date:** January 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Feature Summary](#2-feature-summary)
3. [Architecture](#3-architecture)
4. [Module Descriptions](#4-module-descriptions)
5. [DMA Subsystem](#5-dma-subsystem)
6. [Interfaces](#6-interfaces)
7. [Clock Domains](#7-clock-domains)
8. [Reset Architecture](#8-reset-architecture)
9. [Memory Structures](#9-memory-structures)
10. [Signal Reference](#10-signal-reference)
11. [Timing Parameters](#11-timing-parameters)
12. [Configuration Parameters](#12-configuration-parameters)

---

## 1. Overview

The Ethernet Controller IP is a NIC-class architecture combining a Gigabit Ethernet MAC with an optional scatter-gather DMA subsystem. The design supports two operational modes:

- **MAC-only Mode (DMA_ENABLE=0):** Traditional MAC with AXI-Stream interfaces for direct packet access.
- **DMA Mode (DMA_ENABLE=1):** Full NIC functionality with descriptor-based DMA for efficient system integration.

### Key Specifications

| Parameter | Value |
|-----------|-------|
| Line Rate | 1000 Mbps (Gigabit Ethernet) |
| Interface Standard | IEEE 802.3-2018 |
| PHY Interface | GMII / RGMII |
| Data Interface | AXI4-Stream (MAC) / AXI4-MM (DMA) |
| Control Interface | AXI4-Lite (unified) |
| DMA Architecture | Scatter-gather with descriptor rings |
| Technology | Technology-independent RTL |
| Language | Verilog-2001 |

---

## 2. Feature Summary

### MAC Transmission Features

| Feature | Description |
|---------|-------------|
| Automatic Preamble | 7-byte preamble (0x55) and SFD (0xD5) insertion |
| Automatic FCS | IEEE 802.3 CRC-32 generation and insertion |
| Automatic Padding | Frames padded to minimum 64 bytes |
| Inter-Frame Gap | Configurable IFG (default 12 bytes) |
| Store-and-Forward | Complete frame buffered before transmission |

### MAC Reception Features

| Feature | Description |
|---------|-------------|
| Preamble Detection | Automatic preamble and SFD detection |
| FCS Verification | CRC-32 check on all received frames |
| Runt Detection | Frames < 64 bytes flagged and discarded |
| Error Signaling | Frame status reported via tuser signal |
| Promiscuous Mode | All valid frames accepted |

### DMA Features (when DMA_ENABLE=1)

| Feature | Description |
|---------|-------------|
| Scatter-Gather | Descriptor-based DMA for flexible buffer management |
| Ring Buffers | Configurable TX and RX descriptor rings |
| 64-bit Addressing | Support for large system memory |
| Burst Transfers | AXI4 burst reads/writes for efficiency |
| Status Writeback | Automatic descriptor status update |
| Interrupt Coalescing | Configurable packet/time thresholds |

### System Features

| Feature | Description |
|---------|-------------|
| Clock Domain Crossing | Asynchronous FIFOs with Gray-coded pointers |
| AXI4-Lite Registers | Unified configuration interface for MAC + DMA |
| Dual Interrupts | Separate mac_irq and dma_irq outputs |
| Statistics Counters | 32-bit TX/RX frame and error counters |
| Configurable DMA | DMA_ENABLE parameter for MAC-only mode |

---

## 3. Architecture

### Block Diagram (DMA Mode)

```
                              ┌──────────────────────────────────────────────────────────────────────┐
                              │                      eth_controller_top                               │
                              │                                                                       │
    AXI4-Lite ◄──────────────►│  ┌───────────────────┐                                                │
    (0x000-0x3FF)             │  │eth_controller_regs│                                                │
                              │  └────────┬──────────┘                                                │
                              │           │ ┌─────────────┐ ┌─────────────┐                           │
                              │           ├─► mac_regs   │ │ dma_regs    │◄─────────────┐            │
                              │           │ └──────┬──────┘ └──────┬──────┘              │            │
                              │           │        │               │                     │            │
                              │  ┌────────┴────────┴───────────────┴────────────────┐   │            │
                              │  │                     mac_top                       │   │            │
                              │  │  ┌──────────┐    ┌──────────┐    ┌────────────┐  │   │            │
    AXI-Stream TX             │  │  │ TX FIFO  │───►│  mac_tx  │───►│ GMII TX IF │──┼───┼──► GMII TX │
    (from DMA)  ─────────────►│  │  │  (CDC)   │    │          │    │            │  │   │  (gtx_clk) │
                              │  │  └──────────┘    └────┬─────┘    └────────────┘  │   │            │
                              │  │                       │                          │   │            │
                              │  │                 ┌─────┴─────┐                    │   │            │
                              │  │                 │ mac_crc32 │                    │   │            │
                              │  │                 └───────────┘                    │   │            │
                              │  │                                                  │   │            │
    AXI-Stream RX             │  │  ┌──────────┐    ┌──────────┐                    │   │            │
    (to DMA)    ◄─────────────│  │  │ RX FIFO  │◄───│  mac_rx  │◄───────────────────┼───┼─── GMII RX │
                              │  │  │  (CDC)   │    │          │                    │   │  (rx_clk)  │
                              │  │  └──────────┘    └──────────┘                    │   │            │
                              │  └──────────────────────────────────────────────────┘   │            │
                              │                         ▲                               │            │
                              │                         │ AXI-Stream                    │            │
                              │  ┌──────────────────────┴───────────────────────────────┴──────────┐ │
                              │  │                          dma_top                                │ │
                              │  │  ┌──────────┐    ┌──────────┐    ┌──────────┐                   │ │
                              │  │  │ dma_desc │◄──►│ dma_tx   │───►│ AXI-S TX │───────────────────┤ │
                              │  │  │ (rings)  │    │          │    │          │                   │ │
    AXI4 Master ◄────────────►│  │  └─────┬────┘    └──────────┘    └──────────┘                   │ │
    (Memory)                  │  │        │         ┌──────────┐    ┌──────────┐                   │ │
                              │  │        └────────►│ dma_rx   │◄───│ AXI-S RX │◄──────────────────┤ │
                              │  │                  │          │    │          │                   │ │
                              │  │                  └──────────┘    └──────────┘                   │ │
                              │  └─────────────────────────────────────────────────────────────────┘ │
                              │                                                                       │
    Interrupts ◄──────────────│  ┌───────────────────┐                                                │
    mac_irq, dma_irq          │  │eth_controller_irq │                                                │
                              │  └───────────────────┘                                                │
                              └───────────────────────────────────────────────────────────────────────┘
```

### Block Diagram (MAC-Only Mode, DMA_ENABLE=0)

```
                              ┌────────────────────────────────────────────────────────┐
                              │                    eth_controller_top                   │
                              │                                                         │
    AXI4-Lite ◄──────────────►│  ┌───────────────────┐                                  │
    (0x000-0x1FF)             │  │eth_controller_regs│                                  │
                              │  └─────────┬─────────┘                                  │
                              │            │                                            │
                              │  ┌─────────▼─────────────────────────────────────────┐ │
                              │  │                     mac_top                        │ │
    AXI-Stream TX ───────────►│  │  ┌──────────┐    ┌──────────┐    ┌────────────┐   │─┼─► GMII TX
    (sys_clk)                 │  │  │ TX FIFO  │───►│  mac_tx  │───►│ GMII TX IF │   │ │  (gtx_clk)
                              │  │  │  (CDC)   │    │          │    │            │   │ │
                              │  │  └──────────┘    └──────────┘    └────────────┘   │ │
                              │  │                                                    │ │
    AXI-Stream RX ◄───────────│  │  ┌──────────┐    ┌──────────┐                      │ │
    (sys_clk)                 │  │  │ RX FIFO  │◄───│  mac_rx  │◄─────────────────────┼─┼─ GMII RX
                              │  │  │  (CDC)   │    │          │                      │ │  (rx_clk)
                              │  │  └──────────┘    └──────────┘                      │ │
                              │  └────────────────────────────────────────────────────┘ │
                              │                                                         │
    mac_irq ◄─────────────────│  (dma_irq tied low)                                     │
                              └─────────────────────────────────────────────────────────┘
```

### Data Flow (MAC-Only Mode)

**TX Path:**
1. Software writes frame data to AXI-Stream TX interface.
2. Data enters TX CDC FIFO (sys_clk → gtx_clk).
3. MAC TX state machine reads complete frame from FIFO.
4. Preamble and SFD are prepended.
5. CRC-32 is calculated and appended.
6. Frame is transmitted on GMII interface.
7. Inter-frame gap is inserted.

**RX Path:**
1. PHY provides frame data on GMII interface.
2. MAC RX state machine detects preamble and SFD.
3. Frame data is captured and CRC is calculated.
4. CRC is verified at end of frame.
5. Valid frames enter RX CDC FIFO (rx_clk → sys_clk).
6. Software reads frame data from AXI-Stream RX interface.

### Data Flow (DMA Mode)

**TX Path:**
1. Software prepares TX descriptor with buffer address and OWN=1.
2. Software advances TX head pointer.
3. DMA descriptor engine fetches descriptor from memory.
4. TX DMA engine reads packet data via AXI4 bursts.
5. Data is buffered in TX DMA FIFO.
6. DMA streams data to MAC via AXI-Stream.
7. MAC transmits frame on GMII.
8. DMA writes back descriptor status (DONE, OWN=0).

**RX Path:**
1. PHY receives frame on GMII.
2. MAC validates frame and outputs via AXI-Stream.
3. RX DMA engine buffers incoming data.
4. DMA fetches pre-prepared descriptor from ring.
5. RX DMA writes packet data to memory via AXI4 bursts.
6. DMA writes back descriptor with length and status.
7. Interrupt signals packet completion.

---

## 4. Module Descriptions

### 4.1 eth_controller_top

**Purpose:** Top-level Ethernet Controller module.

**File:** `rtl/eth_controller_top.v`

**Functions:**
- Conditional DMA instantiation based on DMA_ENABLE parameter.
- Unified register block integration.
- AXI-Stream routing (external or DMA).
- Dual interrupt aggregation.

**Key Parameters:**
- DMA_ENABLE: Enable/disable DMA subsystem.
- DMA_ADDR_WIDTH: AXI address width (32 or 64).
- DMA_DATA_WIDTH: AXI data width (64).

---

### 4.2 eth_controller_regs

**Purpose:** Unified register address decoder.

**File:** `rtl/eth_controller_regs.v`

**Functions:**
- Routes AXI-Lite transactions to MAC or DMA.
- Address decode: 0x000-0x1FF → MAC, 0x200-0x3FF → DMA.
- Returns DECERR for DMA access when DMA_ENABLE=0.

---

### 4.3 mac_top

**Purpose:** Gigabit Ethernet MAC module.

**File:** `rtl/mac_core/mac_top.v`

**Functions:**
- Instantiates all MAC submodules.
- Implements clock domain crossing synchronizers.
- Connects internal signals between modules.
- Provides AXI-Stream and GMII interface ports.

**Key Logic:**
- TX/RX enable CDC synchronizers (3-stage flip-flops).
- Frame availability toggle signaling for store-and-forward.

---

### 4.4 mac_regs

**Purpose:** MAC AXI4-Lite register interface.

**File:** `rtl/mac_core/mac_regs.v`

**Functions:**
- AXI4-Lite slave state machine.
- Configuration register storage.
- Status register multiplexing.
- Interrupt status capture and masking.

**State Machine:**
- Write: IDLE → WAIT_DATA → RESPONSE
- Read: IDLE → READ_DATA → RESPONSE

**Register Count:** 10 registers (40 bytes).

---

### 4.5 mac_tx

**Purpose:** TX path state machine.

**File:** `rtl/mac_core/mac_tx.v`

**Functions:**
- Frame transmission sequencing.
- Preamble and SFD generation.
- CRC interface control.
- Automatic padding insertion.
- IFG timing generation.

**State Machine States:**

| State | Description |
|-------|-------------|
| ST_IDLE | Waiting for new frame (SOF detection) |
| ST_PREAMBLE | Transmitting 7 preamble bytes |
| ST_SFD | Transmitting Start Frame Delimiter |
| ST_DATA | Transmitting frame data |
| ST_PAD | Transmitting padding bytes |
| ST_FCS | Transmitting 4 FCS bytes |
| ST_IFG | Inter-frame gap (12 bytes default) |

---

### 4.4 mac_rx

**Purpose:** RX path state machine.

**File:** `rtl/mac_core/mac_rx.v`

**Functions:**
- Preamble and SFD detection.
- Frame data capture.
- CRC verification.
- Runt frame detection.
- Error frame handling.

**State Machine States:**

| State | Description |
|-------|-------------|
| ST_IDLE | Waiting for RX_DV assertion |
| ST_PREAMBLE | Detecting preamble pattern |
| ST_SFD | Detecting Start Frame Delimiter |
| ST_DATA | Receiving frame data |
| ST_CHECK | Verifying CRC |
| ST_COMMIT | Frame valid, commit to FIFO |
| ST_DISCARD | Frame invalid, discard |

---

### 4.5 mac_crc32

**Purpose:** IEEE 802.3 CRC-32 calculator.

**File:** `rtl/mac_core/mac_crc32.v`

**Functions:**
- Parallel CRC-32 calculation (8 bits per clock).
- Initialization on frame start.
- CRC output for FCS insertion (TX).
- Residue check for verification (RX).

**Algorithm:**
- Polynomial: 0x04C11DB7 (reflected: 0xEDB88320)
- Initial value: 0xFFFFFFFF
- Final XOR: 0xFFFFFFFF
- Input/output reflection: Yes

**Instances:**
- One instance for TX path (gtx_clk domain).
- One instance for RX path (rx_clk domain).

---

### 4.6 mac_cdc_fifo

**Purpose:** Asynchronous FIFO for clock domain crossing.

**File:** `rtl/mac_core/mac_cdc_fifo.v`

**Functions:**
- Dual-clock FIFO operation.
- Gray-coded pointer synchronization.
- Full and empty flag generation.
- Overflow and underflow protection.

**CDC Safety:**
- Gray coding ensures single-bit pointer changes.
- 2-stage synchronizers for pointer crossing.
- Conservative full/empty for metastability tolerance.

**Instances:**
- TX FIFO: sys_clk (write) → gtx_clk (read)
- RX FIFO: rx_clk (write) → sys_clk (read)

---

### 4.7 mac_gmii_if

**Purpose:** GMII interface logic.

**File:** `rtl/mac_core/mac_gmii_if.v`

**Functions:**
- GMII signal timing.
- TX data registration.
- RX data sampling.
- Collision and carrier sense handling.

---

## 5. DMA Subsystem

The DMA subsystem is conditionally instantiated when `DMA_ENABLE=1`. It provides scatter-gather DMA functionality for efficient packet transfer.

### 5.1 DMA Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         dma_top                              │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                     dma_desc                          │   │
│  │  ┌───────────┐  ┌───────────┐  ┌────────────────┐   │   │
│  │  │ TX Ring   │  │ RX Ring   │  │ AXI Read/Write │   │   │
│  │  │ Manager   │  │ Manager   │  │ for Descriptors│   │   │
│  │  └─────┬─────┘  └─────┬─────┘  └───────┬────────┘   │   │
│  └────────┼──────────────┼────────────────┼────────────┘   │
│           │              │                │                 │
│  ┌────────▼────────┐  ┌──▼──────────┐    │                 │
│  │    dma_tx       │  │   dma_rx    │    │    AXI4 Master │
│  │  ┌──────────┐   │  │ ┌────────┐  │    │    Interface   │
│  │  │ TX FIFO  │   │  │ │RX FIFO │  │    │        │       │
│  │  └────┬─────┘   │  │ └───┬────┘  │    │        ▼       │
│  │       │ AXI-S   │  │     │AXI-S  │    └────► ARBITER   │◄──► Memory
│  │       ▼ to MAC  │  │     ▼to DMA │                      │
│  └─────────────────┘  └─────────────┘                      │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                     dma_regs                          │   │
│  │   TX_CTRL/STATUS  RX_CTRL/STATUS  INT_STATUS/MASK   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 DMA Modules

#### 5.2.1 dma_top

**Purpose:** DMA subsystem top-level integration.

**File:** `rtl/dma/dma_top.v`

**Functions:**
- Integrates descriptor engine, TX DMA, RX DMA.
- AXI4 master arbiter for memory access.
- AXI-Stream connections to MAC.

---

#### 5.2.2 dma_desc

**Purpose:** Descriptor ring management engine.

**File:** `rtl/dma/dma_desc.v`

**Functions:**
- TX and RX descriptor ring management.
- Descriptor fetch from system memory.
- Descriptor writeback with status.
- Head/tail pointer tracking.

**Descriptor Format (16 bytes):**

| Offset | Field | Description |
|--------|-------|-------------|
| 0-3 | addr_lo | Buffer address [31:0] |
| 4-7 | addr_hi | Buffer address [63:32] |
| 8-9 | length | Buffer length / Actual length |
| 10-11 | reserved | Reserved |
| 12-15 | status | Control/status bits |

**Status Bits:**

| Bit | Name | Description |
|-----|------|-------------|
| 0 | OWN | Ownership (0=CPU, 1=DMA) |
| 1 | DONE | Transfer complete |
| 2 | ERR | Error occurred |
| 3 | LAST | Last descriptor of packet |
| 4 | FIRST | First descriptor of packet |

---

#### 5.2.3 dma_tx

**Purpose:** TX DMA engine.

**File:** `rtl/dma/dma_tx.v`

**Functions:**
- Reads packet data from system memory.
- Buffers in internal FIFO.
- Streams to MAC via AXI-Stream.
- Triggers descriptor writeback.

**State Machine:**
- IDLE → CALC_BURST → ISSUE_AR → READ_DATA → STREAM_OUT → WRITEBACK

---

#### 5.2.4 dma_rx

**Purpose:** RX DMA engine.

**File:** `rtl/dma/dma_rx.v`

**Functions:**
- Receives packets from MAC via AXI-Stream.
- Buffers in internal FIFO.
- Writes to system memory via AXI bursts.
- Updates descriptor with actual length.

**State Machine:**
- IDLE → WAIT_SOF → RECEIVE → CALC_BURST → ISSUE_AW → WRITE_DATA → WRITEBACK

---

#### 5.2.5 dma_regs

**Purpose:** DMA register interface.

**File:** `rtl/dma/dma_regs.v`

**Functions:**
- TX DMA control and status.
- RX DMA control and status.
- DMA interrupt status and mask.

---

### 5.3 DMA Performance

| Parameter | Value |
|-----------|-------|
| Max Burst Length | 16 beats (configurable) |
| AXI Data Width | 64 bits |
| Descriptor Fetch Latency | ~20 cycles |
| TX Throughput | Line-rate (1 Gbps) |
| RX Throughput | Line-rate (1 Gbps) |

---

## 6. Interfaces

### 6.1 AXI4-Lite Slave Interface

**Purpose:** Register access for configuration and status.

**Clock Domain:** sys_clk

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| s_axi_awaddr | Input | 10 | Write address |
| s_axi_awvalid | Input | 1 | Write address valid |
| s_axi_awready | Output | 1 | Write address ready |
| s_axi_wdata | Input | 32 | Write data |
| s_axi_wstrb | Input | 4 | Write byte strobes |
| s_axi_wvalid | Input | 1 | Write data valid |
| s_axi_wready | Output | 1 | Write data ready |
| s_axi_bresp | Output | 2 | Write response |
| s_axi_bvalid | Output | 1 | Write response valid |
| s_axi_bready | Input | 1 | Write response ready |
| s_axi_araddr | Input | 8 | Read address |
| s_axi_arvalid | Input | 1 | Read address valid |
| s_axi_arready | Output | 1 | Read address ready |
| s_axi_rdata | Output | 32 | Read data |
| s_axi_rresp | Output | 2 | Read response |
| s_axi_rvalid | Output | 1 | Read data valid |
| s_axi_rready | Input | 1 | Read data ready |

**Protocol:** AXI4-Lite (AMBA 4.0 specification).

---

### 5.2 AXI4-Stream TX Interface

**Purpose:** Frame data input from system.

**Clock Domain:** sys_clk

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| tx_axis_tdata | Input | 8 | TX data byte |
| tx_axis_tvalid | Input | 1 | TX data valid |
| tx_axis_tready | Output | 1 | TX ready to accept data |
| tx_axis_tlast | Input | 1 | End of frame marker |
| tx_axis_tuser | Input | 1 | Start of frame marker |

**Protocol:** AXI4-Stream (AMBA 4.0 specification).

**Frame Format:**
- First byte: tuser=1, tlast=0
- Middle bytes: tuser=0, tlast=0
- Last byte: tuser=0, tlast=1

---

### 5.3 AXI4-Stream RX Interface

**Purpose:** Frame data output to system.

**Clock Domain:** sys_clk

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| rx_axis_tdata | Output | 8 | RX data byte |
| rx_axis_tvalid | Output | 1 | RX data valid |
| rx_axis_tready | Input | 1 | System ready to accept data |
| rx_axis_tlast | Output | 1 | End of frame marker |
| rx_axis_tuser | Output | 2 | Frame status {bad, good} |

**Protocol:** AXI4-Stream (AMBA 4.0 specification).

**Frame Status (tuser):**
| Value | Description |
|-------|-------------|
| 2'b01 | Frame good (CRC valid) |
| 2'b10 | Frame bad (CRC error or runt) |

---

### 5.4 GMII Interface

**Purpose:** Physical layer interface.

**TX Signals (Clock Domain: gtx_clk):**

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| gmii_txd | Output | 8 | TX data |
| gmii_tx_en | Output | 1 | TX enable |
| gmii_tx_er | Output | 1 | TX error |

**RX Signals (Clock Domain: rx_clk):**

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| gmii_rxd | Input | 8 | RX data |
| gmii_rx_dv | Input | 1 | RX data valid |
| gmii_rx_er | Input | 1 | RX error |

**Control Signals:**

| Signal | Direction | Width | Clock Domain | Description |
|--------|-----------|-------|--------------|-------------|
| gmii_col | Input | 1 | gtx_clk | Collision detected |
| gmii_crs | Input | 1 | rx_clk | Carrier sense |

**Standard:** IEEE 802.3 GMII specification.

---

### 5.5 Interrupt Interface

**Purpose:** Event notification to system.

**Clock Domain:** sys_clk

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| irq | Output | 1 | Interrupt request (active high) |

**Interrupt Sources:**
- TX frame complete
- RX frame received
- RX CRC error
- RX runt frame

---

## 6. Clock Domains

### 6.1 Clock Summary

| Clock | Frequency | Domain | Usage |
|-------|-----------|--------|-------|
| sys_clk | 100 MHz (typical) | System | AXI interfaces, registers |
| gtx_clk | 125 MHz | GMII TX | TX path, TX FIFO read |
| rx_clk | 125 MHz | GMII RX | RX path, RX FIFO write |

### 6.2 Clock Domain Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  ┌──────────────────┐        ┌──────────────────┐                   │
│  │   sys_clk        │        │   gtx_clk        │                   │
│  │   Domain         │        │   Domain         │                   │
│  │                  │        │                  │                   │
│  │  - mac_regs      │   CDC  │  - mac_tx        │                   │
│  │  - AXI-Lite      │◄──────►│  - TX CRC        │                   │
│  │  - AXI-Stream    │  FIFO  │  - GMII TX       │                   │
│  │  - Interrupt     │        │                  │                   │
│  └──────────────────┘        └──────────────────┘                   │
│           ▲                                                         │
│           │                                                         │
│           │ CDC FIFO                                                │
│           │                                                         │
│           ▼                                                         │
│  ┌──────────────────┐                                               │
│  │   rx_clk         │                                               │
│  │   Domain         │                                               │
│  │                  │                                               │
│  │  - mac_rx        │                                               │
│  │  - RX CRC        │                                               │
│  │  - GMII RX       │                                               │
│  └──────────────────┘                                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.3 Clock Requirements

| Parameter | Requirement |
|-----------|-------------|
| sys_clk frequency | ≥ 25 MHz (recommended ≥ 100 MHz) |
| gtx_clk frequency | 125 MHz ± 100 ppm |
| rx_clk frequency | 125 MHz ± 100 ppm |
| Clock jitter | < 100 ps peak-to-peak |
| Clock duty cycle | 45% - 55% |

### 6.4 CDC Signal List

| Signal | Source Domain | Destination Domain | Synchronization |
|--------|---------------|-------------------|-----------------|
| tx_enable | sys_clk | gtx_clk | 3-stage FF |
| rx_enable | sys_clk | rx_clk | 3-stage FF |
| tx_frame_cnt | gtx_clk | sys_clk | Gray-coded CDC |
| rx_frame_cnt | rx_clk | sys_clk | Gray-coded CDC |
| TX data | sys_clk | gtx_clk | Async FIFO |
| RX data | rx_clk | sys_clk | Async FIFO |
| Interrupt pulses | gtx_clk/rx_clk | sys_clk | Pulse sync |

---

## 7. Reset Architecture

### 7.1 Reset Signals

| Signal | Domain | Polarity | Description |
|--------|--------|----------|-------------|
| sys_rst_n | sys_clk | Active low | System domain reset |
| gtx_rst_n | gtx_clk | Active low | TX domain reset |
| rx_rst_n | rx_clk | Active low | RX domain reset |

### 7.2 Reset Requirements

| Parameter | Requirement |
|-----------|-------------|
| Minimum pulse width | 2 clock cycles per domain |
| Release timing | Synchronous to respective clock |
| Reset sequence | Assert all → Release sys_rst_n → Release gtx_rst_n → Release rx_rst_n |

### 7.3 Reset Effects

**sys_rst_n:**
- Clears all configuration registers.
- Resets AXI state machines.
- Disables TX and RX paths.
- Clears interrupt status.
- Resets statistics counters.

**gtx_rst_n:**
- Resets TX state machine to IDLE.
- Clears TX FIFO read pointer.
- Deasserts GMII TX outputs.
- Resets TX CRC calculator.

**rx_rst_n:**
- Resets RX state machine to IDLE.
- Clears RX FIFO write pointer.
- Resets RX CRC calculator.
- Clears RX error flags.

---

## 8. Memory Structures

### 8.1 TX FIFO

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| Data Width | 10 bits | {sof, eof, data[7:0]} |
| Depth | 256 entries | 2^8 = 256 (configurable) |
| Total Size | 320 bytes | 256 × 10 bits |
| Implementation | Inferred RAM | Dual-port RAM |

**Write Port (sys_clk):**
- Write enable: tx_fifo_wr_en
- Write data: {tx_axis_tuser, tx_axis_tlast, tx_axis_tdata}

**Read Port (gtx_clk):**
- Read enable: tx_fifo_rd_en
- Read data: {tx_sof, tx_eof, tx_data}

---

### 8.2 RX FIFO

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| Data Width | 12 bits | {bad, good, sof, eof, data[7:0]} |
| Depth | 256 entries | 2^8 = 256 (configurable) |
| Total Size | 384 bytes | 256 × 12 bits |
| Implementation | Inferred RAM | Dual-port RAM |

**Write Port (rx_clk):**
- Write enable: rx_fifo_wr_en
- Write data: {rx_frame_bad, rx_frame_good, rx_sof, rx_eof, rx_data}

**Read Port (sys_clk):**
- Read enable: rx_fifo_rd_en
- Read data: {rx_axis_tuser, rx_axis_tlast, rx_axis_tdata}

---

### 8.3 Register Space

| Parameter | Value |
|-----------|-------|
| Total Registers | 10 |
| Register Width | 32 bits |
| Total Size | 40 bytes |
| Implementation | Flip-flops |

---

## 9. Signal Reference

### 9.1 Top-Level Ports

| Signal | Direction | Width | Clock Domain | Description |
|--------|-----------|-------|--------------|-------------|
| sys_clk | Input | 1 | - | System clock |
| sys_rst_n | Input | 1 | sys_clk | System reset (active low) |
| gtx_clk | Input | 1 | - | GMII TX clock |
| gtx_rst_n | Input | 1 | gtx_clk | TX reset (active low) |
| rx_clk | Input | 1 | - | GMII RX clock |
| rx_rst_n | Input | 1 | rx_clk | RX reset (active low) |
| s_axi_* | Mixed | Various | sys_clk | AXI4-Lite interface |
| tx_axis_* | Mixed | Various | sys_clk | AXI4-Stream TX |
| rx_axis_* | Mixed | Various | sys_clk | AXI4-Stream RX |
| gmii_txd | Output | 8 | gtx_clk | GMII TX data |
| gmii_tx_en | Output | 1 | gtx_clk | GMII TX enable |
| gmii_tx_er | Output | 1 | gtx_clk | GMII TX error |
| gmii_rxd | Input | 8 | rx_clk | GMII RX data |
| gmii_rx_dv | Input | 1 | rx_clk | GMII RX data valid |
| gmii_rx_er | Input | 1 | rx_clk | GMII RX error |
| gmii_col | Input | 1 | gtx_clk | Collision detect |
| gmii_crs | Input | 1 | rx_clk | Carrier sense |
| irq | Output | 1 | sys_clk | Interrupt request |

---

## 10. Timing Parameters

### 10.1 Frame Timing

| Parameter | Value | Description |
|-----------|-------|-------------|
| Preamble | 7 bytes (56 ns) | 0x55 pattern |
| SFD | 1 byte (8 ns) | 0xD5 |
| Minimum frame | 64 bytes (512 ns) | Excluding preamble/SFD |
| Maximum frame | 1518 bytes (12.144 µs) | Standard Ethernet |
| FCS | 4 bytes (32 ns) | CRC-32 |
| IFG | 12 bytes (96 ns) | Inter-frame gap |

### 10.2 Latency

| Path | Latency | Description |
|------|---------|-------------|
| TX FIFO | 2-4 gtx_clk | Write to read latency |
| TX Frame Start | 8 gtx_clk | FIFO to GMII (preamble) |
| RX FIFO | 2-4 sys_clk | Write to read latency |
| Interrupt | 3 sys_clk | Event to IRQ assertion |

### 10.3 Throughput

| Metric | Value |
|--------|-------|
| Line rate | 1000 Mbps |
| Maximum frame rate | 1.488 Mpps (64-byte frames) |
| Maximum throughput | 976.56 Mbps (1518-byte frames) |

---

## 11. Configuration Parameters

### 11.1 Synthesis Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| AXI_ADDR_WIDTH | 8 | 8-12 | AXI address width |
| AXI_DATA_WIDTH | 32 | 32 | AXI data width (fixed) |
| TX_FIFO_DEPTH | 8 | 4-12 | TX FIFO depth (log2) |
| RX_FIFO_DEPTH | 8 | 4-12 | RX FIFO depth (log2) |
| MIN_FRAME_SIZE | 64 | 64 | Minimum frame size (fixed) |
| MAX_FRAME_SIZE | 1518 | 1518-9000 | Maximum frame size |
| IFG_BYTES | 12 | 8-12 | Inter-frame gap bytes |
| VERSION | 0x00010000 | - | IP version number |

### 11.2 FIFO Sizing Guidelines

| Frame Size | Recommended TX FIFO | Recommended RX FIFO |
|------------|---------------------|---------------------|
| 64-256 bytes | 2^8 = 256 entries | 2^8 = 256 entries |
| 257-1024 bytes | 2^10 = 1024 entries | 2^10 = 1024 entries |
| 1025-1518 bytes | 2^11 = 2048 entries | 2^11 = 2048 entries |
| Jumbo frames | 2^12 = 4096 entries | 2^12 = 4096 entries |

---

*End of Document*
