# Gigabit Ethernet MAC IP - Integration Guide

**Document Version:** 1.0  
**IP Version:** 1.0.0  
**Date:** January 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Integration Checklist](#2-integration-checklist)
3. [Interface Requirements](#3-interface-requirements)
4. [Clock Integration](#4-clock-integration)
5. [Reset Integration](#5-reset-integration)
6. [AXI4-Lite Integration](#6-axi4-lite-integration)
7. [AXI4-Stream Integration](#7-axi4-stream-integration)
8. [GMII/RGMII Integration](#8-gmiirgmii-integration)
9. [Interrupt Integration](#9-interrupt-integration)
10. [Address Mapping](#10-address-mapping)
11. [Software Considerations](#11-software-considerations)
12. [Example Connections](#12-example-connections)
13. [Verification Recommendations](#13-verification-recommendations)

---

## 1. Overview

This document provides guidance for integrating the Gigabit Ethernet MAC IP into a System-on-Chip (SoC) environment. The IP requires connection to system buses, clock infrastructure, reset controllers, and external PHY devices.

### Integration Scope

The integrator must provide:
- Clock generation for all clock domains.
- Reset synchronization for all reset domains.
- AXI4-Lite master for register access.
- AXI4-Stream interfaces for data transfer.
- GMII or RGMII connection to PHY device.
- Interrupt controller connection.

---

## 2. Integration Checklist

### Pre-Integration

- [ ] Verify IP version compatibility.
- [ ] Review interface specifications.
- [ ] Allocate address space for registers.
- [ ] Allocate interrupt number.
- [ ] Plan clock tree for all domains.
- [ ] Plan reset tree for all domains.

### Clock Integration

- [ ] Generate 125 MHz gtx_clk.
- [ ] Connect rx_clk from PHY.
- [ ] Verify clock jitter specifications.
- [ ] Constrain clock domains in SDC.

### Reset Integration

- [ ] Connect sys_rst_n to system reset.
- [ ] Generate synchronized gtx_rst_n.
- [ ] Generate synchronized rx_rst_n.
- [ ] Verify reset sequencing.

### AXI Integration

- [ ] Connect AXI4-Lite to system bus.
- [ ] Configure address decode.
- [ ] Connect AXI4-Stream TX to DMA or CPU.
- [ ] Connect AXI4-Stream RX to DMA or CPU.

### PHY Integration

- [ ] Connect GMII or RGMII signals.
- [ ] Route timing constraints.
- [ ] Verify I/O standard compatibility.

### Interrupt Integration

- [ ] Connect irq to interrupt controller.
- [ ] Configure interrupt priority.
- [ ] Map interrupt in software.

---

## 3. Interface Requirements

### 3.1 Port Summary

| Interface | Protocol | Direction | Clock Domain |
|-----------|----------|-----------|--------------|
| AXI4-Lite | AMBA 4.0 AXI4-Lite | Slave | sys_clk |
| AXI4-Stream TX | AMBA 4.0 AXI4-Stream | Slave | sys_clk |
| AXI4-Stream RX | AMBA 4.0 AXI4-Stream | Master | sys_clk |
| GMII TX | IEEE 802.3 GMII | Master | gtx_clk |
| GMII RX | IEEE 802.3 GMII | Slave | rx_clk |
| Interrupt | Single wire | Master | sys_clk |

### 3.2 Interface Compatibility

| Interface | Compatible IP/Controllers |
|-----------|---------------------------|
| AXI4-Lite | ARM AXI Interconnect, Xilinx AXI SmartConnect |
| AXI4-Stream | Xilinx AXI DMA, ARM DMA-330 (with adapter) |
| GMII | Standard Ethernet PHY (88E1111, RTL8211, etc.) |

---

## 4. Clock Integration

### 4.1 Required Clocks

| Clock | Frequency | Source | Notes |
|-------|-----------|--------|-------|
| sys_clk | 100 MHz typical | System PLL | Can range 25-250 MHz |
| gtx_clk | 125 MHz | MAC or PHY | ±100 ppm tolerance |
| rx_clk | 125 MHz | PHY device | Recovered from line |

### 4.2 Clock Generation

**sys_clk Generation:**
```
PLL or Clock Generator
    │
    └──► sys_clk (100 MHz)
              │
              └──► mac_top.sys_clk
              └──► AXI Interconnect
              └──► DMA Controller
```

**gtx_clk Generation:**

Option A: MAC-Generated (Recommended)
```
125 MHz Reference
    │
    └──► PLL (125 MHz)
              │
              └──► gtx_clk ──► mac_top.gtx_clk
                          └──► PHY TXC
```

Option B: PHY-Generated
```
PHY Device
    │
    └──► GTX_CLK ──► mac_top.gtx_clk
```

**rx_clk Connection:**
```
PHY Device
    │
    └──► RX_CLK ──► mac_top.rx_clk
```

### 4.3 Clock Constraints (SDC)

```tcl
# System clock
create_clock -name sys_clk -period 10.0 [get_ports sys_clk]

# GMII TX clock
create_clock -name gtx_clk -period 8.0 [get_ports gtx_clk]

# GMII RX clock (from PHY)
create_clock -name rx_clk -period 8.0 [get_ports rx_clk]

# Clock domain crossings - asynchronous
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks gtx_clk] \
    -group [get_clocks rx_clk]
```

### 4.4 Clock Quality Requirements

| Parameter | Requirement |
|-----------|-------------|
| Jitter (peak-to-peak) | < 100 ps |
| Duty cycle | 45% - 55% |
| Rise/fall time | < 1 ns |
| Skew (gtx_clk to PHY) | < 500 ps |

---

## 5. Reset Integration

### 5.1 Reset Signals

| Signal | Clock Domain | Active Level | Source |
|--------|--------------|--------------|--------|
| sys_rst_n | sys_clk | Low | System reset controller |
| gtx_rst_n | gtx_clk | Low | Synchronized from sys_rst_n |
| rx_rst_n | rx_clk | Low | Synchronized from sys_rst_n |

### 5.2 Reset Synchronization

Each reset must be synchronized to its respective clock domain. Use a 2-stage synchronizer:

```verilog
// Example: sys_rst_n to gtx_rst_n synchronization
reg [1:0] gtx_rst_sync;
always @(posedge gtx_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        gtx_rst_sync <= 2'b00;
    else
        gtx_rst_sync <= {gtx_rst_sync[0], 1'b1};
end
assign gtx_rst_n = gtx_rst_sync[1];
```

### 5.3 Reset Sequence

```
Time ────────────────────────────────────────────────────►

sys_rst_n   ─────┐                    ┌─────────────────
                 └────────────────────┘
                 
gtx_rst_n   ─────┐                         ┌────────────
                 └─────────────────────────┘
                      ▲
                      │ 2 gtx_clk cycles after sys_rst_n release
                      
rx_rst_n    ─────┐                              ┌───────
                 └──────────────────────────────┘
                           ▲
                           │ 2 rx_clk cycles after sys_rst_n release
```

### 5.4 Reset Requirements

| Requirement | Specification |
|-------------|---------------|
| Minimum pulse width | 2 clock cycles (per domain) |
| Reset assertion | All resets must be asserted together |
| Reset release | sys_rst_n first, then domain resets |
| Synchronization | Required for each clock domain |

---

## 6. AXI4-Lite Integration

### 6.1 Interface Signals

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| s_axi_awaddr | 8 | Input | Write address |
| s_axi_awvalid | 1 | Input | Write address valid |
| s_axi_awready | 1 | Output | Write address ready |
| s_axi_wdata | 32 | Input | Write data |
| s_axi_wstrb | 4 | Input | Write byte strobes |
| s_axi_wvalid | 1 | Input | Write data valid |
| s_axi_wready | 1 | Output | Write data ready |
| s_axi_bresp | 2 | Output | Write response |
| s_axi_bvalid | 1 | Output | Write response valid |
| s_axi_bready | 1 | Input | Write response ready |
| s_axi_araddr | 8 | Input | Read address |
| s_axi_arvalid | 1 | Input | Read address valid |
| s_axi_arready | 1 | Output | Read address ready |
| s_axi_rdata | 32 | Output | Read data |
| s_axi_rresp | 2 | Output | Read response |
| s_axi_rvalid | 1 | Output | Read data valid |
| s_axi_rready | 1 | Input | Read data ready |

### 6.2 Protocol Requirements

| Parameter | Value |
|-----------|-------|
| Data width | 32 bits (fixed) |
| Address width | 8 bits (configurable) |
| Burst support | Not supported (single transfers only) |
| Exclusive access | Not supported |
| Write strobes | Supported (byte-level) |

### 6.3 Address Decoding

The IP uses lower address bits for register selection. Upper address bits are decoded by the SoC interconnect.

```
SoC Address: 0x4000_0000 - 0x4000_00FF
             ├─────────┬──────────────┤
             │ Base    │ MAC Offset   │
             │ Address │ (8 bits)     │
             └─────────┴──────────────┘

Example:
  MAC_ADDR_LO = 0x4000_0000
  CONTROL     = 0x4000_0008
  VERSION     = 0x4000_0024
```

### 6.4 Interconnect Configuration

| Parameter | Configuration |
|-----------|---------------|
| Slave port | Single AXI4-Lite slave |
| Address range | 256 bytes (0x00 - 0xFF) |
| Data width | 32 bits |
| Clock | sys_clk |
| Reset | sys_rst_n (active low) |

### 6.5 Timing Constraints

| Parameter | Requirement |
|-----------|-------------|
| Write latency | 2-3 sys_clk cycles |
| Read latency | 2-3 sys_clk cycles |
| Outstanding transactions | 1 (AXI4-Lite) |

---

## 7. AXI4-Stream Integration

### 7.1 TX Interface (Slave)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| tx_axis_tdata | 8 | Input | TX data byte |
| tx_axis_tvalid | 1 | Input | TX data valid |
| tx_axis_tready | 1 | Output | TX ready |
| tx_axis_tlast | 1 | Input | End of frame |
| tx_axis_tuser | 1 | Input | Start of frame |

### 7.2 RX Interface (Master)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| rx_axis_tdata | 8 | Output | RX data byte |
| rx_axis_tvalid | 1 | Output | RX data valid |
| rx_axis_tready | 1 | Input | RX ready |
| rx_axis_tlast | 1 | Output | End of frame |
| rx_axis_tuser | 2 | Output | Frame status |

### 7.3 DMA Integration

**Recommended DMA Configuration:**

| Parameter | TX DMA | RX DMA |
|-----------|--------|--------|
| Transfer type | Memory to Stream | Stream to Memory |
| Burst length | 1-256 bytes | 1-256 bytes |
| Data width | 8 bits | 8 bits |
| Descriptor mode | Scatter-gather | Scatter-gather |
| Buffer size | ≥ 1518 bytes | ≥ 1518 bytes |

### 7.4 Frame Format

**TX Frame:**
```
Byte 0:    tdata=DA[0], tvalid=1, tlast=0, tuser=1 (SOF)
Byte 1-5:  tdata=DA[1-5], tvalid=1, tlast=0, tuser=0
Byte 6-11: tdata=SA[0-5], tvalid=1, tlast=0, tuser=0
Byte 12-13: tdata=Type/Len, tvalid=1, tlast=0, tuser=0
Byte 14-N: tdata=Payload, tvalid=1, tlast=0, tuser=0
Byte N:    tdata=Last, tvalid=1, tlast=1 (EOF), tuser=0
```

**RX Frame:**
```
Byte 0:    tdata=DA[0], tvalid=1, tlast=0, tuser=00
Byte 1-5:  tdata=DA[1-5], tvalid=1, tlast=0, tuser=00
Byte 6-11: tdata=SA[0-5], tvalid=1, tlast=0, tuser=00
Byte 12-13: tdata=Type/Len, tvalid=1, tlast=0, tuser=00
Byte 14-N: tdata=Payload, tvalid=1, tlast=0, tuser=00
Byte N:    tdata=Last, tvalid=1, tlast=1, tuser=01 (good) or 10 (bad)
```

### 7.5 Backpressure Handling

The TX interface applies backpressure via tready deassertion when:
- TX FIFO is full.
- TX FIFO has limited space remaining.

The RX interface generates tvalid when:
- RX FIFO contains data.
- Frame data is available for reading.

**Important:** Software must ensure RX data is consumed before FIFO overflow. Configure DMA for continuous operation.

---

## 8. GMII/RGMII Integration

### 8.1 GMII Interface Signals

| Signal | Width | Direction | I/O Standard | Description |
|--------|-------|-----------|--------------|-------------|
| gmii_txd | 8 | Output | LVCMOS33 | TX data |
| gmii_tx_en | 1 | Output | LVCMOS33 | TX enable |
| gmii_tx_er | 1 | Output | LVCMOS33 | TX error |
| gmii_rxd | 8 | Input | LVCMOS33 | RX data |
| gmii_rx_dv | 1 | Input | LVCMOS33 | RX data valid |
| gmii_rx_er | 1 | Input | LVCMOS33 | RX error |
| gmii_col | 1 | Input | LVCMOS33 | Collision |
| gmii_crs | 1 | Input | LVCMOS33 | Carrier sense |

### 8.2 GMII Timing Requirements

**TX Timing (MAC drives, PHY samples):**

| Parameter | Min | Typ | Max | Unit |
|-----------|-----|-----|-----|------|
| TXD/TX_EN setup to TXC rising | 2.0 | - | - | ns |
| TXD/TX_EN hold from TXC rising | 0.5 | - | - | ns |
| TXC to TXD/TX_EN (MAC output) | - | - | 6.0 | ns |

**RX Timing (PHY drives, MAC samples):**

| Parameter | Min | Typ | Max | Unit |
|-----------|-----|-----|-----|------|
| RXD/RX_DV setup to RXC rising | 2.0 | - | - | ns |
| RXD/RX_DV hold from RXC rising | 0.5 | - | - | ns |
| RXC to RXD/RX_DV (PHY output) | - | - | 6.0 | ns |

### 8.3 PHY Connection Diagram

```
                 MAC IP                          PHY Device
            ┌─────────────┐                   ┌─────────────┐
            │             │                   │             │
gtx_clk ────┤ TX Clock    │──── GTX_CLK ─────►│ TX Clock    │
            │             │                   │             │
            │ gmii_txd[7:0]├──── TXD[7:0] ───►│ TX Data     │
            │ gmii_tx_en  ├──── TX_EN ───────►│ TX Enable   │
            │ gmii_tx_er  ├──── TX_ER ───────►│ TX Error    │
            │             │                   │             │
rx_clk ◄────┤ RX Clock    │◄─── RX_CLK ──────│ RX Clock    │
            │             │                   │             │
            │ gmii_rxd[7:0]│◄─── RXD[7:0] ────│ RX Data     │
            │ gmii_rx_dv  │◄─── RX_DV ───────│ RX Valid    │
            │ gmii_rx_er  │◄─── RX_ER ───────│ RX Error    │
            │             │                   │             │
            │ gmii_col    │◄─── COL ─────────│ Collision   │
            │ gmii_crs    │◄─── CRS ─────────│ Carrier     │
            │             │                   │             │
            └─────────────┘                   └─────────────┘
```

### 8.4 RGMII Interface (Optional)

For RGMII PHY connection, use the `rgmii_phy_if` module:

```
mac_top                rgmii_phy_if              PHY
┌───────┐              ┌───────────┐           ┌─────┐
│       ├── GMII TX ──►│           ├── TXD ───►│     │
│       │              │           ├── TX_CTL ►│     │
│       ◄── GMII RX ───┤           │◄── RXD ───│     │
│       │              │           │◄── RX_CTL │     │
└───────┘              └───────────┘           └─────┘
```

### 8.5 I/O Constraints

```tcl
# GMII TX Output Constraints
set_output_delay -clock gtx_clk -max 6.0 [get_ports {gmii_txd[*] gmii_tx_en gmii_tx_er}]
set_output_delay -clock gtx_clk -min 0.0 [get_ports {gmii_txd[*] gmii_tx_en gmii_tx_er}]

# GMII RX Input Constraints
set_input_delay -clock rx_clk -max 6.0 [get_ports {gmii_rxd[*] gmii_rx_dv gmii_rx_er}]
set_input_delay -clock rx_clk -min 0.0 [get_ports {gmii_rxd[*] gmii_rx_dv gmii_rx_er}]
```

---

## 9. Interrupt Integration

### 9.1 Interrupt Signal

| Signal | Width | Direction | Active Level | Clock Domain |
|--------|-------|-----------|--------------|--------------|
| irq | 1 | Output | High | sys_clk |

### 9.2 Interrupt Sources

| Source | Description | Register Bit |
|--------|-------------|--------------|
| TX_COMPLETE | Frame transmitted | INT_STATUS[0] |
| RX_RECEIVED | Frame received | INT_STATUS[1] |
| RX_CRC_ERR | CRC error detected | INT_STATUS[2] |
| RX_RUNT | Runt frame detected | INT_STATUS[3] |

### 9.3 Interrupt Controller Connection

```
MAC IP              Interrupt Controller          CPU
┌───────┐           ┌───────────────────┐        ┌─────┐
│       │           │                   │        │     │
│   irq ├──────────►│ IRQ Input [N]     │        │     │
│       │           │                   │        │     │
│       │           │ IRQ Priority      │──────►│ IRQ │
│       │           │ IRQ Enable        │        │     │
└───────┘           └───────────────────┘        └─────┘
```

### 9.4 Interrupt Handling Flow

1. Hardware asserts irq (rising edge).
2. Interrupt controller signals CPU.
3. CPU reads INT_STATUS register.
4. CPU handles interrupt condition.
5. CPU writes INT_STATUS to clear handled bits.
6. irq deasserts when all unmasked interrupts cleared.

### 9.5 Interrupt Configuration

| Parameter | Recommendation |
|-----------|----------------|
| Trigger type | Level-sensitive (high) |
| Priority | Application-dependent |
| Shared | Not recommended (dedicated IRQ line) |

---

## 10. Address Mapping

### 10.1 Register Address Offsets

| Offset | Register | Access |
|--------|----------|--------|
| 0x00 | MAC_ADDR_LO | RW |
| 0x04 | MAC_ADDR_HI | RW |
| 0x08 | CONTROL | RW |
| 0x0C | STATUS | RO |
| 0x10 | INT_STATUS | RW1C |
| 0x14 | INT_MASK | RW |
| 0x18 | TX_FRAME_CNT | RO |
| 0x1C | RX_FRAME_CNT | RO |
| 0x20 | RX_ERR_CNT | RO |
| 0x24 | VERSION | RO |

### 10.2 Example SoC Address Map

| Base Address | Size | Peripheral |
|--------------|------|------------|
| 0x0000_0000 | 64 KB | Boot ROM |
| 0x1000_0000 | 64 KB | SRAM |
| 0x4000_0000 | 256 B | **Ethernet MAC** |
| 0x4000_1000 | 4 KB | DMA Controller |
| 0x4000_2000 | 4 KB | Interrupt Controller |

### 10.3 Address Space Requirements

| Requirement | Value |
|-------------|-------|
| Minimum allocation | 256 bytes (0x100) |
| Alignment | 256-byte boundary |
| Reserved space | 0x28 - 0xFF |

---

## 11. Software Considerations

### 11.1 Driver Requirements

| Component | Description |
|-----------|-------------|
| Register access | Memory-mapped I/O (32-bit aligned) |
| DMA configuration | TX and RX descriptor rings |
| Interrupt handler | Read INT_STATUS, handle events, clear |
| Buffer management | Pre-allocated frame buffers |

### 11.2 Initialization Sequence

```c
// 1. Reset and verify IP presence
uint32_t version = read_reg(ETH_BASE + VERSION);
if ((version >> 16) != 0x0001) {
    return ERROR_IP_NOT_FOUND;
}

// 2. Configure MAC address
write_reg(ETH_BASE + MAC_ADDR_LO, mac_addr_lo);
write_reg(ETH_BASE + MAC_ADDR_HI, mac_addr_hi);

// 3. Configure interrupts
write_reg(ETH_BASE + INT_MASK, 0x0F);  // Enable all

// 4. Enable TX and RX
write_reg(ETH_BASE + CONTROL, 0x03);   // TX_EN | RX_EN
```

### 11.3 Frame Transmission

```c
// 1. Wait for TX ready (tready high)
while (!tx_fifo_ready());

// 2. Write frame to TX AXI-Stream
// First byte with tuser=1 (SOF)
// Last byte with tlast=1 (EOF)
for (int i = 0; i < frame_len; i++) {
    write_tx_fifo(frame[i], i == 0, i == frame_len - 1);
}

// 3. Wait for TX complete interrupt or poll status
```

### 11.4 Frame Reception

```c
// Interrupt handler
void eth_irq_handler(void) {
    uint32_t status = read_reg(ETH_BASE + INT_STATUS);
    
    if (status & INT_RX_RECEIVED) {
        // Read frame from RX AXI-Stream
        while (rx_fifo_valid()) {
            uint8_t data = read_rx_fifo(&last, &user);
            buffer[idx++] = data;
            if (last) {
                process_frame(buffer, idx, user);
                idx = 0;
            }
        }
    }
    
    // Clear handled interrupts
    write_reg(ETH_BASE + INT_STATUS, status);
}
```

---

## 12. Example Connections

### 12.1 Minimal SoC Integration

```
                    ┌──────────────────────────────────────┐
                    │              SoC                      │
                    │                                       │
    ┌───────┐       │   ┌─────────┐      ┌──────────────┐   │
    │       │       │   │         │      │              │   │
    │  CPU  ├───────┼──►│ AXI     │◄────►│ Ethernet MAC │◄──┼──► PHY
    │       │       │   │ Intercon│      │              │   │
    └───────┘       │   │         │◄────►│              │   │
                    │   └────┬────┘      └──────┬───────┘   │
                    │        │                  │           │
                    │        ▼                  ▼           │
                    │   ┌─────────┐      ┌──────────────┐   │
                    │   │   DMA   │◄────►│ Memory       │   │
                    │   │         │      │              │   │
                    │   └─────────┘      └──────────────┘   │
                    │                                       │
                    └──────────────────────────────────────┘
```

### 12.2 Verilog Instantiation Example

```verilog
mac_top #(
    .AXI_ADDR_WIDTH (8),
    .AXI_DATA_WIDTH (32),
    .TX_FIFO_DEPTH  (8),
    .RX_FIFO_DEPTH  (8),
    .MIN_FRAME_SIZE (64),
    .IFG_BYTES      (12)
) u_ethernet_mac (
    // System clock domain
    .sys_clk        (sys_clk),
    .sys_rst_n      (sys_rst_n),
    
    // TX clock domain
    .gtx_clk        (gtx_clk_125m),
    .gtx_rst_n      (gtx_rst_n),
    
    // RX clock domain
    .rx_clk         (phy_rx_clk),
    .rx_rst_n       (rx_rst_n),
    
    // AXI4-Lite (register interface)
    .s_axi_awaddr   (eth_axi_awaddr),
    .s_axi_awvalid  (eth_axi_awvalid),
    .s_axi_awready  (eth_axi_awready),
    .s_axi_wdata    (eth_axi_wdata),
    .s_axi_wstrb    (eth_axi_wstrb),
    .s_axi_wvalid   (eth_axi_wvalid),
    .s_axi_wready   (eth_axi_wready),
    .s_axi_bresp    (eth_axi_bresp),
    .s_axi_bvalid   (eth_axi_bvalid),
    .s_axi_bready   (eth_axi_bready),
    .s_axi_araddr   (eth_axi_araddr),
    .s_axi_arvalid  (eth_axi_arvalid),
    .s_axi_arready  (eth_axi_arready),
    .s_axi_rdata    (eth_axi_rdata),
    .s_axi_rresp    (eth_axi_rresp),
    .s_axi_rvalid   (eth_axi_rvalid),
    .s_axi_rready   (eth_axi_rready),
    
    // AXI4-Stream TX
    .tx_axis_tdata  (tx_axis_tdata),
    .tx_axis_tvalid (tx_axis_tvalid),
    .tx_axis_tready (tx_axis_tready),
    .tx_axis_tlast  (tx_axis_tlast),
    .tx_axis_tuser  (tx_axis_tuser),
    
    // AXI4-Stream RX
    .rx_axis_tdata  (rx_axis_tdata),
    .rx_axis_tvalid (rx_axis_tvalid),
    .rx_axis_tready (rx_axis_tready),
    .rx_axis_tlast  (rx_axis_tlast),
    .rx_axis_tuser  (rx_axis_tuser),
    
    // GMII interface
    .gmii_txd       (phy_txd),
    .gmii_tx_en     (phy_tx_en),
    .gmii_tx_er     (phy_tx_er),
    .gmii_rxd       (phy_rxd),
    .gmii_rx_dv     (phy_rx_dv),
    .gmii_rx_er     (phy_rx_er),
    .gmii_col       (phy_col),
    .gmii_crs       (phy_crs),
    
    // Interrupt
    .irq            (eth_irq)
);
```

---

## 13. Verification Recommendations

### 13.1 Integration Verification

| Test | Description |
|------|-------------|
| Register access | Read/write all registers via AXI4-Lite |
| Loopback test | TX → PHY loopback → RX path verification |
| Interrupt test | Verify all interrupt sources trigger IRQ |
| Reset test | Verify proper reset behavior |

### 13.2 System-Level Verification

| Test | Description |
|------|-------------|
| DMA integration | Verify DMA can read/write frames |
| Multi-frame test | Send/receive multiple consecutive frames |
| Error injection | Inject CRC errors, verify error handling |
| Stress test | Maximum throughput with minimum frames |

### 13.3 Timing Verification

| Check | Method |
|-------|--------|
| Clock domain crossings | CDC analysis tool |
| GMII timing | Static timing analysis with I/O constraints |
| Reset timing | Verify reset synchronization |

---

*End of Document*
