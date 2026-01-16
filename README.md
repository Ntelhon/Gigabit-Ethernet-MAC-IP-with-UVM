# Gigabit Ethernet MAC IP Core

A synthesizable Gigabit Ethernet MAC IP core with full UVM verification environment.

## Overview

This project implements a complete Gigabit Ethernet MAC (Media Access Controller) supporting GMII/RGMII PHY interfaces. The design is written in Verilog and includes a comprehensive UVM-based verification environment in SystemVerilog.

## Features

### MAC Core Features
- **GMII Interface**: Standard Gigabit Media Independent Interface (125 MHz, 8-bit data)
- **RGMII Interface**: Reduced pin count GMII (125 MHz DDR, 4-bit data)
- **AXI-Stream TX/RX**: Industry-standard streaming interface for data plane
- **AXI-Lite Registers**: Configuration and status registers
- **Automatic CRC Generation**: IEEE 802.3 CRC-32 for transmitted frames
- **CRC Verification**: Automatic FCS check on received frames
- **Automatic Padding**: Frames padded to minimum 64-byte size
- **Inter-Frame Gap**: Configurable IFG (default 12 bytes)
- **Store-and-Forward**: Complete frame buffered before transmission
- **Asynchronous Clock Domains**: CDC between system clock and GMII clock

### Verification Environment
- **UVM 1.2 Testbench**: Full UVM verification methodology
- **Agents**: AXI-Stream, AXI-Lite, and GMII agents with drivers/monitors
- **Scoreboard**: Automatic checking with Ethernet CRC model
- **Sequences**: Reusable sequence library for common scenarios
- **Tests**: Multiple test cases covering TX, RX, and loopback

## Directory Structure

```
AI-IP/
├── Makefile                    # Top-level build makefile
├── rtl/                        # RTL source files
│   ├── mac_core/              # MAC core modules
│   │   ├── mac_top.v          # Top-level MAC module
│   │   ├── mac_tx.v           # TX state machine
│   │   ├── mac_rx.v           # RX state machine
│   │   ├── mac_crc32.v        # CRC-32 calculator
│   │   ├── mac_regs.v         # AXI-Lite registers
│   │   ├── mac_tx_axi_stream.v    # TX AXI-Stream interface
│   │   ├── mac_rx_axi_stream.v    # RX AXI-Stream interface
│   │   ├── mac_gmii_if.v      # GMII interface logic
│   │   └── mac_cdc_fifo.v     # CDC FIFO for clock crossing
│   └── phy_if/                # PHY interface modules
│       ├── gmii_phy_if.v      # GMII PHY interface
│       └── rgmii_phy_if.v     # RGMII PHY interface
├── verif/                      # Verification environment
│   ├── tb/                    # Testbench top
│   │   └── tb_top.sv          # Top-level testbench
│   ├── agents/                # UVM agents
│   │   ├── axi_stream_agent/  # AXI-Stream agent
│   │   ├── axi_lite_agent/    # AXI-Lite agent
│   │   └── gmii_agent/        # GMII agent
│   ├── env/                   # UVM environment
│   │   ├── mac_env.sv         # Environment class
│   │   └── mac_virtual_sequencer.sv
│   ├── scoreboard/            # Scoreboard and models
│   │   ├── eth_scoreboard.sv  # Ethernet scoreboard
│   │   └── eth_crc_model.sv   # CRC reference model
│   ├── sequences/             # Test sequences
│   │   ├── mac_test_sequences.sv
│   │   ├── axi_stream_tx_frame_seq.sv
│   │   └── gmii_tx_rx_loopback_seq.sv
│   ├── tests/                 # Test classes
│   │   ├── mac_base_test.sv   # Base test class
│   │   ├── mac_tx_only_test.sv
│   │   ├── mac_tx_rx_loopback_test.sv
│   │   └── ...
│   └── interfaces/            # SystemVerilog interfaces
│       ├── axi_stream_if.sv
│       ├── axi_lite_if.sv
│       └── gmii_if.sv
└── sim/                        # Simulation scripts
    ├── vivado/                # Vivado/XSim simulation
    │   ├── compile.sh         # Compilation script
    │   ├── run_test.sh        # Run single test
    │   └── run_regression.sh  # Run all tests
    └── xcelium/               # Cadence Xcelium simulation
        ├── xrun_sim.sh        # Xcelium run script
        └── rtl.f              # RTL file list
```

## Getting Started

### Prerequisites

- **Vivado 2024.2** (or compatible version) for XSim simulation
- **Cadence Xcelium** (optional, for Xcelium simulation)
- Bash shell (Linux/macOS/WSL)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd AI-IP
   ```

2. **Run a single test (Vivado)**
   ```bash
   cd sim/vivado
   bash compile.sh
   bash run_test.sh mac_tx_only_test
   ```

3. **Run regression**
   ```bash
   cd sim/vivado
   bash run_regression.sh
   ```

4. **Using Makefile**
   ```bash
   make compile   # Compile design
   make run       # Run default test
   make regress   # Run all tests
   ```

## Test Cases

| Test Name | Description |
|-----------|-------------|
| `mac_tx_only_test` | TX-only test: Send frames via AXI-Stream, verify on GMII |
| `mac_tx_rx_loopback_test` | Loopback test: TX frames looped back to RX path |
| `mac_rx_basic_test` | RX-only test: Inject frames on GMII RX, verify on AXI-Stream |
| `mac_tx_basic_test` | Basic TX functionality test |
| `mac_crc_error_test` | CRC error injection and detection |
| `mac_runt_frame_test` | Runt frame (< 64 bytes) handling |
| `mac_ifg_test` | Inter-frame gap verification |

## Configuration

### MAC Registers (AXI-Lite)

| Address | Register | Description |
|---------|----------|-------------|
| 0x0000 | MAC_ADDR_LO | MAC Address [31:0] |
| 0x0004 | MAC_ADDR_HI | MAC Address [47:32] |
| 0x0008 | TX_CTRL | TX Control (bit 0: enable) |
| 0x000C | RX_CTRL | RX Control (bit 0: enable) |
| 0x0010 | CONFIG | General configuration |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TX_FIFO_DEPTH` | 8 | TX FIFO depth (2^n entries) |
| `RX_FIFO_DEPTH` | 8 | RX FIFO depth (2^n entries) |
| `MIN_FRAME_SIZE` | 64 | Minimum frame size (bytes) |
| `IFG_BYTES` | 12 | Inter-frame gap (bytes) |

## Architecture

### Clock Domains

- **sys_clk (100 MHz)**: System clock for AXI interfaces
- **gtx_clk (125 MHz)**: GMII TX clock domain
- **rx_clk (125 MHz)**: GMII RX clock domain

### Data Flow

```
TX Path:
  AXI-Stream TX → TX FIFO (CDC) → MAC TX FSM → CRC Gen → GMII TX

RX Path:
  GMII RX → MAC RX FSM → CRC Check → RX FIFO (CDC) → AXI-Stream RX
```

## Verification

The verification environment uses UVM 1.2 methodology:

- **Agents**: Modular, reusable verification components
- **Scoreboard**: Automatic comparison with reference model
- **Coverage**: Functional coverage for key scenarios
- **Assertions**: SVA for protocol checking

### Running with Verbosity

```bash
bash run_test.sh mac_tx_only_test UVM_HIGH
```

## License

This project is provided for educational and reference purposes.

## Contributing

Contributions are welcome! Please follow standard git workflow:

1. Fork the repository
2. Create a feature branch
3. Make changes with clear commit messages
4. Submit a pull request

## Contact

For questions or issues, please open a GitHub issue.
