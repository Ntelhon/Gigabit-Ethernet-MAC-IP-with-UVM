@echo off
REM ==============================================================================
REM File: run_regression.bat
REM Description: Run all directed UVM tests in regression
REM
REM Usage:
REM   run_regression.bat
REM   run_regression.bat -waves
REM
REM Author: AI-IP Generator
REM ==============================================================================

setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set WAVES_OPT=

REM Check for waves option
if "%1"=="-waves" set WAVES_OPT=-waves

REM Test list
set TESTS=mac_tx_basic_test mac_rx_basic_test mac_crc_error_test mac_runt_frame_test mac_ifg_test mac_reset_during_traffic_test

set PASS_COUNT=0
set FAIL_COUNT=0
set TOTAL_COUNT=0

echo.
echo ==============================================================================
echo                     MAC UVM Regression Suite
echo ==============================================================================
echo.

REM Compile first
call "%SCRIPT_DIR%compile.bat"
if errorlevel 1 (
    echo Compilation failed! Aborting regression.
    exit /b 1
)

REM Run each test
for %%t in (%TESTS%) do (
    set /a TOTAL_COUNT+=1
    echo.
    echo ------------------------------------------------------------------------------
    echo Running test !TOTAL_COUNT!: %%t
    echo ------------------------------------------------------------------------------
    
    call "%SCRIPT_DIR%run_test.bat" %%t %WAVES_OPT%
    
    REM Check result
    findstr /c:"TEST PASSED" "%SCRIPT_DIR%results\%%t\simulate.log" >nul 2>&1
    if !errorlevel! equ 0 (
        echo RESULT: PASSED
        set /a PASS_COUNT+=1
    ) else (
        echo RESULT: FAILED
        set /a FAIL_COUNT+=1
    )
)

REM Summary
echo.
echo ==============================================================================
echo                       Regression Summary
echo ==============================================================================
echo Total:  %TOTAL_COUNT%
echo Passed: %PASS_COUNT%
echo Failed: %FAIL_COUNT%
echo ==============================================================================
echo.

if %FAIL_COUNT% gtr 0 (
    echo REGRESSION FAILED
    exit /b 1
) else (
    echo REGRESSION PASSED
    exit /b 0
)

endlocal
