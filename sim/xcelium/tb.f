#===============================================================================
# File: tb.f
# Description: UVM Testbench file list for Gigabit Ethernet MAC IP
#
# Usage:
#   xrun -f tb.f ...
#
# Note:
#   All paths are relative to project_root
#   Compile order: packages before classes, base before derived
#
# Author: AI-IP Generator
#===============================================================================

#-------------------------------------------------------------------------------
# Include Directories
#-------------------------------------------------------------------------------
-incdir ${PROJECT_ROOT}/verif/interfaces
-incdir ${PROJECT_ROOT}/verif/agents/gmii_agent
-incdir ${PROJECT_ROOT}/verif/agents/axi_lite_agent
-incdir ${PROJECT_ROOT}/verif/agents/axi_stream_agent
-incdir ${PROJECT_ROOT}/verif/scoreboard
-incdir ${PROJECT_ROOT}/verif/env
-incdir ${PROJECT_ROOT}/verif/sequences
-incdir ${PROJECT_ROOT}/verif/tests
-incdir ${PROJECT_ROOT}/verif/tb

#-------------------------------------------------------------------------------
# SystemVerilog Interfaces
#-------------------------------------------------------------------------------

# GMII interface
${PROJECT_ROOT}/verif/interfaces/gmii_if.sv

# AXI-Lite interface
${PROJECT_ROOT}/verif/interfaces/axi_lite_if.sv

# AXI-Stream interface (TX and RX)
${PROJECT_ROOT}/verif/interfaces/axi_stream_if.sv

#-------------------------------------------------------------------------------
# GMII Agent Package (compile order matters)
#-------------------------------------------------------------------------------

# GMII agent package (includes all agent components)
${PROJECT_ROOT}/verif/agents/gmii_agent/gmii_agent_pkg.sv

#-------------------------------------------------------------------------------
# AXI-Lite Agent Package
#-------------------------------------------------------------------------------

# AXI-Lite agent package (includes all agent components)
${PROJECT_ROOT}/verif/agents/axi_lite_agent/axi_lite_agent_pkg.sv

#-------------------------------------------------------------------------------
# AXI-Stream Agent Package
#-------------------------------------------------------------------------------

# AXI-Stream agent package (includes all agent components)
${PROJECT_ROOT}/verif/agents/axi_stream_agent/axi_stream_agent_pkg.sv

#-------------------------------------------------------------------------------
# Scoreboard Package
#-------------------------------------------------------------------------------

# Ethernet scoreboard package
${PROJECT_ROOT}/verif/scoreboard/eth_scoreboard_pkg.sv

#-------------------------------------------------------------------------------
# Environment Package
#-------------------------------------------------------------------------------

# MAC environment package (includes virtual sequencer, env)
${PROJECT_ROOT}/verif/env/mac_env_pkg.sv

#-------------------------------------------------------------------------------
# Test Package
#-------------------------------------------------------------------------------

# Test package (includes base test, sequences, all tests)
${PROJECT_ROOT}/verif/tests/mac_test_pkg.sv

#-------------------------------------------------------------------------------
# Testbench Top
#-------------------------------------------------------------------------------

# UVM testbench top module
${PROJECT_ROOT}/verif/tb/tb_top.sv
