#!/bin/bash
#===============================================================================
# File: compile.sh
# Description: Linux/Unix script to compile MAC UVM testbench with Vivado
#
# Usage:
#   ./compile.sh
#
# Author: AI-IP Generator
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Script Directory
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
echo "=============================================================================="
echo ""

cd "$SCRIPT_DIR"
vivado -mode batch -source vivado_compile.tcl

echo ""
echo "Compilation complete!"
echo ""
