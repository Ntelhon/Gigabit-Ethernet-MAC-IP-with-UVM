#!/bin/bash
#===============================================================================
# File: run_test.sh
# Description: Linux/Unix script to run MAC UVM tests with Vivado xsim
#
# Usage:
#   ./run_test.sh <test_name> [options]
#
# Examples:
#   ./run_test.sh mac_tx_basic_test
#   ./run_test.sh mac_rx_basic_test -waves
#   ./run_test.sh mac_crc_error_test -verbosity UVM_HIGH -waves
#
# Author: AI-IP Generator
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Script Directory
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

#-------------------------------------------------------------------------------
# Usage
#-------------------------------------------------------------------------------
usage() {
    echo ""
    echo "Usage: $0 <test_name> [options]"
    echo ""
    echo "Available tests:"
    echo "  mac_tx_basic_test"
    echo "  mac_rx_basic_test"
    echo "  mac_crc_error_test"
    echo "  mac_runt_frame_test"
    echo "  mac_ifg_test"
    echo "  mac_reset_during_traffic_test"
    echo ""
    echo "Options:"
    echo "  -verbosity <level>  : UVM_NONE, UVM_LOW, UVM_MEDIUM, UVM_HIGH, UVM_FULL"
    echo "  -waves              : Enable waveform dumping"
    echo "  -seed <value>       : Set random seed"
    echo "  -gui                : Open waveform viewer after simulation"
    echo ""
    exit 1
}

#-------------------------------------------------------------------------------
# Check Arguments
#-------------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    usage
fi

TEST_NAME=$1
shift

#-------------------------------------------------------------------------------
# Check Vivado
#-------------------------------------------------------------------------------
if ! command -v vivado &> /dev/null; then
    echo "ERROR: Vivado not found in PATH"
    echo "Please source Vivado settings first:"
    echo "  source /tools/Xilinx/Vivado/2022.1/settings64.sh"
    exit 1
fi

#-------------------------------------------------------------------------------
# Check if Project Exists
#-------------------------------------------------------------------------------
if [ ! -f "$SCRIPT_DIR/work/mac_sim.xpr" ]; then
    echo "Project not found. Running compilation first..."
    "$SCRIPT_DIR/compile.sh"
fi

#-------------------------------------------------------------------------------
# Run Simulation
#-------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "Running test: $TEST_NAME"
echo "=============================================================================="
echo ""

cd "$SCRIPT_DIR"

# Create results directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/results/$TEST_NAME"

# Run Vivado and capture output to run.log
vivado -mode batch -source vivado_run.tcl -tclargs -test "$TEST_NAME" "$@" 2>&1 | tee "$SCRIPT_DIR/results/$TEST_NAME/run.log"

#-------------------------------------------------------------------------------
# Report Results Location
#-------------------------------------------------------------------------------
echo ""
echo "Results available in: $SCRIPT_DIR/results/$TEST_NAME/"
echo ""
