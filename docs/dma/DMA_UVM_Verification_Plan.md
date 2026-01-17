# DMA UVM Verification Plan

**Document Version:** 1.0  
**Date:** January 2026

---

## Table of Contents

1. [Verification Strategy](#1-verification-strategy)
2. [Existing UVM Infrastructure](#2-existing-uvm-infrastructure)
3. [New UVM Components](#3-new-uvm-components)
4. [Test Plan](#4-test-plan)
5. [Coverage Plan](#5-coverage-plan)
6. [Verification Environment Architecture](#6-verification-environment-architecture)

---

## 1. Verification Strategy

### 1.1 Key Principles

1. **Preserve Existing Tests**: All existing MAC UVM tests must continue to pass
2. **Layered Verification**: 
   - Level 1: DMA modules in isolation
   - Level 2: DMA subsystem integrated with MAC
   - Level 3: Full system with memory model
3. **Incremental Approach**: Add DMA verification without breaking MAC verification
4. **Bypass Testing**: Verify DMA_ENABLE=0 mode thoroughly

### 1.2 Verification Levels

```
Level 1: Module-Level
├── eth_tx_dma (standalone)
├── eth_rx_dma (standalone)
├── eth_dma_desc (standalone)
└── eth_dma_regs (standalone)

Level 2: Subsystem-Level
├── eth_dma_top (DMA_ENABLE=1)
└── eth_dma_top (DMA_ENABLE=0, bypass)

Level 3: System-Level
├── eth_controller_top (MAC + DMA + Memory)
└── eth_controller_top (MAC-only, DMA bypassed)
```

---

## 2. Existing UVM Infrastructure

### 2.1 Current UVM Environment

The existing MAC verification environment includes:

```
verif/
├── agents/
│   ├── axi_stream_agent/      ← Reuse for MAC ↔ DMA
│   ├── axi_lite_agent/        ← Reuse for MAC registers
│   └── gmii_agent/            ← Reuse for PHY interface
├── env/
│   └── mac_env.sv             ← Extend with DMA components
├── scoreboard/
│   └── eth_scoreboard.sv      ← Extend for DMA checking
└── tests/
    └── mac_*_test.sv          ← Keep all existing tests
```

**Critical**: These components remain **unchanged**. DMA verification is additive.

---

## 3. New UVM Components

### 3.1 AXI4 Memory Agent

**Purpose**: Model system memory for DMA transactions

**Location**: `verif/agents/axi4_mem_agent/`

**Files**:
```
axi4_mem_agent_pkg.sv
axi4_mem_agent.sv
axi4_mem_driver.sv
axi4_mem_monitor.sv
axi4_mem_sequencer.sv
axi4_mem_txn.sv
axi4_mem_model.sv          ← Memory storage model
```

**Key Features**:
- **Driver**: Responds to AXI4 read/write transactions
- **Monitor**: Captures all AXI4 transactions for checking
- **Memory Model**: Associative array for descriptor and packet storage
- **Configurable latency**: Simulate DDR access delays

**Transaction Example**:
```systemverilog
class axi4_mem_txn extends uvm_sequence_item;
    rand bit [31:0]   addr;
    rand bit [63:0]   data[];
    rand int          length;
    rand axi4_cmd_e   cmd;      // READ, WRITE
    rand bit [7:0]    strb[];
    bit [1:0]         resp;
    
    constraint c_burst_size {
        length inside {[1:16]};
        data.size() == length;
        strb.size() == length * 8;
    }
endclass
```

### 3.2 DMA Register Agent

**Purpose**: Control DMA via AXI4-Lite

**Location**: `verif/agents/dma_reg_agent/` (or extend existing `axi_lite_agent`)

**Register Abstraction Layer (RAL)**:
```systemverilog
class dma_reg_block extends uvm_reg_block;
    rand uvm_reg dma_control;
    rand uvm_reg tx_desc_base_lo;
    rand uvm_reg tx_desc_base_hi;
    rand uvm_reg tx_desc_ring_size;
    rand uvm_reg rx_desc_base_lo;
    rand uvm_reg rx_desc_base_hi;
    rand uvm_reg rx_desc_ring_size;
    rand uvm_reg int_status;
    rand uvm_reg int_mask;
    // ... status counters
endclass
```

### 3.3 DMA Scoreboard

**Purpose**: Check DMA operation correctness

**Location**: `verif/scoreboard/dma_scoreboard.sv`

**Checks**:
1. **Descriptor Management**:
   - Ownership bit transitions (CPU → DMA → CPU)
   - Descriptor fields written correctly
   - Ring wrap-around behavior
   
2. **Data Integrity**:
   - TX: Memory → DMA → MAC matches
   - RX: MAC → DMA → Memory matches
   - Packet data not corrupted
   
3. **Protocol Compliance**:
   - AXI4 burst transactions valid
   - Descriptor fetch/writeback order correct
   - No out-of-order completions

4. **Error Handling**:
   - AXI errors propagated correctly
   - Buffer overflows detected
   - Invalid descriptors rejected

**Implementation Outline**:
```systemverilog
class dma_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp_mac_tx #(axi_stream_txn, dma_scoreboard) mac_tx_export;
    uvm_analysis_imp_mac_rx #(axi_stream_txn, dma_scoreboard) mac_rx_export;
    uvm_analysis_imp_mem_wr #(axi4_mem_txn, dma_scoreboard)   mem_wr_export;
    uvm_analysis_imp_mem_rd #(axi4_mem_txn, dma_scoreboard)   mem_rd_export;
    uvm_analysis_imp_desc   #(axi4_mem_txn, dma_scoreboard)   desc_export;
    
    // Queues for tracking
    axi_stream_txn tx_pkt_queue[$];
    axi_stream_txn rx_pkt_queue[$];
    
    function void write_mac_tx(axi_stream_txn txn);
        // Check TX packet matches descriptor/memory
        compare_tx_packet(txn);
    endfunction
    
    function void write_mac_rx(axi_stream_txn txn);
        // Check RX packet written to correct memory location
        compare_rx_packet(txn);
    endfunction
    
    function void compare_tx_packet(axi_stream_txn mac_pkt);
        // 1. Find corresponding descriptor
        // 2. Read packet from memory at descriptor's buffer_addr
        // 3. Compare byte-by-byte
        // 4. Check descriptor status updated
    endfunction
endclass
```

### 3.4 DMA Sequences

**Purpose**: Stimulus generation for DMA scenarios

**Location**: `verif/sequences/dma_sequences.sv`

**Key Sequences**:

1. **dma_config_seq**: Configure DMA registers
```systemverilog
class dma_config_seq extends uvm_sequence;
    rand bit [31:0] tx_desc_base;
    rand bit [31:0] rx_desc_base;
    rand bit [7:0]  tx_ring_size;
    rand bit [7:0]  rx_ring_size;
    
    task body();
        // Write descriptor base addresses
        write_reg(TX_DESC_BASE_LO, tx_desc_base);
        write_reg(TX_DESC_RING_SIZE, tx_ring_size);
        write_reg(RX_DESC_BASE_LO, rx_desc_base);
        write_reg(RX_DESC_RING_SIZE, rx_ring_size);
        
        // Enable DMA
        write_reg(DMA_CONTROL, TX_EN | RX_EN);
    endtask
endclass
```

2. **dma_tx_single_pkt_seq**: Send single packet via DMA
```systemverilog
class dma_tx_single_pkt_seq extends uvm_sequence;
    rand bit [7:0] packet_data[];
    rand bit [15:0] packet_len;
    
    constraint c_packet_size {
        packet_len inside {[64:1518]};
        packet_data.size() == packet_len;
    }
    
    task body();
        // 1. Allocate memory for packet
        bit [31:0] buf_addr = mem_model.alloc(packet_len);
        
        // 2. Write packet to memory
        mem_model.write_bytes(buf_addr, packet_data);
        
        // 3. Setup TX descriptor
        tx_desc_t desc;
        desc.buffer_addr = buf_addr;
        desc.buffer_len = packet_len;
        desc.control = DESC_OWN | DESC_LAST | DESC_INT_EN;
        
        // 4. Write descriptor to memory
        bit [31:0] desc_addr = tx_desc_base + (tx_index * 16);
        mem_model.write_desc(desc_addr, desc);
        
        // 5. Wait for completion interrupt
        wait_for_interrupt(IRQ_TX_DONE);
        
        // 6. Check descriptor updated
        desc = mem_model.read_desc(desc_addr);
        assert(desc.status & DESC_DONE);
        assert(!(desc.control & DESC_OWN));
    endtask
endclass
```

3. **dma_rx_burst_seq**: Receive burst of packets
4. **dma_tx_ring_wrap_seq**: Fill TX ring to test wrap-around
5. **dma_axi_error_seq**: Inject AXI errors

### 3.5 Extended MAC Environment

**Location**: `verif/env/mac_dma_env.sv`

```systemverilog
class mac_dma_env extends mac_env;  // Inherit from existing MAC env
    
    // New agents
    axi4_mem_agent      mem_agent;
    axi_lite_agent      dma_reg_agent;
    
    // New scoreboard
    dma_scoreboard      dma_sb;
    
    // Memory model
    axi4_mem_model      mem_model;
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Create new components only if DMA enabled
        if (cfg.dma_enable) begin
            mem_agent = axi4_mem_agent::type_id::create("mem_agent", this);
            dma_reg_agent = axi_lite_agent::type_id::create("dma_reg_agent", this);
            dma_sb = dma_scoreboard::type_id::create("dma_sb", this);
            mem_model = axi4_mem_model::type_id::create("mem_model", this);
        end
    endfunction
    
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        if (cfg.dma_enable) begin
            // Connect monitors to scoreboard
            mem_agent.monitor.item_collected_port.connect(dma_sb.mem_export);
            mac_agent.tx_monitor.item_collected_port.connect(dma_sb.mac_tx_export);
            mac_agent.rx_monitor.item_collected_port.connect(dma_sb.mac_rx_export);
        end
    endfunction
endclass
```

---

## 4. Test Plan

### 4.1 DMA-Specific Tests

#### Test 1: DMA TX Single Packet
**Objective**: Verify basic TX DMA functionality  
**Stimulus**:
- Configure DMA with single TX descriptor
- Setup descriptor with 64-byte packet
- Enable DMA TX
**Checks**:
- Packet appears on GMII interface
- Descriptor OWN bit cleared
- Descriptor DONE bit set
- TX completion interrupt generated

#### Test 2: DMA RX Single Packet
**Objective**: Verify basic RX DMA functionality  
**Stimulus**:
- Configure DMA with single RX descriptor
- Inject 64-byte packet on GMII
**Checks**:
- Packet written to memory at descriptor's buffer_addr
- Descriptor OWN bit cleared
- Descriptor actual_len matches packet length
- RX completion interrupt generated

#### Test 3: DMA TX Burst
**Objective**: Verify multiple packet transmission  
**Stimulus**:
- Setup 10 TX descriptors (chained)
- Vary packet sizes: 64, 128, 512, 1024, 1518 bytes
**Checks**:
- All packets transmitted in order
- All descriptors updated correctly
- No data corruption

#### Test 4: DMA RX Burst
**Objective**: Verify multiple packet reception  
**Stimulus**:
- Setup 10 RX descriptors
- Inject 10 packets of varying sizes
**Checks**:
- All packets captured correctly
- Memory contents match received packets
- Ring index advances correctly

#### Test 5: DMA Ring Wrap-Around (TX)
**Objective**: Verify TX ring wrap  
**Stimulus**:
- Configure ring size = 4 descriptors
- Send 8 packets (force 2 wraps)
**Checks**:
- DMA correctly wraps to descriptor 0
- No descriptor corruption
- All packets transmitted

#### Test 6: DMA Ring Wrap-Around (RX)
**Objective**: Verify RX ring wrap  
**Stimulus**:
- Configure ring size = 4 descriptors
- Receive 8 packets
**Checks**:
- DMA correctly wraps to descriptor 0
- WRAP bit in descriptor handled correctly
- All packets captured

#### Test 7: DMA Bypass Mode (DMA_ENABLE=0)
**Objective**: Verify MAC works without DMA  
**Stimulus**:
- Instantiate DUT with DMA_ENABLE=0
- Send packets via user AXI-Stream interface
**Checks**:
- Packets transmitted successfully
- DMA registers return DECERR
- AXI4 memory interface idle

#### Test 8: DMA TX Error Handling
**Objective**: Verify error detection  
**Stimulus**:
- Setup TX descriptor with invalid buffer address
- Inject AXI SLVERR during data read
**Checks**:
- DMA detects error
- Descriptor ERR bit set
- TX error interrupt generated
- DMA does not hang

#### Test 9: DMA RX Buffer Overflow
**Objective**: Verify overflow handling  
**Stimulus**:
- Setup RX descriptor with buffer_len = 512
- Receive 1518-byte packet
**Checks**:
- DMA detects overflow
- Error interrupt generated
- Partial data written (up to buffer_len)

#### Test 10: Concurrent TX/RX
**Objective**: Verify simultaneous operation  
**Stimulus**:
- Send and receive packets simultaneously
- Use random delays on AXI4 memory interface
**Checks**:
- No deadlock
- Both TX and RX complete correctly
- Descriptor arbitration works

### 4.2 Integration Tests (MAC + DMA)

#### Test 11: Full Loopback with DMA
**Objective**: End-to-end system test  
**Stimulus**:
- Configure DMA TX and RX
- Send packet via DMA → MAC → PHY loopback → MAC → DMA
**Checks**:
- Received packet matches transmitted packet
- Both TX and RX descriptors updated
- Both interrupts generated

#### Test 12: Stress Test
**Objective**: Long-duration test  
**Stimulus**:
- Run 1000 packets TX and RX
- Random packet sizes
- Random delays
**Checks**:
- No errors
- No hangs
- All packets accounted for

### 4.3 Backward Compatibility Tests

**Critical**: All existing MAC tests must pass without modification.

```
Test Suite                  | DMA_ENABLE=0 | DMA_ENABLE=1 (DMA unused)
----------------------------|--------------|---------------------------
mac_tx_basic_test           | PASS         | PASS
mac_rx_basic_test           | PASS         | PASS
mac_tx_rx_loopback_test     | PASS         | PASS
mac_tx_only_test            | PASS         | PASS
mac_crc_error_test          | PASS         | PASS
mac_runt_frame_test         | PASS         | PASS
mac_ifg_test                | PASS         | PASS
mac_reset_during_traffic    | PASS         | PASS
mac_comprehensive_test      | PASS         | PASS
```

---

## 5. Coverage Plan

### 5.1 Functional Coverage

#### Descriptor Coverage
```systemverilog
covergroup desc_cg;
    cp_buffer_len: coverpoint desc.buffer_len {
        bins small   = {[64:127]};
        bins medium  = {[128:511]};
        bins large   = {[512:1518]};
    }
    
    cp_own: coverpoint desc.control[OWN_BIT] {
        bins cpu_owned = {0};
        bins dma_owned = {1};
    }
    
    cp_last: coverpoint desc.control[LAST_BIT];
    cp_int_en: coverpoint desc.control[INT_EN_BIT];
    
    cross cp_buffer_len, cp_own, cp_last;
endgroup
```

#### DMA State Coverage
```systemverilog
covergroup dma_state_cg;
    cp_tx_state: coverpoint dut.u_eth.u_dma.u_tx_dma.state {
        bins idle = {STATE_IDLE};
        bins fetch_desc = {STATE_FETCH_DESC};
        bins stream = {STATE_STREAM_DATA};
        bins writeback = {STATE_WRITEBACK};
    }
    
    cp_rx_state: coverpoint dut.u_eth.u_dma.u_rx_dma.state;
    
    // State transitions
    cp_tx_transitions: coverpoint dut.u_eth.u_dma.u_tx_dma.state {
        bins idle_to_fetch = (STATE_IDLE => STATE_FETCH_DESC);
        bins fetch_to_stream = (STATE_FETCH_DESC => STATE_STREAM_DATA);
        bins stream_to_wb = (STATE_STREAM_DATA => STATE_WRITEBACK);
        bins wb_to_idle = (STATE_WRITEBACK => STATE_IDLE);
    }
endgroup
```

#### AXI4 Transaction Coverage
```systemverilog
covergroup axi4_cg;
    cp_burst_len: coverpoint txn.awlen {
        bins single = {0};
        bins short_burst = {[1:3]};
        bins medium_burst = {[4:7]};
        bins long_burst = {[8:15]};
    }
    
    cp_burst_type: coverpoint txn.awburst {
        bins fixed = {0};
        bins incr = {1};
        bins wrap = {2};
    }
    
    cp_resp: coverpoint txn.bresp {
        bins okay = {0};
        bins exokay = {1};
        bins slverr = {2};
        bins decerr = {3};
    }
endgroup
```

### 5.2 Code Coverage Goals

```
Coverage Type          | Target
-----------------------|--------
Line Coverage          | > 95%
Branch Coverage        | > 90%
Toggle Coverage        | > 80%
FSM State Coverage     | 100%
FSM Transition Cov     | > 95%
```

### 5.3 Assertion Coverage

Integrate SVA assertions in RTL:
```systemverilog
// Example: OWN bit transition
property p_own_bit_transition;
    @(posedge clk) disable iff (!rst_n)
    (desc_fetch && desc_own) |-> ##[1:100] (!desc_own);
endproperty
ap_own_transition: assert property(p_own_bit_transition);
cp_own_transition: cover property(p_own_bit_transition);

// AXI4 protocol assertions (use VIP)
```

---

## 6. Verification Environment Architecture

### 6.1 Top-Level Testbench

```
tb_top (SystemVerilog)
├── DUT: eth_controller_top
│   ├── u_mac: mac_top
│   └── u_dma: eth_dma_top (if DMA_ENABLE=1)
│
├── Interfaces:
│   ├── axi_lite_if (MAC registers)
│   ├── axi_lite_if (DMA registers)
│   ├── axi_stream_if (user TX/RX, only if DMA_ENABLE=0)
│   ├── axi4_if (memory)
│   └── gmii_if (PHY)
│
└── UVM Test Environment
    ├── mac_dma_env
    │   ├── axi_lite_agent (MAC regs)
    │   ├── axi_lite_agent (DMA regs)
    │   ├── axi4_mem_agent
    │   ├── axi_stream_agent (for bypass mode)
    │   ├── gmii_agent
    │   ├── eth_scoreboard (existing)
    │   └── dma_scoreboard (new)
    │
    └── Test Library
        ├── Existing MAC tests (unchanged)
        └── New DMA tests
```

### 6.2 Directory Structure

```
verif/
├── agents/
│   ├── axi4_mem_agent/           ← NEW
│   │   ├── axi4_mem_agent_pkg.sv
│   │   ├── axi4_mem_agent.sv
│   │   ├── axi4_mem_driver.sv
│   │   ├── axi4_mem_monitor.sv
│   │   ├── axi4_mem_sequencer.sv
│   │   ├── axi4_mem_txn.sv
│   │   └── axi4_mem_model.sv
│   ├── axi_stream_agent/         ← EXISTING (reuse)
│   ├── axi_lite_agent/           ← EXISTING (reuse)
│   └── gmii_agent/               ← EXISTING (reuse)
│
├── env/
│   ├── mac_env.sv                ← EXISTING (keep)
│   └── mac_dma_env.sv            ← NEW (extends mac_env)
│
├── scoreboard/
│   ├── eth_scoreboard.sv         ← EXISTING (keep)
│   └── dma_scoreboard.sv         ← NEW
│
├── sequences/
│   ├── mac_test_sequences.sv     ← EXISTING (keep)
│   └── dma_sequences.sv          ← NEW
│
└── tests/
    ├── mac_*_test.sv             ← EXISTING (keep all)
    └── dma_*_test.sv             ← NEW
```

---

## Summary

### Verification Scope

1. **6 new RTL modules** (DMA subsystem)
2. **3 new UVM agents** (AXI4 memory, DMA registers, extended env)
3. **12+ new test cases** (DMA-specific)
4. **All existing tests preserved** (backward compatibility)
5. **Comprehensive coverage** (functional + code + assertions)

### Non-Scope (Not Included)

This verification plan does NOT include:
- ❌ Software driver development
- ❌ Linux kernel integration
- ❌ FPGA board bring-up
- ❌ Performance benchmarking tools
- ❌ Power analysis
- ❌ RGMII PHY interface testing (focus on GMII)

### Timeline Estimate

```
Task                               | Effort
-----------------------------------|--------
Create AXI4 memory agent           | 2 weeks
Create DMA scoreboard              | 1 week
Create DMA sequences               | 1 week
Write DMA test cases               | 2 weeks
Extend MAC environment             | 1 week
Run regression (existing tests)    | 1 week
Debug and fix issues               | 2 weeks
Coverage closure                   | 1 week
-----------------------------------|--------
Total                              | 11 weeks
```

This plan ensures the DMA subsystem is thoroughly verified while maintaining the integrity of the existing MAC verification.
