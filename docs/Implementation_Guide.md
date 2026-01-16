# Gigabit Ethernet MAC IP - Implementation Guide

**Document Version:** 1.0  
**IP Version:** 1.0.0  
**Date:** January 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Technology Independence](#2-technology-independence)
3. [Memory Implementation](#3-memory-implementation)
4. [Clock Implementation](#4-clock-implementation)
5. [Reset Implementation](#5-reset-implementation)
6. [I/O Implementation](#6-io-implementation)
7. [Power Considerations](#7-power-considerations)
8. [Synthesis Guidelines](#8-synthesis-guidelines)
9. [Physical Implementation](#9-physical-implementation)
10. [Design For Test](#10-design-for-test)
11. [Sign-Off Checklist](#11-sign-off-checklist)

---

## 1. Overview

This document provides guidance for ASIC implementation of the Gigabit Ethernet MAC IP. The IP is delivered as technology-independent RTL. Certain components require technology-specific replacements for optimal area, power, and timing.

### Implementation Scope

The implementation engineer must:
- Replace inferred memories with foundry SRAM macros.
- Insert clock gating cells from the target library.
- Map I/O cells to the target I/O library.
- Apply technology-specific constraints.
- Perform physical implementation and sign-off.

### Technology Requirements

| Parameter | Minimum Requirement |
|-----------|---------------------|
| Process node | 180nm or finer |
| Standard cell library | Timing-characterized |
| SRAM compiler | Dual-port SRAM available |
| I/O library | LVCMOS33 or compatible |

---

## 2. Technology Independence

### 2.1 Technology-Independent Components

The following components use standard RTL constructs:

| Component | RTL Construct | Notes |
|-----------|---------------|-------|
| State machines | Flip-flops, combinational logic | Standard synthesis |
| Counters | Flip-flops | Standard synthesis |
| Control logic | Gates, muxes | Standard synthesis |
| CRC calculator | XOR trees | Parallel implementation |
| Gray coders | XOR gates | Single-bit change logic |
| Synchronizers | Flip-flop chains | CDC elements |

### 2.2 Technology-Dependent Components

The following components require technology-specific implementation:

| Component | Inference | Replacement Required |
|-----------|-----------|---------------------|
| TX FIFO RAM | Dual-port RAM | Foundry SRAM |
| RX FIFO RAM | Dual-port RAM | Foundry SRAM |
| Clock gating | Latch + AND | ICG cells |
| Reset synchronizers | Flip-flops | Async reset FFs |
| I/O buffers | Generic | I/O library cells |

---

## 3. Memory Implementation

### 3.1 FIFO Memory Specifications

**TX FIFO Memory:**

| Parameter | Value |
|-----------|-------|
| Type | Dual-port SRAM |
| Width | 10 bits |
| Depth | 256 entries (default) |
| Total size | 2560 bits (320 bytes) |
| Write port | sys_clk domain |
| Read port | gtx_clk domain |
| Access | Asynchronous (different clocks) |

**RX FIFO Memory:**

| Parameter | Value |
|-----------|-------|
| Type | Dual-port SRAM |
| Width | 12 bits |
| Depth | 256 entries (default) |
| Total size | 3072 bits (384 bytes) |
| Write port | rx_clk domain |
| Read port | sys_clk domain |
| Access | Asynchronous (different clocks) |

### 3.2 SRAM Requirements

| Requirement | Specification |
|-------------|---------------|
| Port configuration | True dual-port or 1R1W |
| Write enable | Byte-level or word-level |
| Read enable | Required |
| Output register | Optional (timing dependent) |
| BIST | Recommended |
| Repair | Optional |

### 3.3 SRAM Replacement Procedure

**Step 1: Generate SRAM Macros**

Use the foundry SRAM compiler to generate:
- TX FIFO: 256x10 dual-port SRAM
- RX FIFO: 256x12 dual-port SRAM

**Step 2: Create Wrapper Module**

Create a wrapper to match the RTL interface:

```verilog
// Example SRAM wrapper for TX FIFO
module tx_fifo_sram_wrapper (
    // Write port
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [7:0]  wr_addr,
    input  wire [9:0]  wr_data,
    
    // Read port
    input  wire        rd_clk,
    input  wire        rd_en,
    input  wire [7:0]  rd_addr,
    output wire [9:0]  rd_data
);

    // Foundry SRAM instantiation
    SRAM_DP_256X10 u_sram (
        // Write port
        .CLKA   (wr_clk),
        .CENA   (~wr_en),
        .WENA   (~wr_en),
        .AA     (wr_addr),
        .DA     (wr_data),
        .QA     (),           // Not used for write
        
        // Read port
        .CLKB   (rd_clk),
        .CENB   (~rd_en),
        .WENB   (1'b1),       // Read only
        .AB     (rd_addr),
        .DB     (10'b0),
        .QB     (rd_data)
    );

endmodule
```

**Step 3: Replace Inferred Memory**

Modify `mac_cdc_fifo.v` to instantiate the wrapper:

```verilog
// Original (inferred):
// reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

// Replacement (SRAM macro):
`ifdef ASIC_IMPLEMENTATION
    fifo_sram_wrapper u_mem (
        .wr_clk  (wr_clk),
        .wr_en   (wr_en && !wr_full),
        .wr_addr (wr_ptr_bin[ADDR_WIDTH-1:0]),
        .wr_data (wr_data),
        .rd_clk  (rd_clk),
        .rd_en   (rd_en && !rd_empty),
        .rd_addr (rd_ptr_bin[ADDR_WIDTH-1:0]),
        .rd_data (rd_data)
    );
`else
    // Inferred RAM for simulation
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    // ... existing code ...
`endif
```

### 3.4 Memory Timing Considerations

| Path | Requirement |
|------|-------------|
| Write setup | wr_data stable before wr_clk rising |
| Write hold | wr_data stable after wr_clk rising |
| Read latency | rd_data valid 1 cycle after rd_en |
| Clock-to-Q | Per SRAM datasheet |

### 3.5 Memory Power

| Mode | Description |
|------|-------------|
| Active | Normal read/write operation |
| Standby | Clock gated, data retained |
| Sleep | Optional low-power mode |

---

## 4. Clock Implementation

### 4.1 Clock Tree Requirements

| Clock | Frequency | Skew Target | Notes |
|-------|-----------|-------------|-------|
| sys_clk | 100 MHz | < 100 ps | System clock tree |
| gtx_clk | 125 MHz | < 80 ps | TX clock tree |
| rx_clk | 125 MHz | < 80 ps | RX clock tree (from PHY) |

### 4.2 Clock Gating

The IP uses implicit clock gating through enable signals. For ASIC implementation, insert Integrated Clock Gating (ICG) cells.

**Clock Gating Candidates:**

| Module | Signal | Condition |
|--------|--------|-----------|
| mac_tx | State machine | tx_enable == 0 |
| mac_rx | State machine | rx_enable == 0 |
| TX FIFO | Write logic | tx_axis_tvalid == 0 |
| RX FIFO | Read logic | rx_axis_tready == 0 |

**ICG Cell Insertion:**

```verilog
// Before (RTL):
always @(posedge clk) begin
    if (enable)
        data <= next_data;
end

// After (with ICG):
wire gated_clk;

ICG u_icg (
    .CK     (clk),
    .E      (enable),
    .ECK    (gated_clk)
);

always @(posedge gated_clk) begin
    data <= next_data;
end
```

**Synthesis Directive:**

```tcl
# Enable automatic clock gating insertion
set_clock_gating_style -sequential_cell latch \
    -minimum_bitwidth 4 \
    -control_point before \
    -control_signal scan_enable
```

### 4.3 Clock Domain Crossing

| Crossing | Source | Destination | Method |
|----------|--------|-------------|--------|
| tx_enable | sys_clk | gtx_clk | 3-stage sync |
| rx_enable | sys_clk | rx_clk | 3-stage sync |
| FIFO pointers | wr_clk | rd_clk | Gray code + 2-stage sync |
| Interrupts | gtx_clk/rx_clk | sys_clk | Pulse sync |

**Synchronizer Implementation:**

Use foundry-provided synchronizer cells if available:

```verilog
// Foundry synchronizer cell (example)
SYNC2_POSEDGE u_sync (
    .D      (async_signal),
    .CK     (dest_clk),
    .Q      (sync_signal)
);
```

---

## 5. Reset Implementation

### 5.1 Reset Architecture

| Reset | Domain | Type | Source |
|-------|--------|------|--------|
| sys_rst_n | sys_clk | Async assert, sync deassert | External |
| gtx_rst_n | gtx_clk | Async assert, sync deassert | Derived |
| rx_rst_n | rx_clk | Async assert, sync deassert | Derived |

### 5.2 Reset Synchronizer

Replace RTL synchronizers with foundry reset synchronizer cells:

```verilog
// Foundry reset synchronizer (example)
RESET_SYNC u_rst_sync (
    .CLK        (gtx_clk),
    .RST_IN_N   (sys_rst_n),
    .RST_OUT_N  (gtx_rst_n)
);
```

**Characteristics:**
- Asynchronous assertion (immediate)
- Synchronous deassertion (on clock edge)
- Metastability-hardened

### 5.3 Reset Tree

```
sys_rst_n (external)
    │
    ├──► sys_clk domain (direct)
    │
    ├──► RESET_SYNC ──► gtx_rst_n (gtx_clk domain)
    │
    └──► RESET_SYNC ──► rx_rst_n (rx_clk domain)
```

### 5.4 Reset Constraints

```tcl
# Define reset as asynchronous
set_ideal_network [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]

# Reset recovery and removal timing
set_max_delay -from [get_ports sys_rst_n] \
    -to [get_cells */u_rst_sync/*] 2.0
```

---

## 6. I/O Implementation

### 6.1 I/O Requirements

| Interface | I/O Standard | Drive Strength | Slew |
|-----------|--------------|----------------|------|
| GMII TX | LVCMOS33 | 8 mA | Fast |
| GMII RX | LVCMOS33 | - | - |
| AXI signals | Core voltage | - | - |
| Clocks | LVCMOS33 | - | - |

### 6.2 I/O Cell Mapping

| Signal | I/O Cell Type | Notes |
|--------|---------------|-------|
| gmii_txd[7:0] | Output buffer | 8 mA drive |
| gmii_tx_en | Output buffer | 8 mA drive |
| gmii_tx_er | Output buffer | 8 mA drive |
| gmii_rxd[7:0] | Input buffer | Schmitt trigger optional |
| gmii_rx_dv | Input buffer | Schmitt trigger optional |
| gmii_rx_er | Input buffer | Schmitt trigger optional |
| gmii_col | Input buffer | Weak pull-down |
| gmii_crs | Input buffer | Weak pull-down |
| gtx_clk | Clock input | PLL or clock buffer |
| rx_clk | Clock input | Clock buffer |

### 6.3 I/O Timing

**Output Timing:**

```tcl
# GMII TX output constraints
set_output_delay -clock gtx_clk -max 6.0 \
    [get_ports {gmii_txd[*] gmii_tx_en gmii_tx_er}]
set_output_delay -clock gtx_clk -min 0.5 \
    [get_ports {gmii_txd[*] gmii_tx_en gmii_tx_er}]
```

**Input Timing:**

```tcl
# GMII RX input constraints  
set_input_delay -clock rx_clk -max 6.0 \
    [get_ports {gmii_rxd[*] gmii_rx_dv gmii_rx_er}]
set_input_delay -clock rx_clk -min 0.5 \
    [get_ports {gmii_rxd[*] gmii_rx_dv gmii_rx_er}]
```

### 6.4 ESD Protection

All I/O pins require ESD protection per foundry guidelines:
- Primary ESD clamp on pad
- Secondary ESD diodes to rails
- CDM protection structures

---

## 7. Power Considerations

### 7.1 Power Domains

| Domain | Voltage | Components |
|--------|---------|------------|
| Core | 1.0V (typical) | Logic, SRAM |
| I/O | 3.3V | GMII buffers |
| PLL | 1.0V | Clock generation |

### 7.2 Power Estimation

| Component | Dynamic Power | Leakage Power |
|-----------|---------------|---------------|
| Logic | ~5 mW @ 125 MHz | ~0.1 mW |
| TX SRAM | ~1 mW @ 125 MHz | ~0.05 mW |
| RX SRAM | ~1 mW @ 125 MHz | ~0.05 mW |
| I/O | ~10 mW @ 1 Gbps | ~0.5 mW |
| **Total** | **~17 mW** | **~0.7 mW** |

*Note: Values are estimates. Actual power depends on technology node and activity.*

### 7.3 Power Reduction Techniques

| Technique | Implementation |
|-----------|----------------|
| Clock gating | ICG cells on idle modules |
| Power gating | Optional for TX/RX paths |
| Multi-Vt | HVT for non-critical paths |
| Operand isolation | Gate inputs to idle units |

### 7.4 Power Intent (UPF)

```tcl
# Power domain definition (example)
create_power_domain PD_MAC -include_scope

# Supply network
create_supply_net VDD -domain PD_MAC
create_supply_net VSS -domain PD_MAC

# Primary power state
add_power_state PD_MAC.primary \
    -supply {VDD 1.0} {VSS 0.0}
```

---

## 8. Synthesis Guidelines

### 8.1 Synthesis Constraints

```tcl
# Clock definitions
create_clock -name sys_clk -period 10.0 [get_ports sys_clk]
create_clock -name gtx_clk -period 8.0 [get_ports gtx_clk]
create_clock -name rx_clk -period 8.0 [get_ports rx_clk]

# Clock uncertainty
set_clock_uncertainty -setup 0.2 [all_clocks]
set_clock_uncertainty -hold 0.1 [all_clocks]

# Clock domain crossings
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks gtx_clk] \
    -group [get_clocks rx_clk]

# False paths for synchronizers
set_false_path -through [get_pins */tx_enable_sync_reg[0]/D]
set_false_path -through [get_pins */rx_enable_sync_reg[0]/D]

# Max delay for CDC paths
set_max_delay -datapath_only \
    -from [get_clocks sys_clk] \
    -to [get_cells */tx_enable_sync_reg[0]] \
    [get_clock_period gtx_clk]
```

### 8.2 Area Optimization

| Directive | Application |
|-----------|-------------|
| `compile_ultra` | Timing-critical paths |
| `set_max_area 0` | Area-constrained regions |
| `group_path -weight` | Balance timing/area |

### 8.3 Timing Optimization

| Path | Strategy |
|------|----------|
| AXI interface | Balance setup/hold |
| GMII output | Meet output delay |
| GMII input | Meet input delay |
| FIFO paths | Relax for CDC |

---

## 9. Physical Implementation

### 9.1 Floorplan Guidelines

```
┌─────────────────────────────────────────────────────┐
│                     I/O Ring                         │
│  ┌──────────────────────────────────────────────┐   │
│  │                                              │   │
│  │   ┌────────┐  ┌────────┐  ┌────────────┐     │   │
│  │   │TX SRAM │  │RX SRAM │  │ Registers  │     │   │
│  │   └────────┘  └────────┘  └────────────┘     │   │
│  │                                              │   │
│  │   ┌──────────────────────────────────────┐   │   │
│  │   │         MAC TX Logic                  │   │   │
│  │   └──────────────────────────────────────┘   │   │
│  │                                              │   │
│  │   ┌──────────────────────────────────────┐   │   │
│  │   │         MAC RX Logic                  │   │   │
│  │   └──────────────────────────────────────┘   │   │
│  │                                              │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 9.2 Placement Guidelines

| Component | Placement |
|-----------|-----------|
| TX SRAM | Near TX logic |
| RX SRAM | Near RX logic |
| TX logic | Near GMII TX I/O |
| RX logic | Near GMII RX I/O |
| Registers | Near AXI I/O |
| Synchronizers | Near destination clock |

### 9.3 Routing Guidelines

| Net Type | Priority | Layer |
|----------|----------|-------|
| Clock | Highest | Upper metals |
| Reset | High | Upper metals |
| Data | Medium | Any |
| Control | Medium | Any |

### 9.4 DRC/LVS Considerations

| Check | Notes |
|-------|-------|
| Antenna rules | Protect SRAM inputs |
| Electromigration | Size clock/reset buffers |
| IR drop | Adequate power straps |
| Via density | Meet via rules |

---

## 10. Design For Test

### 10.1 Scan Insertion

| Requirement | Specification |
|-------------|---------------|
| Scan style | Muxed-D scan |
| Scan chains | 2-4 chains recommended |
| Scan enable | Dedicated port or reuse |
| Lockup latches | At clock domain boundaries |

### 10.2 Scan Exclusions

| Element | Reason |
|---------|--------|
| Synchronizer FFs | Functional requirement |
| SRAM arrays | Separate BIST |
| Clock gating latches | Separate test mode |

### 10.3 Memory BIST

| Memory | BIST Type | Coverage |
|--------|-----------|----------|
| TX FIFO SRAM | March C- | Stuck-at, transition |
| RX FIFO SRAM | March C- | Stuck-at, transition |

**BIST Integration:**

```verilog
// BIST wrapper signals
input  wire        bist_mode,
input  wire        bist_clk,
input  wire        bist_reset,
output wire        bist_done,
output wire        bist_fail
```

### 10.4 JTAG Integration

| Signal | Description |
|--------|-------------|
| TDI | Test data input |
| TDO | Test data output |
| TCK | Test clock |
| TMS | Test mode select |
| TRST_N | Test reset |

### 10.5 Test Modes

| Mode | Description |
|------|-------------|
| Functional | Normal operation |
| Scan | Scan chain testing |
| BIST | Memory self-test |
| JTAG | Boundary scan |
| Bypass | IP bypass for system test |

---

## 11. Sign-Off Checklist

### 11.1 Pre-Tapeout Verification

| Check | Tool | Status |
|-------|------|--------|
| Formal equivalence | Formality/Conformal | ☐ |
| Timing analysis | PrimeTime/Tempus | ☐ |
| Power analysis | PrimePower/Voltus | ☐ |
| CDC verification | SpyGlass/Meridian | ☐ |
| DRC | Calibre/IC Validator | ☐ |
| LVS | Calibre/IC Validator | ☐ |
| Antenna | Calibre/IC Validator | ☐ |
| ERC | Calibre/IC Validator | ☐ |
| IR drop | RedHawk/Voltus | ☐ |
| EM analysis | RedHawk/Voltus | ☐ |

### 11.2 Timing Sign-Off

| Corner | Temperature | Voltage | Analysis |
|--------|-------------|---------|----------|
| SS | 125°C | 0.9V | Setup |
| FF | -40°C | 1.1V | Hold |
| TT | 25°C | 1.0V | Functional |

### 11.3 Documentation Deliverables

| Document | Description |
|----------|-------------|
| Synthesis report | Area, timing, power |
| STA report | Setup/hold analysis |
| Power report | Dynamic and leakage |
| DRC/LVS report | Clean status |
| CDC report | No violations |
| Test coverage | Fault coverage numbers |

### 11.4 Deliverables Checklist

| Deliverable | Format | Status |
|-------------|--------|--------|
| Gate-level netlist | Verilog | ☐ |
| SDF timing | SDF 3.0 | ☐ |
| LEF abstract | LEF | ☐ |
| GDS layout | GDS II | ☐ |
| Liberty timing | LIB | ☐ |
| Scan chains | STIL/WGL | ☐ |
| BIST vectors | STIL/WGL | ☐ |

---

*End of Document*
