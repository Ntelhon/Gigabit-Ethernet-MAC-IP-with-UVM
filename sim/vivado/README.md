# Vivado xsim Simulation Environment for MAC UVM Verification

## Overview

This directory contains scripts for running UVM-based verification of the Gigabit Ethernet MAC IP using Vivado xsim simulator.

## Requirements

### Software
- **Vivado**: 2022.1 or later (includes built-in UVM 1.2)
- **OS**: Windows 10/11 or Linux

### Environment Setup

#### Windows
```batch
:: Add Vivado to PATH
call C:\Xilinx\Vivado\2022.1\settings64.bat
```

#### Linux
```bash
# Add Vivado to PATH
source /tools/Xilinx/Vivado/2022.1/settings64.sh
```

### No External Dependencies Required
- **UVM_HOME**: Not required - Vivado includes UVM 1.2 library
- **No DPI**: Scripts configured with `UVM_NO_DPI` for xsim compatibility
- **No vendor PHY models**: Pure behavioral verification

## Directory Structure

```
project_root/
├── rtl/
│   ├── mac_core/         # MAC core RTL (Verilog)
│   └── phy_if/           # PHY interface RTL (Verilog)
├── verif/
│   ├── interfaces/       # SystemVerilog interfaces
│   ├── agents/           # UVM agents
│   │   ├── gmii_agent/
│   │   └── axi_lite_agent/
│   ├── env/              # UVM environment
│   ├── scoreboard/       # Ethernet scoreboard
│   ├── tests/            # UVM tests
│   └── tb/               # Testbench top
└── sim/
    └── vivado/
        ├── vivado_compile.tcl
        ├── vivado_run.tcl
        ├── compile.bat/.sh
        ├── run_test.bat/.sh
        ├── run_regression.bat/.sh
        ├── work/             # Generated: Vivado project
        └── results/          # Generated: Test logs
            └── <test_name>/
                ├── simulate.log
                └── <test_name>.wdb
```

## Quick Start

### Step 1: Compile the Design

#### Windows
```batch
cd sim\vivado
compile.bat
```

#### Linux
```bash
cd sim/vivado
./compile.sh
```

### Step 2: Run a Single Test

#### Windows
```batch
run_test.bat mac_tx_basic_test
run_test.bat mac_rx_basic_test -waves
run_test.bat mac_crc_error_test -verbosity UVM_HIGH -waves
```

#### Linux
```bash
./run_test.sh mac_tx_basic_test
./run_test.sh mac_rx_basic_test -waves
./run_test.sh mac_crc_error_test -verbosity UVM_HIGH -waves
```

### Step 3: Run Full Regression

#### Windows
```batch
run_regression.bat
run_regression.bat -waves
```

#### Linux
```bash
./run_regression.sh
./run_regression.sh -waves
```

## Available Tests

| Test Name | Description |
|-----------|-------------|
| `mac_tx_basic_test` | Basic TX path verification (64B and 512B frames) |
| `mac_rx_basic_test` | Basic RX path verification (min/med/max frames) |
| `mac_crc_error_test` | CRC error injection and detection |
| `mac_runt_frame_test` | Undersized frame handling |
| `mac_ifg_test` | Inter-Frame Gap timing verification |
| `mac_reset_during_traffic_test` | Reset robustness during transmission |

## Command Line Options

### run_test.bat / run_test.sh

| Option | Description | Default |
|--------|-------------|---------|
| `-verbosity <level>` | UVM verbosity level | `UVM_MEDIUM` |
| `-waves` | Enable waveform capture | Disabled |
| `-seed <value>` | Random seed | 1 |
| `-timeout <ns>` | Simulation timeout | 1000000 |
| `-gui` | Open waveform viewer | Disabled |

### Verbosity Levels

| Level | Description |
|-------|-------------|
| `UVM_NONE` | No messages |
| `UVM_LOW` | High-level summaries |
| `UVM_MEDIUM` | Standard test progress |
| `UVM_HIGH` | Detailed operation logs |
| `UVM_FULL` | All available information |
| `UVM_DEBUG` | Debug-level tracing |

## Viewing Waveforms

### After Simulation (Batch Mode)
```batch
:: Windows
vivado -source view_waves.tcl -tclargs results\mac_tx_basic_test\mac_tx_basic_test.wdb

:: Or open Vivado GUI and load WDB file
vivado
:: In Vivado: File -> Open Waveform Database
```

### During Simulation (With -gui)
```batch
run_test.bat mac_tx_basic_test -waves -gui
```

## Debugging Failures

### 1. Check Simulation Log
```batch
type results\mac_tx_basic_test\simulate.log
```

### 2. Increase Verbosity
```batch
run_test.bat mac_tx_basic_test -verbosity UVM_DEBUG -waves
```

### 3. Search for Errors
```batch
:: Windows
findstr /i "error fatal" results\mac_tx_basic_test\simulate.log

:: Linux
grep -i "error\|fatal" results/mac_tx_basic_test/simulate.log
```

### 4. Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Project not found" | Compilation not run | Run `compile.bat` first |
| "UVM_FATAL timeout" | Test hung | Check FSM states, increase timeout |
| "Scoreboard mismatch" | Data corruption | Check waveforms at GMII interface |
| "CRC error" | Frame corruption | Verify CRC logic in `mac_crc32.v` |

## Advanced Usage

### Run with Custom Vivado Arguments
```batch
vivado -mode batch -source vivado_run.tcl -tclargs -test mac_tx_basic_test -verbosity UVM_HIGH -waves
```

### Compile with Different Top Module
```batch
vivado -mode batch -source vivado_compile.tcl -tclargs -top custom_tb_top
```

### Run Interactively in Vivado TCL Console
```tcl
source vivado_compile.tcl
source vivado_run.tcl
```

## Batch Mode Integration

### Jenkins/CI Integration
```bash
#!/bin/bash
# CI script example
cd sim/vivado
./compile.sh || exit 1
./run_regression.sh || exit 1
echo "All tests passed"
```

### Makefile Integration
```makefile
.PHONY: compile sim regress clean

compile:
	cd sim/vivado && vivado -mode batch -source vivado_compile.tcl

sim:
	cd sim/vivado && vivado -mode batch -source vivado_run.tcl -tclargs -test $(TEST)

regress:
	cd sim/vivado && ./run_regression.sh

clean:
	rm -rf sim/vivado/work sim/vivado/results
```

## File Descriptions

| File | Purpose |
|------|---------|
| `vivado_compile.tcl` | Creates Vivado project, adds sources, sets include paths, configures xsim |
| `vivado_run.tcl` | Opens project, sets UVM plusargs, launches simulation, collects results |
| `compile.bat/.sh` | Wrapper scripts for easy compilation |
| `run_test.bat/.sh` | Wrapper scripts with argument parsing |
| `run_regression.bat/.sh` | Runs all tests and reports pass/fail summary |

## Notes

1. **No DPI**: All scripts set `UVM_NO_DPI` and `UVM_REGEX_NO_DPI` for xsim compatibility
2. **Built-in UVM**: Uses Vivado's included UVM 1.2 library (no external UVM_HOME needed)
3. **Relative Paths**: All paths are relative to script location for portability
4. **ASIC-Friendly**: No vendor-specific constructs in verification environment
