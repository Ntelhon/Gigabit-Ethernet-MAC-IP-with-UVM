# DMA Integration Guide

**Document Version:** 1.0  
**Date:** January 2026

---

## Table of Contents

1. [Integration Overview](#1-integration-overview)
2. [Step-by-Step Integration](#2-step-by-step-integration)
3. [Address Mapping](#3-address-mapping)
4. [Memory Requirements](#4-memory-requirements)
5. [Software Initialization](#5-software-initialization)
6. [Parameter Configuration](#6-parameter-configuration)
7. [Timing Constraints](#7-timing-constraints)
8. [Verification Checklist](#8-verification-checklist)

---

## 1. Integration Overview

### 1.1 Integration Checklist

- [ ] Choose integration mode (DMA enabled vs bypassed)
- [ ] Allocate address space for MAC and DMA registers
- [ ] Allocate memory for descriptor rings
- [ ] Configure parameters (ring depth, burst length, address widths)
- [ ] Connect AXI interfaces to system bus
- [ ] Route clock and reset signals
- [ ] Connect interrupts to interrupt controller
- [ ] Create timing constraints
- [ ] Verify connectivity with simulation

---

## 2. Step-by-Step Integration

### 2.1 Choose Integration Mode

#### Option A: Full DMA Mode (Embedded Systems)

```verilog
eth_controller_top #(
    .DMA_ENABLE         (1),              // Enable DMA
    .M_AXI_ADDR_WIDTH   (32),             // 32-bit addressing
    .M_AXI_DATA_WIDTH   (64),             // 64-bit data bus
    .M_AXI_MAX_BURST    (16),             // Max 16-beat bursts
    .DESC_ADDR_WIDTH    (32),             // 32-bit descriptor addresses
    .DESC_RING_DEPTH    (8)               // 2^8 = 256 descriptors
) u_eth_ctrl (
    // All interfaces connected
    ...
);
```

**Use Case**: ARM Cortex-A/R, RISC-V, Microcontrollers with DDR/SRAM

#### Option B: MAC-Only Mode (FPGA)

```verilog
eth_controller_top #(
    .DMA_ENABLE         (0)               // Disable DMA
) u_eth_ctrl (
    // Only MAC and user streaming interfaces
    ...
);
```

**Use Case**: FPGA packet processing, custom datapaths, streaming applications

### 2.2 Connect Clocks and Resets

```verilog
// Clock connections
.sys_clk        (axi_clk),          // AXI bus clock (50-250 MHz)
.gtx_clk        (eth_gtx_clk),      // GMII TX clock (125 MHz)
.rx_clk         (gmii_rx_clk),      // GMII RX clock from PHY (125 MHz)

// Reset connections
.sys_rst_n      (axi_rst_n),        // Synchronous to sys_clk
.gtx_rst_n      (gtx_rst_n),        // Synchronous to gtx_clk
.rx_rst_n       (rx_rst_n)          // Synchronous to rx_clk
```

**Important**: Ensure resets are properly synchronized to their respective clock domains.

### 2.3 Connect AXI4-Lite Interfaces

```verilog
// MAC register interface
.s_axi_mac_awaddr   (axi_mac_awaddr),
.s_axi_mac_awvalid  (axi_mac_awvalid),
.s_axi_mac_awready  (axi_mac_awready),
// ... (all MAC AXI-Lite signals)

// DMA register interface (only if DMA_ENABLE=1)
.s_axi_dma_awaddr   (axi_dma_awaddr),
.s_axi_dma_awvalid  (axi_dma_awvalid),
.s_axi_dma_awready  (axi_dma_awready),
// ... (all DMA AXI-Lite signals)
```

### 2.4 Connect AXI4 Memory Interface

**Only required if DMA_ENABLE=1**

```verilog
// Write address channel
.m_axi_mem_awid     (mem_awid),
.m_axi_mem_awaddr   (mem_awaddr),
.m_axi_mem_awlen    (mem_awlen),
.m_axi_mem_awsize   (mem_awsize),
.m_axi_mem_awburst  (mem_awburst),
.m_axi_mem_awvalid  (mem_awvalid),
.m_axi_mem_awready  (mem_awready),

// Write data channel
.m_axi_mem_wdata    (mem_wdata),
.m_axi_mem_wstrb    (mem_wstrb),
.m_axi_mem_wlast    (mem_wlast),
.m_axi_mem_wvalid   (mem_wvalid),
.m_axi_mem_wready   (mem_wready),

// Write response channel
.m_axi_mem_bid      (mem_bid),
.m_axi_mem_bresp    (mem_bresp),
.m_axi_mem_bvalid   (mem_bvalid),
.m_axi_mem_bready   (mem_bready),

// Read address channel
.m_axi_mem_arid     (mem_arid),
.m_axi_mem_araddr   (mem_araddr),
.m_axi_mem_arlen    (mem_arlen),
.m_axi_mem_arsize   (mem_arsize),
.m_axi_mem_arburst  (mem_arburst),
.m_axi_mem_arvalid  (mem_arvalid),
.m_axi_mem_arready  (mem_arready),

// Read data channel
.m_axi_mem_rid      (mem_rid),
.m_axi_mem_rdata    (mem_rdata),
.m_axi_mem_rresp    (mem_rresp),
.m_axi_mem_rlast    (mem_rlast),
.m_axi_mem_rvalid   (mem_rvalid),
.m_axi_mem_rready   (mem_rready)
```

### 2.5 Connect User Streaming Interfaces

**Only used if DMA_ENABLE=0**

```verilog
// TX path (from user logic to MAC)
.s_axis_user_tx_tdata   (user_tx_tdata),
.s_axis_user_tx_tvalid  (user_tx_tvalid),
.s_axis_user_tx_tlast   (user_tx_tlast),
.s_axis_user_tx_tuser   (user_tx_tuser),   // SOF
.s_axis_user_tx_tready  (user_tx_tready),

// RX path (from MAC to user logic)
.m_axis_user_rx_tdata   (user_rx_tdata),
.m_axis_user_rx_tvalid  (user_rx_tvalid),
.m_axis_user_rx_tlast   (user_rx_tlast),
.m_axis_user_rx_tuser   (user_rx_tuser),   // {frame_bad, frame_good}
.m_axis_user_rx_tready  (user_rx_tready)
```

### 2.6 Connect GMII Interface

```verilog
// TX (to PHY)
.gmii_txd       (phy_gmii_txd),
.gmii_tx_en     (phy_gmii_tx_en),
.gmii_tx_er     (phy_gmii_tx_er),

// RX (from PHY)
.gmii_rxd       (phy_gmii_rxd),
.gmii_rx_dv     (phy_gmii_rx_dv),
.gmii_rx_er     (phy_gmii_rx_er),

// Status (optional)
.gmii_col       (phy_gmii_col),
.gmii_crs       (phy_gmii_crs)
```

### 2.7 Connect Interrupts

```verilog
// MAC interrupt
.irq_mac            (eth_mac_irq),

// DMA interrupts (only if DMA_ENABLE=1)
.irq_dma_tx_done    (eth_dma_tx_done_irq),
.irq_dma_rx_done    (eth_dma_rx_done_irq),
.irq_dma_tx_error   (eth_dma_tx_error_irq),
.irq_dma_rx_error   (eth_dma_rx_error_irq),
.irq_dma_combined   (eth_dma_combined_irq)
```

**Interrupt Controller Connection**:
```verilog
// Option 1: Use combined interrupt
assign irq_vector[ETH_IRQ_NUM]     = eth_mac_irq;
assign irq_vector[ETH_DMA_IRQ_NUM] = eth_dma_combined_irq;

// Option 2: Use separate interrupts
assign irq_vector[ETH_MAC_IRQ]       = eth_mac_irq;
assign irq_vector[ETH_TX_DONE_IRQ]   = eth_dma_tx_done_irq;
assign irq_vector[ETH_RX_DONE_IRQ]   = eth_dma_rx_done_irq;
assign irq_vector[ETH_TX_ERROR_IRQ]  = eth_dma_tx_error_irq;
assign irq_vector[ETH_RX_ERROR_IRQ]  = eth_dma_rx_error_irq;
```

---

## 3. Address Mapping

### 3.1 Register Address Space

Allocate two separate address ranges:

```
System Memory Map:
┌────────────────────────────────────┐
│  0x4000_0000 - 0x4000_00FF         │  MAC Registers (256 bytes)
│  ├─ 0x00: MAC_ADDR_LO              │
│  ├─ 0x04: MAC_ADDR_HI              │
│  ├─ 0x08: CONTROL                  │
│  ├─ 0x0C: STATUS                   │
│  ├─ 0x10: INT_STATUS               │
│  └─ ...                            │
├────────────────────────────────────┤
│  0x4000_1000 - 0x4000_10FF         │  DMA Registers (256 bytes)
│  ├─ 0x00: DMA_CONTROL              │
│  ├─ 0x08: TX_DESC_BASE_LO          │
│  ├─ 0x14: RX_DESC_BASE_LO          │
│  ├─ 0x20: INT_STATUS               │
│  └─ ...                            │
└────────────────────────────────────┘
```

**C/C++ Definitions**:
```c
#define ETH_MAC_BASE    0x40000000
#define ETH_DMA_BASE    0x40001000

// MAC registers
#define MAC_ADDR_LO     (ETH_MAC_BASE + 0x00)
#define MAC_CONTROL     (ETH_MAC_BASE + 0x08)

// DMA registers
#define DMA_CONTROL     (ETH_DMA_BASE + 0x00)
#define TX_DESC_BASE_LO (ETH_DMA_BASE + 0x08)
#define RX_DESC_BASE_LO (ETH_DMA_BASE + 0x14)
```

---

## 4. Memory Requirements

### 4.1 Descriptor Memory

Each descriptor is **16 bytes (128 bits)**.

**TX Descriptor Ring**:
```
Ring Size (log2) | Number of Descriptors | Memory Required
-----------------|----------------------|------------------
6                | 64                   | 1 KB
7                | 128                  | 2 KB
8                | 256                  | 4 KB
9                | 512                  | 8 KB
10               | 1024                 | 16 KB
```

**RX Descriptor Ring**:
```
Ring Size (log2) | Number of Descriptors | Memory Required
-----------------|----------------------|------------------
6                | 64                   | 1 KB
7                | 128                  | 2 KB
8                | 256                  | 4 KB
9                | 512                  | 8 KB
10               | 1024                 | 16 KB
```

**Typical Configuration**:
- TX Ring: 256 descriptors (4 KB)
- RX Ring: 256 descriptors (4 KB)
- **Total: 8 KB**

### 4.2 Packet Buffer Memory

Each descriptor points to a packet buffer in memory.

**TX Buffers**:
```
Number of Buffers | Buffer Size | Total Memory
------------------|-------------|---------------
256               | 1536 bytes  | 384 KB
256               | 2048 bytes  | 512 KB
```

**RX Buffers**:
```
Number of Buffers | Buffer Size | Total Memory
------------------|-------------|---------------
256               | 1536 bytes  | 384 KB
256               | 2048 bytes  | 512 KB
```

**Typical Configuration**:
- 256 TX buffers × 2 KB = 512 KB
- 256 RX buffers × 2 KB = 512 KB
- **Total: 1 MB**

### 4.3 Total Memory Budget

```
Component           | Memory Required
--------------------|------------------
TX Descriptor Ring  | 4 KB
RX Descriptor Ring  | 4 KB
TX Packet Buffers   | 512 KB
RX Packet Buffers   | 512 KB
--------------------|------------------
Total               | ~1 MB
```

**Alignment Requirements**:
- Descriptor rings: 16-byte aligned (recommended: 4 KB page alignment)
- Packet buffers: 8-byte aligned

---

## 5. Software Initialization

### 5.1 Initialization Sequence

```c
void eth_controller_init(void) {
    // 1. Software reset
    write_reg(DMA_CONTROL, DMA_RESET);
    while (read_reg(DMA_CONTROL) & DMA_RESET);  // Wait for self-clear
    
    // 2. Configure MAC address
    write_reg(MAC_ADDR_LO, 0xAABBCCDD);
    write_reg(MAC_ADDR_HI, 0x00001122);
    
    // 3. Allocate and initialize descriptor rings
    tx_desc_ring = dma_alloc_coherent(4096);  // 256 descriptors
    rx_desc_ring = dma_alloc_coherent(4096);
    
    init_tx_descriptors(tx_desc_ring, 256);
    init_rx_descriptors(rx_desc_ring, 256);
    
    // 4. Program descriptor base addresses
    write_reg(TX_DESC_BASE_LO, (uint32_t)tx_desc_ring);
    write_reg(TX_DESC_BASE_HI, (uint32_t)(tx_desc_ring >> 32));
    write_reg(TX_DESC_RING_SIZE, 8);  // log2(256) = 8
    
    write_reg(RX_DESC_BASE_LO, (uint32_t)rx_desc_ring);
    write_reg(RX_DESC_BASE_HI, (uint32_t)(rx_desc_ring >> 32));
    write_reg(RX_DESC_RING_SIZE, 8);
    
    // 5. Enable interrupts
    write_reg(INT_MASK, INT_TX_DONE | INT_RX_DONE | INT_TX_ERROR | INT_RX_ERROR);
    
    // 6. Enable MAC TX/RX
    write_reg(MAC_CONTROL, MAC_TX_ENABLE | MAC_RX_ENABLE);
    
    // 7. Enable DMA TX/RX
    write_reg(DMA_CONTROL, DMA_TX_ENABLE | DMA_RX_ENABLE);
}
```

### 5.2 TX Descriptor Initialization

```c
void init_tx_descriptors(struct eth_tx_desc *ring, int count) {
    for (int i = 0; i < count; i++) {
        ring[i].buffer_addr = 0;           // Will be set when sending
        ring[i].buffer_len  = 0;
        ring[i].control     = 0;           // OWN=0 (CPU owns)
        ring[i].status      = 0;
    }
}
```

### 5.3 RX Descriptor Initialization

```c
void init_rx_descriptors(struct eth_rx_desc *ring, int count) {
    for (int i = 0; i < count; i++) {
        void *buf = dma_alloc_coherent(2048);  // Allocate RX buffer
        
        ring[i].buffer_addr = (uint64_t)buf;
        ring[i].buffer_len  = 2048;
        ring[i].control     = DESC_OWN | DESC_INT_EN;  // DMA owns, interrupt enabled
        if (i == count - 1) {
            ring[i].control |= DESC_WRAP;      // Last descriptor wraps
        }
        ring[i].status = 0;
    }
}
```

### 5.4 Packet Transmission

```c
int eth_send_packet(uint8_t *data, uint16_t len) {
    // 1. Get next TX descriptor
    struct eth_tx_desc *desc = &tx_ring[tx_index];
    
    // 2. Check if descriptor is free (OWN=0)
    if (desc->control & DESC_OWN) {
        return -EBUSY;  // Descriptor still owned by DMA
    }
    
    // 3. Copy packet to TX buffer (or use zero-copy with DMA)
    memcpy(tx_buffers[tx_index], data, len);
    dma_sync_for_device(tx_buffers[tx_index], len);
    
    // 4. Setup descriptor
    desc->buffer_addr = tx_buffer_phys[tx_index];
    desc->buffer_len  = len;
    desc->control     = DESC_OWN | DESC_LAST | DESC_INT_EN;
    
    // 5. Increment index
    tx_index = (tx_index + 1) % TX_RING_SIZE;
    
    return 0;
}
```

### 5.5 Packet Reception

```c
void eth_rx_interrupt_handler(void) {
    while (1) {
        struct eth_rx_desc *desc = &rx_ring[rx_index];
        
        // Check if packet available (OWN=0, DONE=1)
        if ((desc->control & DESC_OWN) || !(desc->status & DESC_DONE)) {
            break;  // No more packets
        }
        
        // Check for errors
        if (desc->status & DESC_ERR) {
            // Handle error
            goto next_packet;
        }
        
        // Get packet length
        uint16_t len = (desc->status >> 16) & 0x1FFF;  // actual_len field
        
        // Process packet
        void *buf = (void *)(uintptr_t)desc->buffer_addr;
        dma_sync_for_cpu(buf, len);
        process_packet(buf, len);
        
next_packet:
        // Give descriptor back to DMA
        desc->control = DESC_OWN | DESC_INT_EN;
        if (rx_index == RX_RING_SIZE - 1) {
            desc->control |= DESC_WRAP;
        }
        desc->status = 0;
        
        rx_index = (rx_index + 1) % RX_RING_SIZE;
    }
    
    // Clear interrupt
    write_reg(INT_STATUS, INT_RX_DONE);
}
```

---

## 6. Parameter Configuration

### 6.1 Recommended Parameters by Use Case

#### Embedded Linux (ARM Cortex-A)
```verilog
.DMA_ENABLE         (1),
.M_AXI_ADDR_WIDTH   (32),
.M_AXI_DATA_WIDTH   (64),
.M_AXI_MAX_BURST    (16),
.DESC_RING_DEPTH    (8),        // 256 descriptors
.BUF_SIZE_WIDTH     (14)        // 16 KB max buffer
```

#### RTOS (ARM Cortex-R/M)
```verilog
.DMA_ENABLE         (1),
.M_AXI_ADDR_WIDTH   (32),
.M_AXI_DATA_WIDTH   (32),       // Smaller data bus
.M_AXI_MAX_BURST    (8),        // Smaller bursts
.DESC_RING_DEPTH    (6),        // 64 descriptors
.BUF_SIZE_WIDTH     (12)        // 4 KB max buffer
```

#### FPGA Streaming
```verilog
.DMA_ENABLE         (0)         // No DMA
```

---

## 7. Timing Constraints

### 7.1 SDC Constraints

```tcl
# Clock definitions
create_clock -name sys_clk -period 10.0 [get_ports sys_clk]  # 100 MHz
create_clock -name gtx_clk -period 8.0  [get_ports gtx_clk]  # 125 MHz
create_clock -name rx_clk  -period 8.0  [get_ports rx_clk]   # 125 MHz

# Clock groups (asynchronous)
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks gtx_clk] \
    -group [get_clocks rx_clk]

# Input delays (example for AXI interface)
set_input_delay -clock sys_clk -max 2.0 [get_ports s_axi_*]
set_input_delay -clock sys_clk -min 0.5 [get_ports s_axi_*]

# Output delays
set_output_delay -clock sys_clk -max 2.0 [get_ports m_axi_*]
set_output_delay -clock sys_clk -min 0.5 [get_ports m_axi_*]

# GMII interface timing
set_input_delay  -clock rx_clk -max 1.0 [get_ports gmii_rxd*]
set_output_delay -clock gtx_clk -max 1.0 [get_ports gmii_txd*]

# False paths
set_false_path -from [get_ports sys_rst_n]
set_false_path -from [get_ports gtx_rst_n]
set_false_path -from [get_ports rx_rst_n]
```

---

## 8. Verification Checklist

### 8.1 Simulation Verification

- [ ] Basic MAC TX/RX without DMA (DMA_ENABLE=0)
- [ ] DMA TX single packet
- [ ] DMA RX single packet
- [ ] DMA TX multiple packets (descriptor ring wrap)
- [ ] DMA RX multiple packets (descriptor ring wrap)
- [ ] Interrupt generation (TX done, RX done)
- [ ] Error handling (AXI errors, buffer overflow)
- [ ] MAC-only mode (DMA bypassed)
- [ ] AXI4 protocol compliance (using VIP)
- [ ] Clock domain crossing (CDC verification)

### 8.2 Hardware Verification

- [ ] Register read/write access (MAC and DMA)
- [ ] Loopback test (TX → PHY → RX)
- [ ] Packet transmission with DMA
- [ ] Packet reception with DMA
- [ ] Interrupt functionality
- [ ] Performance test (throughput, latency)
- [ ] Stress test (continuous traffic)
- [ ] Error injection (CRC errors, runt frames)

### 8.3 Software Verification

- [ ] Driver initialization
- [ ] Descriptor ring management
- [ ] Packet send/receive
- [ ] Interrupt handling
- [ ] Error recovery
- [ ] Performance benchmarking
