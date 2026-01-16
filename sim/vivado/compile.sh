#!/bin/bash
#===============================================================================
# File: compile.sh
# Description: Linux/Unix script to compile MAC UVM testbench with Vivado
#
# Usage:
#   ./compile.sh           # Normal compilation
#   ./compile.sh debug     # Compile with DEBUG flag enabled
#
# Author: AI-IP Generator
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Script Directory
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#-------------------------------------------------------------------------------
# Parse Arguments
#-------------------------------------------------------------------------------
DEBUG_MODE=0
if [ "$1" == "debug" ] || [ "$1" == "DEBUG" ]; then
    DEBUG_MODE=1
    echo "DEBUG mode enabled - verbose debug output will be included"
fi

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
# Run Compilation
#-------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "Compiling MAC UVM Testbench"
if [ $DEBUG_MODE -eq 1 ]; then
    echo "  Mode: DEBUG (verbose output enabled)"
fi
echo "=============================================================================="
echo ""

cd "$SCRIPT_DIR"

# Export DEBUG flag for TCL script
export DEBUG_MODE=$DEBUG_MODE

vivado -mode batch -source vivado_compile.tcl

echo ""
echo "Compilation complete!"
echo ""
