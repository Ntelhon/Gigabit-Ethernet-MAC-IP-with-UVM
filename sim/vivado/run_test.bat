@echo off
REM ==============================================================================
REM File: run_test.bat
REM Description: Windows batch script to run MAC UVM tests with Vivado xsim
REM
REM Usage:
REM   run_test.bat <test_name> [options]
REM
REM Examples:
REM   run_test.bat mac_tx_basic_test
REM   run_test.bat mac_rx_basic_test -waves
REM   run_test.bat mac_crc_error_test -verbosity UVM_HIGH -waves
REM
REM Author: AI-IP Generator
REM ==============================================================================

setlocal enabledelayedexpansion

REM ------------------------------------------------------------------------------
REM Check Arguments
REM ------------------------------------------------------------------------------
if "%1"=="" (
    echo.
    echo Usage: run_test.bat ^<test_name^> [options]
    echo.
    echo Available tests:
    echo   mac_tx_basic_test
    echo   mac_rx_basic_test
    echo   mac_crc_error_test
    echo   mac_runt_frame_test
    echo   mac_ifg_test
    echo   mac_reset_during_traffic_test
    echo.
    echo Options:
    echo   -verbosity ^<level^>  : UVM_NONE, UVM_LOW, UVM_MEDIUM, UVM_HIGH, UVM_FULL
    echo   -waves              : Enable waveform dumping
    echo   -seed ^<value^>       : Set random seed
    echo   -gui                : Open waveform viewer after simulation
    echo.
    exit /b 1
)

set TEST_NAME=%1
shift

REM Collect remaining arguments
set EXTRA_ARGS=
:parse_args
if "%1"=="" goto done_args
set EXTRA_ARGS=%EXTRA_ARGS% %1
shift
goto parse_args
:done_args

REM ------------------------------------------------------------------------------
REM Get Script Directory
REM ------------------------------------------------------------------------------
set SCRIPT_DIR=%~dp0
set PROJECT_ROOT=%SCRIPT_DIR%..\..

REM ------------------------------------------------------------------------------
REM Check Vivado
REM ------------------------------------------------------------------------------
where vivado >nul 2>&1
if errorlevel 1 (
    echo ERROR: Vivado not found in PATH
    echo Please source Vivado settings first:
    echo   call C:\Xilinx\Vivado\2022.1\settings64.bat
    exit /b 1
)

REM ------------------------------------------------------------------------------
REM Check if Project Exists
REM ------------------------------------------------------------------------------
if not exist "%SCRIPT_DIR%work\mac_sim.xpr" (
    echo Project not found. Running compilation first...
    call "%SCRIPT_DIR%compile.bat"
    if errorlevel 1 (
        echo Compilation failed!
        exit /b 1
    )
)

REM ------------------------------------------------------------------------------
REM Run Simulation
REM ------------------------------------------------------------------------------
echo.
echo ==============================================================================
echo Running test: %TEST_NAME%
echo ==============================================================================
echo.

cd /d "%SCRIPT_DIR%"
vivado -mode batch -source vivado_run.tcl -tclargs -test %TEST_NAME% %EXTRA_ARGS%

REM ------------------------------------------------------------------------------
REM Report Results Location
REM ------------------------------------------------------------------------------
echo.
echo Results available in: %SCRIPT_DIR%results\%TEST_NAME%\
echo.

endlocal
