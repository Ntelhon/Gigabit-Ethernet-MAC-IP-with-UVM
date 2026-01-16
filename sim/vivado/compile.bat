@echo off
REM ==============================================================================
REM File: compile.bat
REM Description: Windows batch script to compile MAC UVM testbench with Vivado
REM
REM Usage:
REM   compile.bat
REM
REM Author: AI-IP Generator
REM ==============================================================================

setlocal

REM ------------------------------------------------------------------------------
REM Get Script Directory
REM ------------------------------------------------------------------------------
set SCRIPT_DIR=%~dp0

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
REM Run Compilation
REM ------------------------------------------------------------------------------
echo.
echo ==============================================================================
echo Compiling MAC UVM Testbench
echo ==============================================================================
echo.

cd /d "%SCRIPT_DIR%"
vivado -mode batch -source vivado_compile.tcl

if errorlevel 1 (
    echo.
    echo Compilation FAILED!
    exit /b 1
)

echo.
echo Compilation complete!
echo.

endlocal
