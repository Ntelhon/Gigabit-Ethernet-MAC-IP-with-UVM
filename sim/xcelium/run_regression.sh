#!/bin/bash
#===============================================================================
# File: run_regression.sh
# Description: Run all MAC UVM tests with Cadence Xcelium
#
# Usage:
#   ./run_regression.sh [options]
#
# Options:
#   -waves    Enable waveform capture for all tests
#   -cov      Enable coverage collection
#   -clean    Clean before starting
#   -j <N>    Run N tests in parallel (default: 1)
#
# Author: AI-IP Generator
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#-------------------------------------------------------------------------------
# Default Options
#-------------------------------------------------------------------------------
WAVES_OPT=""
COV_OPT=""
CLEAN_OPT=""
PARALLEL=1

#-------------------------------------------------------------------------------
# Parse Arguments
#-------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        -waves)
            WAVES_OPT="-waves"
            shift
            ;;
        -cov)
            COV_OPT="-cov"
            shift
            ;;
        -clean)
            CLEAN_OPT="-clean"
            shift
            ;;
        -j)
            PARALLEL="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

#-------------------------------------------------------------------------------
# Test List
#-------------------------------------------------------------------------------
TESTS=(
    "mac_tx_basic_test"
    "mac_rx_basic_test"
    "mac_crc_error_test"
    "mac_runt_frame_test"
    "mac_ifg_test"
    "mac_reset_during_traffic_test"
)

#-------------------------------------------------------------------------------
# Run Regression
#-------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "                    MAC UVM Regression Suite (Xcelium)"
echo "=============================================================================="
echo ""

# Compile first
echo "Compiling design..."
"$SCRIPT_DIR/xrun_sim.sh" -compile_only $CLEAN_OPT
echo ""

# Results tracking
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=${#TESTS[@]}

# Create results summary file
SUMMARY_FILE="$SCRIPT_DIR/results/regression_summary.txt"
mkdir -p "$SCRIPT_DIR/results"
echo "Regression Summary - $(date)" > "$SUMMARY_FILE"
echo "============================================" >> "$SUMMARY_FILE"

# Run tests
for test in "${TESTS[@]}"; do
    echo "------------------------------------------------------------------------------"
    echo "Running: $test"
    echo "------------------------------------------------------------------------------"
    
    if "$SCRIPT_DIR/xrun_sim.sh" -test "$test" -run_only $WAVES_OPT $COV_OPT; then
        echo "$test: PASSED" >> "$SUMMARY_FILE"
        ((PASS_COUNT++))
    else
        echo "$test: FAILED" >> "$SUMMARY_FILE"
        ((FAIL_COUNT++))
    fi
    echo ""
done

#-------------------------------------------------------------------------------
# Merge Coverage (if enabled)
#-------------------------------------------------------------------------------
if [[ -n "$COV_OPT" ]]; then
    echo "Merging coverage data..."
    cd "$SCRIPT_DIR/coverage"
    imc -load *.ucd -exec "merge -out merged_cov.ucd -message 1"
    echo "Coverage merged: $SCRIPT_DIR/coverage/merged_cov.ucd"
fi

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "                       Regression Summary"
echo "=============================================================================="
echo "Total:  $TOTAL_COUNT"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo "=============================================================================="
echo ""

cat "$SUMMARY_FILE"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "REGRESSION FAILED"
    exit 1
else
    echo "REGRESSION PASSED"
    exit 0
fi
