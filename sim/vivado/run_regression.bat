@echo off
REM ==============================================================================
REM File: run_regression.bat
REM Description: Run all directed UVM tests in regression
REM
REM Usage:
REM   run_regression.bat           - Run MAC tests only
REM   run_regression.bat -all      - Run all tests (MAC + DMA)
REM   run_regression.bat -dma      - Run DMA tests only
REM   run_regression.bat -waves    - Enable waveforms
REM
REM Author: AI-IP Generator
REM ==============================================================================

setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set WAVES_OPT=
set TEST_SET=mac

REM Check for options
:parse_opts
if "%1"=="-waves" (
    set WAVES_OPT=-waves
    shift
    goto parse_opts
)
if "%1"=="-all" (
    set TEST_SET=all
    shift
    goto parse_opts
)
if "%1"=="-dma" (
    set TEST_SET=dma
    shift
    goto parse_opts
)

REM MAC test list
set MAC_TESTS=mac_tx_basic_test mac_rx_basic_test mac_crc_error_test mac_runt_frame_test mac_ifg_test mac_reset_during_traffic_test mac_comprehensive_test

REM DMA test list (requires tb_dma_top)
set DMA_TESTS=dma_tx_only_test dma_rx_only_test dma_tx_rx_test dma_multi_packet_test dma_stress_test eth_controller_full_test

REM Select tests based on mode
if "%TEST_SET%"=="mac" (
    set TESTS=%MAC_TESTS%
    set TB_TOP=tb_top
) else if "%TEST_SET%"=="dma" (
    set TESTS=%DMA_TESTS%
    set TB_TOP=tb_dma_top
) else (
    set TESTS=%MAC_TESTS% %DMA_TESTS%
    set TB_TOP=tb_top
)

set PASS_COUNT=0
set FAIL_COUNT=0
set TOTAL_COUNT=0

echo.
echo ==============================================================================
echo                     Ethernet MAC/DMA UVM Regression Suite
echo                     Test Set: %TEST_SET%
echo ==============================================================================
echo.

REM Compile first (with appropriate top)
call "%SCRIPT_DIR%compile.bat"
if errorlevel 1 (
    echo Compilation failed! Aborting regression.
    exit /b 1
)

REM If running all tests, compile DMA tb as well
if "%TEST_SET%"=="all" (
    echo Compiling DMA testbench...
    call "%SCRIPT_DIR%compile.bat" -top tb_dma_top
)

REM Run each test
for %%t in (%TESTS%) do (
    set /a TOTAL_COUNT+=1
    
    REM Determine which testbench to use
    echo %%t | findstr /c:"dma" /c:"eth_controller" >nul 2>&1
    if !errorlevel! equ 0 (
        set CURR_TB=tb_dma_top
    ) else (
        set CURR_TB=tb_top
    )
    
    echo.
    echo ------------------------------------------------------------------------------
    echo Running test !TOTAL_COUNT!: %%t (TB: !CURR_TB!)
    echo ------------------------------------------------------------------------------
    
    call "%SCRIPT_DIR%run_test.bat" %%t -top !CURR_TB! %WAVES_OPT%
    
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
