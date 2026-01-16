#!/bin/bash
#===============================================================================
# File: xrun_sim.sh
# Description: Cadence Xcelium simulation script for MAC UVM verification
#
# Usage:
#   ./xrun_sim.sh -test <test_name> [options]
#
# Examples:
#   ./xrun_sim.sh -test mac_tx_basic_test
#   ./xrun_sim.sh -test mac_rx_basic_test -waves
#   ./xrun_sim.sh -test mac_crc_error_test -verbosity UVM_HIGH -waves -cov
#   ./xrun_sim.sh -compile_only
#   ./xrun_sim.sh -run_only -test mac_tx_basic_test
#
# Requirements:
#   - Cadence Xcelium (xrun) in PATH
#   - UVM 1.2 (included with Xcelium)
#
# Author: AI-IP Generator
# License: MIT
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Script Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

# Output directories
WORK_DIR="$SCRIPT_DIR/work"
RESULTS_DIR="$SCRIPT_DIR/results"
COV_DIR="$SCRIPT_DIR/coverage"

#-------------------------------------------------------------------------------
# Default Parameters
#-------------------------------------------------------------------------------
TEST_NAME=""
VERBOSITY="UVM_MEDIUM"
SEED="random"
TIMEOUT="1000000ns"
ENABLE_WAVES=0
ENABLE_COV=0
COMPILE_ONLY=0
RUN_ONLY=0
GUI_MODE=0
DEBUG_MODE=0

#-------------------------------------------------------------------------------
# Usage
#-------------------------------------------------------------------------------
usage() {
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Required (unless -compile_only):"
    echo "  -test <name>        UVM test name"
    echo ""
    echo "Options:"
    echo "  -verbosity <level>  UVM verbosity (UVM_NONE|LOW|MEDIUM|HIGH|FULL|DEBUG)"
    echo "  -seed <value>       Random seed (default: random)"
    echo "  -timeout <time>     Simulation timeout (default: 1000000ns)"
    echo "  -waves              Enable waveform dumping (SHM)"
    echo "  -cov                Enable functional coverage"
    echo "  -compile_only       Compile only, don't run"
    echo "  -run_only           Run only (use existing compile)"
    echo "  -gui                Open SimVision GUI"
    echo "  -debug              Enable debug mode (more access)"
    echo "  -clean              Clean work directory before compile"
    echo "  -h, -help           Show this help"
    echo ""
    echo "Available tests:"
    echo "  mac_tx_basic_test"
    echo "  mac_rx_basic_test"
    echo "  mac_crc_error_test"
    echo "  mac_runt_frame_test"
    echo "  mac_ifg_test"
    echo "  mac_reset_during_traffic_test"
    echo ""
    exit 1
}

#-------------------------------------------------------------------------------
# Parse Arguments
#-------------------------------------------------------------------------------
CLEAN=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -test)
            TEST_NAME="$2"
            shift 2
            ;;
        -verbosity)
            VERBOSITY="$2"
            shift 2
            ;;
        -seed)
            SEED="$2"
            shift 2
            ;;
        -timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -waves)
            ENABLE_WAVES=1
            shift
            ;;
        -cov)
            ENABLE_COV=1
            shift
            ;;
        -compile_only)
            COMPILE_ONLY=1
            shift
            ;;
        -run_only)
            RUN_ONLY=1
            shift
            ;;
        -gui)
            GUI_MODE=1
            shift
            ;;
        -debug)
            DEBUG_MODE=1
            shift
            ;;
        -clean)
            CLEAN=1
            shift
            ;;
        -h|-help)
            usage
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            ;;
    esac
done

#-------------------------------------------------------------------------------
# Validate Arguments
#-------------------------------------------------------------------------------
if [[ $COMPILE_ONLY -eq 0 && -z "$TEST_NAME" ]]; then
    echo "ERROR: Test name required (use -test <name>)"
    usage
fi

#-------------------------------------------------------------------------------
# Check Xcelium Installation
#-------------------------------------------------------------------------------
if ! command -v xrun &> /dev/null; then
    echo "ERROR: xrun not found in PATH"
    echo ""
    echo "Please source Cadence environment first:"
    echo "  source /tools/cadence/XCELIUM/tools/bin/xrun"
    echo ""
    echo "Or add to .bashrc:"
    echo "  export PATH=/tools/cadence/XCELIUM/tools/bin:\$PATH"
    echo "  export CDS_LIC_FILE=<license_server>"
    exit 1
fi

#-------------------------------------------------------------------------------
# Print Configuration
#-------------------------------------------------------------------------------
echo "=============================================================================="
echo "Cadence Xcelium Simulation Script"
echo "=============================================================================="
echo "Project Root:  $PROJECT_ROOT"
echo "Test Name:     ${TEST_NAME:-N/A}"
echo "Verbosity:     $VERBOSITY"
echo "Seed:          $SEED"
echo "Timeout:       $TIMEOUT"
echo "Waves:         $([ $ENABLE_WAVES -eq 1 ] && echo 'Enabled' || echo 'Disabled')"
echo "Coverage:      $([ $ENABLE_COV -eq 1 ] && echo 'Enabled' || echo 'Disabled')"
echo "=============================================================================="

#-------------------------------------------------------------------------------
# Clean (Optional)
#-------------------------------------------------------------------------------
if [[ $CLEAN -eq 1 ]]; then
    echo "Cleaning work directory..."
    rm -rf "$WORK_DIR"
    rm -rf "$SCRIPT_DIR/xcelium.d"
    rm -rf "$SCRIPT_DIR/waves.shm"
    rm -rf "$SCRIPT_DIR/*.log"
    rm -rf "$SCRIPT_DIR/*.key"
    rm -rf "$SCRIPT_DIR/*.err"
fi

#-------------------------------------------------------------------------------
# Create Directories
#-------------------------------------------------------------------------------
mkdir -p "$WORK_DIR"
mkdir -p "$RESULTS_DIR"
if [[ $ENABLE_COV -eq 1 ]]; then
    mkdir -p "$COV_DIR"
fi

#-------------------------------------------------------------------------------
# Build xrun Command - Common Options
#-------------------------------------------------------------------------------
XRUN_OPTS=""

# Basic options
XRUN_OPTS+=" -64bit"                          # 64-bit mode
XRUN_OPTS+=" -sv"                             # Enable SystemVerilog
XRUN_OPTS+=" -uvm"                            # Enable UVM 1.2
XRUN_OPTS+=" -timescale 1ns/1ps"              # Default timescale
XRUN_OPTS+=" -top tb_top"                     # Top module

# UVM options (no DPI)
XRUN_OPTS+=" -define UVM_NO_DPI"
XRUN_OPTS+=" -define UVM_REGEX_NO_DPI"
XRUN_OPTS+=" -define SIMULATION"

# Message control
XRUN_OPTS+=" -messages"                       # Enable detailed messages
XRUN_OPTS+=" -nowarn COVDEF"                  # Suppress coverage define warnings
XRUN_OPTS+=" -nowarn COVSEC"                  # Suppress coverage section warnings

# Debug access
if [[ $DEBUG_MODE -eq 1 ]]; then
    XRUN_OPTS+=" -access +rwc"                # Full read/write/connectivity
    XRUN_OPTS+=" -linedebug"                  # Line-level debug
else
    XRUN_OPTS+=" -access +r"                  # Read access for waves
fi

# File lists
XRUN_OPTS+=" -f $SCRIPT_DIR/rtl.f"
XRUN_OPTS+=" -f $SCRIPT_DIR/tb.f"

#-------------------------------------------------------------------------------
# Compile-Only Mode
#-------------------------------------------------------------------------------
if [[ $COMPILE_ONLY -eq 1 ]]; then
    echo ""
    echo "Compiling design..."
    
    xrun \
        $XRUN_OPTS \
        -compile \
        -l "$SCRIPT_DIR/compile.log" \
        2>&1 | tee "$SCRIPT_DIR/compile_output.log"
    
    echo ""
    echo "Compilation complete."
    echo "Log: $SCRIPT_DIR/compile.log"
    exit 0
fi

#-------------------------------------------------------------------------------
# Build xrun Command - Simulation Options
#-------------------------------------------------------------------------------

# Test name
XRUN_OPTS+=" +UVM_TESTNAME=$TEST_NAME"

# Verbosity
XRUN_OPTS+=" +UVM_VERBOSITY=$VERBOSITY"

# Seed
if [[ "$SEED" == "random" ]]; then
    XRUN_OPTS+=" -svseed random"
else
    XRUN_OPTS+=" -svseed $SEED"
fi

# Timeout
XRUN_OPTS+=" +UVM_TIMEOUT=$TIMEOUT"

# Waveform dumping
if [[ $ENABLE_WAVES -eq 1 ]]; then
    WAVE_DIR="$RESULTS_DIR/$TEST_NAME"
    mkdir -p "$WAVE_DIR"
    XRUN_OPTS+=" -input $SCRIPT_DIR/waves.tcl"
fi

# Coverage
if [[ $ENABLE_COV -eq 1 ]]; then
    XRUN_OPTS+=" -coverage all"
    XRUN_OPTS+=" -covoverwrite"
    XRUN_OPTS+=" -covfile $SCRIPT_DIR/cov.ccf"
    XRUN_OPTS+=" -covworkdir $COV_DIR"
    XRUN_OPTS+=" -covtest $TEST_NAME"
fi

# GUI mode
if [[ $GUI_MODE -eq 1 ]]; then
    XRUN_OPTS+=" -gui"
fi

# Run-only mode
if [[ $RUN_ONLY -eq 1 ]]; then
    XRUN_OPTS+=" -R"  # Run only (use existing snapshot)
fi

# Log file
LOG_DIR="$RESULTS_DIR/$TEST_NAME"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sim.log"

#-------------------------------------------------------------------------------
# Create Waveform TCL Script
#-------------------------------------------------------------------------------
if [[ $ENABLE_WAVES -eq 1 ]]; then
    cat > "$SCRIPT_DIR/waves.tcl" << 'EOF'
# Waveform capture script for Xcelium
database -open waves -shm -into waves.shm
probe -create tb_top -depth all -all -shm -database waves
run
exit
EOF
fi

#-------------------------------------------------------------------------------
# Create Coverage Configuration
#-------------------------------------------------------------------------------
if [[ $ENABLE_COV -eq 1 ]]; then
    cat > "$SCRIPT_DIR/cov.ccf" << 'EOF'
# Coverage configuration file

# Set coverage options
set_toggle_portsonly
set_covergroup -per_instance_default_one

# Include DUT
select_coverage -bet -module mac_top...

# Exclude testbench
deselect_coverage -bet -module tb_top
deselect_coverage -bet -module *_agent
deselect_coverage -bet -module *_driver
deselect_coverage -bet -module *_monitor
EOF
fi

#-------------------------------------------------------------------------------
# Run Simulation
#-------------------------------------------------------------------------------
echo ""
echo "Running simulation..."
echo "Command: xrun $XRUN_OPTS"
echo ""

START_TIME=$(date +%s)

xrun \
    $XRUN_OPTS \
    -l "$LOG_FILE" \
    2>&1 | tee "$LOG_DIR/console.log"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

#-------------------------------------------------------------------------------
# Move Waveform Files
#-------------------------------------------------------------------------------
if [[ $ENABLE_WAVES -eq 1 && -d "$SCRIPT_DIR/waves.shm" ]]; then
    mv "$SCRIPT_DIR/waves.shm" "$LOG_DIR/"
    echo "Waveforms: $LOG_DIR/waves.shm"
fi

#-------------------------------------------------------------------------------
# Check Results
#-------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "Simulation Results"
echo "=============================================================================="
echo "Elapsed Time: ${ELAPSED}s"
echo "Log File:     $LOG_FILE"

# Parse results
if grep -q "TEST PASSED" "$LOG_FILE" 2>/dev/null; then
    echo ""
    echo "       *** TEST PASSED ***"
    RESULT=0
elif grep -q "TEST FAILED" "$LOG_FILE" 2>/dev/null; then
    echo ""
    echo "       *** TEST FAILED ***"
    RESULT=1
elif grep -q "UVM_FATAL" "$LOG_FILE" 2>/dev/null; then
    echo ""
    echo "       *** TEST FAILED (UVM_FATAL) ***"
    RESULT=1
else
    echo ""
    echo "       *** TEST RESULT UNKNOWN ***"
    RESULT=1
fi

# Extract counts
if grep -q "UVM_ERROR" "$LOG_FILE" 2>/dev/null; then
    ERR_COUNT=$(grep -c "UVM_ERROR" "$LOG_FILE" || true)
    echo "UVM Errors:   $ERR_COUNT"
fi

if grep -q "UVM_WARNING" "$LOG_FILE" 2>/dev/null; then
    WARN_COUNT=$(grep -c "UVM_WARNING" "$LOG_FILE" || true)
    echo "UVM Warnings: $WARN_COUNT"
fi

echo "=============================================================================="
echo ""

exit $RESULT
