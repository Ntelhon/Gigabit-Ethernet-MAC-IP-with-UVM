# Cadence Xcelium Simulation Environment for MAC UVM Verification

## Overview

This directory contains scripts for running UVM-based verification of the Gigabit Ethernet MAC IP using Cadence Xcelium (xrun) simulator.

## Requirements

### Software
- **Cadence Xcelium**: 20.09 or later
- **License**: Valid Cadence license (CDS_LIC_FILE)
- **OS**: Linux (RHEL 7/8, CentOS 7/8)

### Environment Setup

```bash
# Add Xcelium to PATH
export PATH=/tools/cadence/XCELIUM2309/tools/bin:$PATH

# Set license server
export CDS_LIC_FILE=5280@license_server

# Optional: Cadence install root
export CDS_INST_DIR=/tools/cadence/XCELIUM2309

# Verify installation
xrun -version
```

### UVM Library
- **Built-in**: Xcelium includes UVM 1.2 (no external UVM_HOME required)
- **No DPI**: Scripts configured with `UVM_NO_DPI` for compatibility

## Directory Structure

```
sim/xcelium/
├── rtl.f               # RTL file list
├── tb.f                # Testbench file list
├── xrun_sim.sh         # Main simulation script
├── run_regression.sh   # Full regression script
├── waves.tcl           # Generated: waveform capture
├── cov.ccf             # Generated: coverage config
├── work/               # Generated: compile output
├── results/            # Generated: test logs
│   └── <test_name>/
│       ├── sim.log
│       ├── console.log
│       └── waves.shm/
└── coverage/           # Generated: coverage data
```

## Quick Start

### Step 1: Make Scripts Executable
```bash
cd sim/xcelium
chmod +x *.sh
```

### Step 2: Run a Single Test
```bash
# Basic test
./xrun_sim.sh -test mac_tx_basic_test

# With waveforms
./xrun_sim.sh -test mac_rx_basic_test -waves

# With high verbosity
./xrun_sim.sh -test mac_crc_error_test -verbosity UVM_HIGH -waves

# With coverage
./xrun_sim.sh -test mac_ifg_test -cov
```

### Step 3: Run Full Regression
```bash
# Basic regression
./run_regression.sh

# With waves and coverage
./run_regression.sh -waves -cov
```

## Command Line Options

### xrun_sim.sh Options

| Option | Description | Default |
|--------|-------------|---------|
| `-test <name>` | UVM test name (required) | - |
| `-verbosity <level>` | UVM verbosity level | `UVM_MEDIUM` |
| `-seed <value>` | Random seed | `random` |
| `-timeout <time>` | Simulation timeout | `1000000ns` |
| `-waves` | Enable SHM waveform dump | Disabled |
| `-cov` | Enable functional coverage | Disabled |
| `-compile_only` | Compile only, don't run | - |
| `-run_only` | Run only (use existing compile) | - |
| `-gui` | Open SimVision GUI | Disabled |
| `-debug` | Enable debug mode (+rwc) | Disabled |
| `-clean` | Clean work directory first | - |

### Verbosity Levels

| Level | Description |
|-------|-------------|
| `UVM_NONE` | No messages |
| `UVM_LOW` | High-level summaries |
| `UVM_MEDIUM` | Standard test progress |
| `UVM_HIGH` | Detailed operation logs |
| `UVM_FULL` | All available information |
| `UVM_DEBUG` | Debug-level tracing |

## Available Tests

| Test Name | Description |
|-----------|-------------|
| `mac_tx_basic_test` | Basic TX path verification |
| `mac_rx_basic_test` | Basic RX path verification |
| `mac_crc_error_test` | CRC error injection and detection |
| `mac_runt_frame_test` | Undersized frame handling |
| `mac_ifg_test` | Inter-Frame Gap timing verification |
| `mac_reset_during_traffic_test` | Reset robustness during transmission |

## Viewing Waveforms in SimVision

### After Simulation
```bash
# Launch SimVision with waveform database
simvision results/mac_tx_basic_test/waves.shm &
```

### During Simulation (Interactive)
```bash
./xrun_sim.sh -test mac_tx_basic_test -waves -gui
```

### SimVision Tips
```tcl
# In SimVision console:

# Add all signals from DUT
probe -create tb_top.dut -depth all

# Add specific signals
probe -create tb_top.dut.gmii_txd
probe -create tb_top.dut.gmii_tx_en

# Save waveform configuration
window -save waves.svcf
```

## Coverage Analysis

### View Coverage Report
```bash
# Launch IMC (Incisive Metrics Center)
imc -load coverage/mac_tx_basic_test.ucd &
```

### Merge Coverage from Regression
```bash
cd coverage
imc -exec merge_cov.tcl

# merge_cov.tcl contents:
# load -run */*.ucd
# merge -out merged.ucd -message 1
# report -metrics all -out cov_report.txt
```

### Generate HTML Report
```bash
imc -load coverage/merged.ucd -exec html_report.tcl

# html_report.tcl contents:
# report_metrics -out cov_html -format html -detail all
```

## Debugging Failures

### 1. Check Simulation Log
```bash
cat results/mac_tx_basic_test/sim.log

# Search for errors
grep -i "error\|fatal" results/mac_tx_basic_test/sim.log
```

### 2. Increase Verbosity
```bash
./xrun_sim.sh -test mac_tx_basic_test -verbosity UVM_DEBUG -waves
```

### 3. Interactive Debug
```bash
./xrun_sim.sh -test mac_tx_basic_test -debug -gui
```

### 4. Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `xrun not found` | Xcelium not in PATH | Source Cadence environment |
| `License checkout failed` | License issue | Check CDS_LIC_FILE |
| `UVM_FATAL timeout` | Test hung | Check FSM states in waves |
| `Syntax error in file` | SV parsing issue | Check file compile order |
| `Module not found` | Missing include | Check file lists |

## File Lists

### rtl.f (RTL Sources)
- Pure Verilog files
- Compile order: dependencies first
- Uses `${PROJECT_ROOT}` variable

### tb.f (Testbench Sources)
- SystemVerilog files
- Include directories specified
- Package files before classes
- Top module last

## xrun Key Options Reference

| Option | Description |
|--------|-------------|
| `-64bit` | 64-bit compilation |
| `-sv` | Enable SystemVerilog |
| `-uvm` | Enable UVM library |
| `-timescale 1ns/1ps` | Default timescale |
| `-access +r` | Read access for probing |
| `-access +rwc` | Full debug access |
| `-linedebug` | Line-level debug info |
| `-messages` | Detailed messages |
| `-svseed <N>` | Set SV random seed |
| `-coverage all` | Enable all coverage |
| `-gui` | Launch SimVision |
| `-R` | Run-only (use snapshot) |
| `-compile` | Compile only |

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `CDS_LIC_FILE` | License server | `5280@server` |
| `CDS_INST_DIR` | Xcelium install | `/tools/cadence/XCELIUM` |
| `PROJECT_ROOT` | Project root path | Set by script |

## Makefile Integration

```makefile
XCELIUM_DIR = sim/xcelium

.PHONY: compile sim regress clean

compile:
	cd $(XCELIUM_DIR) && ./xrun_sim.sh -compile_only

sim:
	cd $(XCELIUM_DIR) && ./xrun_sim.sh -test $(TEST) -waves

regress:
	cd $(XCELIUM_DIR) && ./run_regression.sh -cov

clean:
	cd $(XCELIUM_DIR) && ./xrun_sim.sh -test dummy -clean
	rm -rf $(XCELIUM_DIR)/work $(XCELIUM_DIR)/results
```

## CI/CD Integration

```bash
#!/bin/bash
# Jenkins/CI script

set -e

# Source Cadence environment
source /tools/cadence/setup.sh

cd sim/xcelium

# Run regression with coverage
./run_regression.sh -cov

# Check results
if [ $? -ne 0 ]; then
    echo "REGRESSION FAILED"
    exit 1
fi

# Archive results
tar -czf regression_results.tar.gz results/ coverage/

echo "REGRESSION PASSED"
```

## Notes

1. **No DPI**: Scripts use `UVM_NO_DPI` for maximum portability
2. **Batch Mode**: All scripts designed for batch/headless execution
3. **Portable Paths**: Uses `PROJECT_ROOT` environment variable
4. **ASIC-Friendly**: No vendor-specific constructs in RTL or TB
5. **Industry Standard**: Follows Cadence recommended practices
