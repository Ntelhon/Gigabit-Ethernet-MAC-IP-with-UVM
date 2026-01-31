#===============================================================================
# Makefile: UVM Simulation Control for Gigabit Ethernet MAC IP
#
# Description:
#   Unified Makefile for running UVM-based verification with multiple
#   simulators (Vivado xsim, Cadence Xcelium).
#
# Usage:
#   make help                           # Show usage
#   make compile SIM=vivado             # Compile with Vivado
#   make run SIM=vivado TEST=mac_tx_basic_test
#   make run SIM=xcelium TEST=mac_rx_basic_test -waves
#   make regress SIM=xcelium            # Run all tests
#   make clean                          # Clean all outputs
#
# Author: AI-IP Generator
# License: MIT
#===============================================================================

#-------------------------------------------------------------------------------
# Default Simulator Selection
#-------------------------------------------------------------------------------
# Supported: vivado, xcelium
SIM ?= vivado

#-------------------------------------------------------------------------------
# Project Directory Structure
#-------------------------------------------------------------------------------
# Get Makefile directory (project root)
PROJ_ROOT := $(shell pwd)

# RTL directories
RTL_DIR        := $(PROJ_ROOT)/rtl
RTL_MAC_DIR    := $(RTL_DIR)/mac_core
RTL_PHY_DIR    := $(RTL_DIR)/phy_if

# Verification directories
VERIF_DIR      := $(PROJ_ROOT)/verif
TB_IF_DIR      := $(VERIF_DIR)/interfaces
TB_AGENTS_DIR  := $(VERIF_DIR)/agents
TB_ENV_DIR     := $(VERIF_DIR)/env
TB_SCB_DIR     := $(VERIF_DIR)/scoreboard
TB_TESTS_DIR   := $(VERIF_DIR)/tests
TB_TOP_DIR     := $(VERIF_DIR)/tb

# Simulation directories
SIM_DIR        := $(PROJ_ROOT)/sim
VIVADO_DIR     := $(SIM_DIR)/vivado
XCELIUM_DIR    := $(SIM_DIR)/xcelium

#-------------------------------------------------------------------------------
# Simulation Parameters (Overridable from command line)
#-------------------------------------------------------------------------------
# Default test name
TEST ?= eth_sanity_test

# Random seed (1 = fixed, random = random)
SEED ?= 1

# UVM verbosity level
UVM_VERBOSITY ?= UVM_MEDIUM

# Simulation timeout (ns)
TIMEOUT ?= 1000000

# Enable waveforms (0 or 1)
WAVES ?= 0

# Enable coverage (0 or 1)
COV ?= 0

# Enable debug output (0 or 1)
DEBUG ?= 0

# Top module
TOP ?= tb_top

#-------------------------------------------------------------------------------
# Test List for Regression
#-------------------------------------------------------------------------------
TESTS := \
    eth_sanity_test \
    eth_rx_path_test \
    eth_tx_path_test \
    eth_bidir_test \
    mac_sanity_test \
    dma_descriptor_test

#-------------------------------------------------------------------------------
# Vivado xsim Configuration
#-------------------------------------------------------------------------------
# Vivado executable
VIVADO ?= vivado

# Vivado TCL scripts
VIVADO_COMPILE_TCL := $(VIVADO_DIR)/vivado_compile.tcl
VIVADO_RUN_TCL     := $(VIVADO_DIR)/vivado_run.tcl

# Vivado output directories
VIVADO_WORK    := $(VIVADO_DIR)/work
VIVADO_RESULTS := $(VIVADO_DIR)/results

# Vivado wave options
ifeq ($(WAVES),1)
    VIVADO_WAVE_OPT := -waves
else
    VIVADO_WAVE_OPT :=
endif

# Vivado debug options
ifeq ($(DEBUG),1)
    VIVADO_DEBUG_OPT := debug
else
    VIVADO_DEBUG_OPT :=
endif

#-------------------------------------------------------------------------------
# Cadence Xcelium Configuration
#-------------------------------------------------------------------------------
# Xcelium executable
XRUN ?= xrun

# File lists
XCELIUM_RTL_F := $(XCELIUM_DIR)/rtl.f
XCELIUM_TB_F  := $(XCELIUM_DIR)/tb.f

# Xcelium output directories
XCELIUM_WORK    := $(XCELIUM_DIR)/work
XCELIUM_RESULTS := $(XCELIUM_DIR)/results
XCELIUM_COV     := $(XCELIUM_DIR)/coverage

# Xcelium common options
XRUN_OPTS := \
    -64bit \
    -sv \
    -uvm \
    -timescale 1ns/1ps \
    -top $(TOP) \
    -define UVM_NO_DPI \
    -define UVM_REGEX_NO_DPI \
    -define SIMULATION \
    -messages \
    -nowarn COVDEF \
    -nowarn COVSEC

# Xcelium debug output options
ifeq ($(DEBUG),1)
    XRUN_OPTS += -define DEBUG
endif

# Xcelium waveform options
ifeq ($(WAVES),1)
    XRUN_OPTS += -access +rwc -linedebug
else
    XRUN_OPTS += -access +r
endif

# Xcelium coverage options
ifeq ($(COV),1)
    XRUN_OPTS += -coverage all -covoverwrite
endif

#-------------------------------------------------------------------------------
# Phony Targets
#-------------------------------------------------------------------------------
.PHONY: help compile run sim regress waves clean \
        compile_vivado run_vivado waves_vivado clean_vivado \
        compile_xcelium run_xcelium waves_xcelium clean_xcelium \
        check_sim check_vivado check_xcelium \
        list_tests info

#-------------------------------------------------------------------------------
# Default Target
#-------------------------------------------------------------------------------
.DEFAULT_GOAL := help

#-------------------------------------------------------------------------------
# Help Target
#-------------------------------------------------------------------------------
help:
	@echo ""
	@echo "==============================================================================="
	@echo " Gigabit Ethernet MAC UVM Simulation Makefile"
	@echo "==============================================================================="
	@echo ""
	@echo " Supported Simulators:"
	@echo "   SIM=vivado    Vivado Simulator (xsim) [default]"
	@echo "   SIM=xcelium   Cadence Xcelium (xrun)"
	@echo ""
	@echo " Targets:"
	@echo "   make help         Show this help message"
	@echo "   make compile      Compile RTL and testbench"
	@echo "   make run          Run a single UVM test"
	@echo "   make regress      Run all tests in regression"
	@echo "   make waves        Open waveform viewer"
	@echo "   make clean        Remove all simulation outputs"
	@echo "   make list_tests   List available tests"
	@echo "   make info         Show current configuration"
	@echo ""
	@echo " Variables (override on command line):"
	@echo "   TEST=<name>           UVM test name (default: $(TEST))"
	@echo "   SEED=<value>          Random seed (default: $(SEED))"
	@echo "   UVM_VERBOSITY=<level> Verbosity (default: $(UVM_VERBOSITY))"
	@echo "   TIMEOUT=<ns>          Timeout in ns (default: $(TIMEOUT))"
	@echo "   WAVES=1               Enable waveform dump"
	@echo "   COV=1                 Enable coverage (xcelium)"
	@echo "   DEBUG=1               Enable verbose debug output"
	@echo ""
	@echo " Examples:"
	@echo "   make run SIM=vivado TEST=mac_tx_basic_test"
	@echo "   make run SIM=xcelium TEST=mac_rx_basic_test WAVES=1"
	@echo "   make compile SIM=vivado DEBUG=1"
	@echo "   make regress SIM=xcelium COV=1"
	@echo "   make waves SIM=vivado TEST=mac_tx_basic_test"
	@echo "   make clean"
	@echo ""
	@echo "==============================================================================="
	@echo ""

#-------------------------------------------------------------------------------
# List Available Tests
#-------------------------------------------------------------------------------
list_tests:
	@echo ""
	@echo "Available UVM Tests:"
	@echo "--------------------"
	@for test in $(TESTS); do \
		echo "  $$test"; \
	done
	@echo ""

#-------------------------------------------------------------------------------
# Show Current Configuration
#-------------------------------------------------------------------------------
info:
	@echo ""
	@echo "Current Configuration:"
	@echo "----------------------"
	@echo "  Simulator:       $(SIM)"
	@echo "  Test:            $(TEST)"
	@echo "  Seed:            $(SEED)"
	@echo "  Verbosity:       $(UVM_VERBOSITY)"
	@echo "  Timeout:         $(TIMEOUT) ns"
	@echo "  Waves:           $(WAVES)"
	@echo "  Coverage:        $(COV)"
	@echo "  Debug:           $(DEBUG)"
	@echo "  Project Root:    $(PROJ_ROOT)"
	@echo ""

#-------------------------------------------------------------------------------
# Simulator Check Targets
#-------------------------------------------------------------------------------
check_sim:
ifeq ($(SIM),vivado)
	@$(MAKE) --no-print-directory check_vivado
else ifeq ($(SIM),xcelium)
	@$(MAKE) --no-print-directory check_xcelium
else
	@echo "ERROR: Unknown simulator '$(SIM)'"
	@echo "Supported: vivado, xcelium"
	@exit 1
endif

check_vivado:
	@which $(VIVADO) > /dev/null 2>&1 || \
		(echo "ERROR: Vivado not found. Please add to PATH." && exit 1)

check_xcelium:
	@which $(XRUN) > /dev/null 2>&1 || \
		(echo "ERROR: xrun not found. Please source Cadence environment." && exit 1)

#===============================================================================
# COMPILE TARGETS
#===============================================================================

#-------------------------------------------------------------------------------
# Compile (Dispatcher)
#-------------------------------------------------------------------------------
compile: check_sim
ifeq ($(SIM),vivado)
	@$(MAKE) --no-print-directory compile_vivado
else ifeq ($(SIM),xcelium)
	@$(MAKE) --no-print-directory compile_xcelium
endif

#-------------------------------------------------------------------------------
# Compile - Vivado
#-------------------------------------------------------------------------------
compile_vivado: check_vivado
	@echo ""
	@echo "==============================================================================="
	@echo " Compiling with Vivado xsim"
ifeq ($(DEBUG),1)
	@echo " DEBUG mode enabled"
endif
	@echo "==============================================================================="
	@echo ""
	@mkdir -p $(VIVADO_WORK)
	@cd $(VIVADO_DIR) && DEBUG_MODE=$(DEBUG) $(VIVADO) -mode batch -source $(VIVADO_COMPILE_TCL) \
		-notrace -nojournal \
		2>&1 | tee $(VIVADO_DIR)/compile.log
	@echo ""
	@echo "Compilation complete. Log: $(VIVADO_DIR)/compile.log"
	@echo ""

#-------------------------------------------------------------------------------
# Compile - Xcelium
#-------------------------------------------------------------------------------
compile_xcelium: check_xcelium
	@echo ""
	@echo "==============================================================================="
	@echo " Compiling with Cadence Xcelium"
ifeq ($(DEBUG),1)
	@echo " DEBUG mode enabled"
endif
	@echo "==============================================================================="
	@echo ""
	@mkdir -p $(XCELIUM_WORK)
	@cd $(XCELIUM_DIR) && \
		PROJECT_ROOT=$(PROJ_ROOT) $(XRUN) \
		$(XRUN_OPTS) \
		-f $(XCELIUM_RTL_F) \
		-f $(XCELIUM_TB_F) \
		-compile \
		-l $(XCELIUM_DIR)/compile.log
	@echo ""
	@echo "Compilation complete. Log: $(XCELIUM_DIR)/compile.log"
	@echo ""

#===============================================================================
# RUN TARGETS
#===============================================================================

#-------------------------------------------------------------------------------
# Run Single Test (Dispatcher)
#-------------------------------------------------------------------------------
run: check_sim
ifeq ($(SIM),vivado)
	@$(MAKE) --no-print-directory run_vivado
else ifeq ($(SIM),xcelium)
	@$(MAKE) --no-print-directory run_xcelium
endif

# Alias for run
sim: run

#-------------------------------------------------------------------------------
# Run - Vivado
#-------------------------------------------------------------------------------
run_vivado: check_vivado
	@echo ""
	@echo "==============================================================================="
	@echo " Running Test: $(TEST)"
	@echo " Simulator:    Vivado xsim"
	@echo " Seed:         $(SEED)"
	@echo " Verbosity:    $(UVM_VERBOSITY)"
	@echo "==============================================================================="
	@echo ""
	@mkdir -p $(VIVADO_RESULTS)/$(TEST)
	@cd $(VIVADO_DIR) && $(VIVADO) -mode batch -source $(VIVADO_RUN_TCL) \
		-notrace -nojournal \
		-tclargs -test $(TEST) \
		          -verbosity $(UVM_VERBOSITY) \
		          -seed $(SEED) \
		          -timeout $(TIMEOUT) \
		          $(VIVADO_WAVE_OPT) \
		2>&1 | tee $(VIVADO_RESULTS)/$(TEST)/run.log
	@echo ""
	@echo "Results: $(VIVADO_RESULTS)/$(TEST)/"
	@echo ""

#-------------------------------------------------------------------------------
# Run - Xcelium
#-------------------------------------------------------------------------------
run_xcelium: check_xcelium
	@echo ""
	@echo "==============================================================================="
	@echo " Running Test: $(TEST)"
	@echo " Simulator:    Cadence Xcelium"
	@echo " Seed:         $(SEED)"
	@echo " Verbosity:    $(UVM_VERBOSITY)"
	@echo "==============================================================================="
	@echo ""
	@mkdir -p $(XCELIUM_RESULTS)/$(TEST)
	@cd $(XCELIUM_DIR) && \
		PROJECT_ROOT=$(PROJ_ROOT) $(XRUN) \
		$(XRUN_OPTS) \
		-f $(XCELIUM_RTL_F) \
		-f $(XCELIUM_TB_F) \
		+UVM_TESTNAME=$(TEST) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		+UVM_TIMEOUT=$(TIMEOUT) \
		-svseed $(SEED) \
		$(if $(filter 1,$(COV)),-covworkdir $(XCELIUM_COV) -covtest $(TEST)) \
		$(if $(filter 1,$(WAVES)),-input $(XCELIUM_DIR)/dump_waves.tcl) \
		-l $(XCELIUM_RESULTS)/$(TEST)/sim.log
	@if [ "$(WAVES)" = "1" ] && [ -d "$(XCELIUM_DIR)/waves.shm" ]; then \
		mv $(XCELIUM_DIR)/waves.shm $(XCELIUM_RESULTS)/$(TEST)/; \
	fi
	@echo ""
	@echo "Results: $(XCELIUM_RESULTS)/$(TEST)/"
	@echo ""

#===============================================================================
# REGRESSION TARGETS
#===============================================================================

#-------------------------------------------------------------------------------
# Run All Tests
#-------------------------------------------------------------------------------
regress: check_sim
	@echo ""
	@echo "==============================================================================="
	@echo " Running Regression with $(SIM)"
	@echo "==============================================================================="
	@echo ""
	@echo "Tests to run:"
	@for test in $(TESTS); do echo "  - $$test"; done
	@echo ""
	@# Compile once
	@$(MAKE) --no-print-directory compile SIM=$(SIM)
	@# Run each test
	@PASS=0; FAIL=0; \
	for test in $(TESTS); do \
		echo ""; \
		echo "----------------------------------------------------------------------"; \
		echo "Running: $$test"; \
		echo "----------------------------------------------------------------------"; \
		if $(MAKE) --no-print-directory run SIM=$(SIM) TEST=$$test WAVES=$(WAVES) COV=$(COV); then \
			echo "RESULT: $$test PASSED"; \
			PASS=$$((PASS + 1)); \
		else \
			echo "RESULT: $$test FAILED"; \
			FAIL=$$((FAIL + 1)); \
			if [ "$(STOP_ON_FAIL)" = "1" ]; then \
				echo "Stopping on first failure (STOP_ON_FAIL=1)"; \
				exit 1; \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "======================================================================"; \
	echo " Regression Summary"; \
	echo "======================================================================"; \
	echo " Passed: $$PASS"; \
	echo " Failed: $$FAIL"; \
	echo " Total:  $$(echo $(TESTS) | wc -w)"; \
	echo "======================================================================"; \
	if [ $$FAIL -gt 0 ]; then \
		echo " REGRESSION FAILED"; \
		exit 1; \
	else \
		echo " REGRESSION PASSED"; \
	fi

#===============================================================================
# WAVEFORM TARGETS
#===============================================================================

#-------------------------------------------------------------------------------
# Open Waveform Viewer (Dispatcher)
#-------------------------------------------------------------------------------
waves: check_sim
ifeq ($(SIM),vivado)
	@$(MAKE) --no-print-directory waves_vivado
else ifeq ($(SIM),xcelium)
	@$(MAKE) --no-print-directory waves_xcelium
endif

#-------------------------------------------------------------------------------
# Waves - Vivado (xsim)
#-------------------------------------------------------------------------------
waves_vivado:
	@echo ""
	@echo "Opening Vivado waveform viewer..."
	@WDB_FILE=$(VIVADO_RESULTS)/$(TEST)/$(TEST).wdb; \
	if [ -f "$$WDB_FILE" ]; then \
		$(VIVADO) -mode gui -source $(VIVADO_DIR)/open_waves.tcl -tclargs $$WDB_FILE & \
	else \
		echo "ERROR: Waveform file not found: $$WDB_FILE"; \
		echo "Run simulation with WAVES=1 first."; \
		exit 1; \
	fi

#-------------------------------------------------------------------------------
# Waves - Xcelium (SimVision)
#-------------------------------------------------------------------------------
waves_xcelium:
	@echo ""
	@echo "Opening SimVision waveform viewer..."
	@SHM_DIR=$(XCELIUM_RESULTS)/$(TEST)/waves.shm; \
	if [ -d "$$SHM_DIR" ]; then \
		simvision $$SHM_DIR &; \
	else \
		echo "ERROR: Waveform directory not found: $$SHM_DIR"; \
		echo "Run simulation with WAVES=1 first."; \
		exit 1; \
	fi

#===============================================================================
# CLEAN TARGETS
#===============================================================================

#-------------------------------------------------------------------------------
# Clean All
#-------------------------------------------------------------------------------
clean: clean_vivado clean_xcelium
	@echo ""
	@echo "All simulation outputs cleaned."
	@echo ""

#-------------------------------------------------------------------------------
# Clean - Vivado
#-------------------------------------------------------------------------------
clean_vivado:
	@echo "Cleaning Vivado outputs..."
	@rm -rf $(VIVADO_WORK)
	@rm -rf $(VIVADO_RESULTS)
	@rm -rf $(VIVADO_DIR)/*.log
	@rm -rf $(VIVADO_DIR)/*.jou
	@rm -rf $(VIVADO_DIR)/.Xil
	@rm -rf $(VIVADO_DIR)/xsim.dir
	@rm -rf $(VIVADO_DIR)/*.pb
	@rm -rf $(VIVADO_DIR)/*.wdb

#-------------------------------------------------------------------------------
# Clean - Xcelium
#-------------------------------------------------------------------------------
clean_xcelium:
	@echo "Cleaning Xcelium outputs..."
	@rm -rf $(XCELIUM_WORK)
	@rm -rf $(XCELIUM_RESULTS)
	@rm -rf $(XCELIUM_COV)
	@rm -rf $(XCELIUM_DIR)/*.log
	@rm -rf $(XCELIUM_DIR)/*.key
	@rm -rf $(XCELIUM_DIR)/*.err
	@rm -rf $(XCELIUM_DIR)/xcelium.d
	@rm -rf $(XCELIUM_DIR)/waves.shm
	@rm -rf $(XCELIUM_DIR)/cov_work
	@rm -rf $(XCELIUM_DIR)/INCA_libs

#===============================================================================
# UTILITY TARGETS
#===============================================================================

#-------------------------------------------------------------------------------
# Create Xcelium Wave Dump Script (if needed)
#-------------------------------------------------------------------------------
$(XCELIUM_DIR)/dump_waves.tcl:
	@echo "Creating wave dump script..."
	@echo "database -open waves -shm -into waves.shm" > $@
	@echo "probe -create $(TOP) -depth all -all -shm -database waves" >> $@
	@echo "run" >> $@
	@echo "exit" >> $@

#-------------------------------------------------------------------------------
# Create Vivado Wave Open Script (if needed)
#-------------------------------------------------------------------------------
$(VIVADO_DIR)/open_waves.tcl:
	@echo "Creating wave open script..."
	@echo 'set wdb_file [lindex $$argv 0]' > $@
	@echo 'open_wave_database $$wdb_file' >> $@

#===============================================================================
# End of Makefile
#===============================================================================
