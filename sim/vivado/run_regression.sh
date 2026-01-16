#!/bin/bash
#===============================================================================
# File: run_regression.sh
# Description: Run all directed UVM tests in regression
#
# Usage:
#   ./run_regression.sh
#   ./run_regression.sh -waves
#
# Author: AI-IP Generator
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAVES_OPT=""

# Check for waves option
if [ "$1" = "-waves" ]; then
    WAVES_OPT="-waves"
fi

# Test list
TESTS=(
    "mac_tx_basic_test"
    "mac_rx_basic_test"
    "mac_crc_error_test"
    "mac_runt_frame_test"
    "mac_ifg_test"
    "mac_reset_during_traffic_test"
)

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

echo ""
echo "=============================================================================="
echo "                    MAC UVM Regression Suite"
echo "=============================================================================="
echo ""

# Compile first
"$SCRIPT_DIR/compile.sh"

# Run each test
for test in "${TESTS[@]}"; do
    ((TOTAL_COUNT++))
    echo ""
    echo "------------------------------------------------------------------------------"
    echo "Running test $TOTAL_COUNT: $test"
    echo "------------------------------------------------------------------------------"
    
    set +e  # Don't exit on error
    "$SCRIPT_DIR/run_test.sh" "$test" $WAVES_OPT
    set -e
    
    # Check result
    if grep -q "TEST PASSED" "$SCRIPT_DIR/results/$test/simulate.log" 2>/dev/null; then
        echo "RESULT: PASSED"
        ((PASS_COUNT++))
    else
        echo "RESULT: FAILED"
        ((FAIL_COUNT++))
    fi
done

# Summary
echo ""
echo "=============================================================================="
echo "                      Regression Summary"
echo "=============================================================================="
echo "Total:  $TOTAL_COUNT"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo "=============================================================================="
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo "REGRESSION FAILED"
    exit 1
else
    echo "REGRESSION PASSED"
    exit 0
fi
