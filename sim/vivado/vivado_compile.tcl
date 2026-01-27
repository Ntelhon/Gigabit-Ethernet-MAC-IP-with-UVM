#===============================================================================
# File: vivado_compile.tcl
# Description: Vivado xsim compilation script for Gigabit Ethernet MAC UVM TB
#
# Purpose:
#   Creates a Vivado simulation project and compiles all RTL and testbench
#   sources for UVM-based verification using xsim.
#
# Usage:
#   vivado -mode batch -source vivado_compile.tcl
#   vivado -mode batch -source vivado_compile.tcl -tclargs -top eth_tb_top
#
# Requirements:
#   - Vivado 2022.1 or later (UVM 1.2 built-in)
#   - No external UVM_HOME required (uses Vivado's built-in UVM)
#
# Author: AI-IP Generator
# License: MIT
#===============================================================================

#-------------------------------------------------------------------------------
# Parse Command Line Arguments
#-------------------------------------------------------------------------------
set top_module "eth_tb_top"
set project_name "mac_sim"
set part "xc7a100tcsg324-1"  ;# Default part (can be overridden)

for {set i 0} {$i < $argc} {incr i} {
    set arg [lindex $argv $i]
    switch -exact -- $arg {
        "-top" {
            incr i
            set top_module [lindex $argv $i]
        }
        "-project" {
            incr i
            set project_name [lindex $argv $i]
        }
        "-part" {
            incr i
            set part [lindex $argv $i]
        }
    }
}

#-------------------------------------------------------------------------------
# Directory Setup (Relative Paths)
#-------------------------------------------------------------------------------
# Get script directory as reference point
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize "$script_dir/../.."]

# Source directories
set rtl_mac_dir    "$project_root/rtl/mac_core"
set rtl_dma_dir    "$project_root/rtl/dma"
set rtl_phy_dir    "$project_root/rtl/phy_if"
set rtl_top        "$project_root/rtl"
set tb_agents_dir  "$project_root/verif/agents"
set tb_env_dir     "$project_root/verif/env"
set tb_seq_dir     "$project_root/verif/sequences"
set tb_tests_dir   "$project_root/verif/tests"
set tb_top_dir     "$project_root/verif/top"
set tb_if_dir      "$project_root/verif/agents"

# Output directory
set sim_dir        "$project_root/sim/vivado"
set work_dir       "$sim_dir/work"

#-------------------------------------------------------------------------------
# Clean Previous Build
#-------------------------------------------------------------------------------
puts "=============================================="
puts "Vivado xsim Compilation Script"
puts "=============================================="
puts "Project Root: $project_root"
puts "Top Module:   $top_module"
puts "=============================================="

if {[file exists $work_dir]} {
    puts "Cleaning previous build..."
    file delete -force $work_dir
}
file mkdir $work_dir
cd $work_dir

#-------------------------------------------------------------------------------
# Create Simulation Project
#-------------------------------------------------------------------------------
puts "Creating simulation project..."
create_project -force $project_name $work_dir -part $part

# Set project properties for simulation
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib work [current_project]

#-------------------------------------------------------------------------------
# Collect RTL Source Files (Verilog)
#-------------------------------------------------------------------------------
puts "Collecting RTL sources..."

set rtl_files [list]

# MAC Core RTL
foreach f [glob -nocomplain -directory $rtl_mac_dir *.v] {
    lappend rtl_files $f
}

# DMA RTL
foreach f [glob -nocomplain -directory $rtl_dma_dir *.v] {
    lappend rtl_files $f
}

# PHY Interface RTL
foreach f [glob -nocomplain -directory $rtl_phy_dir *.v] {
    lappend rtl_files $f
}

# Ethernet Top RTL
foreach f [glob -nocomplain -directory $rtl_top *.v] {
    lappend rtl_files $f
}

puts "Found [llength $rtl_files] RTL files"

#-------------------------------------------------------------------------------
# Collect Testbench Source Files (SystemVerilog)
#-------------------------------------------------------------------------------
puts "Collecting testbench sources..."

set tb_files [list]

# Agent Interfaces
lappend tb_files $tb_agents_dir/axi_stream/src/axi_stream_if.sv
lappend tb_files $tb_agents_dir/axi4/src/axi4_if.sv
lappend tb_files $tb_agents_dir/axi_lite/src/axi_lite_if.sv
lappend tb_files $tb_agents_dir/gmii/src/gmii_if.sv

# AXI-Stream Agent Packace
foreach f [glob -nocomplain -directory $tb_agents_dir/axi_stream *.sv] { lappend tb_files $f }

# AXI4 Agent Packace
foreach f [glob -nocomplain -directory $tb_agents_dir/axi4 *.sv] { lappend tb_files $f }

# AXI-Lite Agent Packace
foreach f [glob -nocomplain -directory $tb_agents_dir/axi_lite *.sv] { lappend tb_files $f }

# GMII Agent Packace
foreach f [glob -nocomplain -directory $tb_agents_dir/gmii *.sv] { lappend tb_files $f }

# Sequence Packace
foreach f [glob -nocomplain -directory $tb_seq_dir *.sv] { lappend tb_files $f }

# Environment Packace
foreach f [glob -nocomplain -directory $tb_env_dir/mac *.sv] { lappend tb_files $f }
foreach f [glob -nocomplain -directory $tb_env_dir/dma *.sv] { lappend tb_files $f }
foreach f [glob -nocomplain -directory $tb_env_dir/eth_controller *.sv] { lappend tb_files $f }

# Test Packace
foreach f [glob -nocomplain -directory $tb_tests_dir *.sv] { lappend tb_files $f }

# Testbench
foreach f [glob -nocomplain -directory $tb_top_dir *.sv] { lappend tb_files $f }

puts "Found [llength $tb_files] testbench files"

#-------------------------------------------------------------------------------
# Add Source Files to Project
#-------------------------------------------------------------------------------
puts "Adding source files to project..."

# Add RTL files
if {[llength $rtl_files] > 0} {
    add_files -fileset sim_1 $rtl_files
    foreach f $rtl_files {
        set_property file_type {Verilog} [get_files $f]
    }
}

# Add testbench files
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 $tb_files
    foreach f $tb_files {
        set_property file_type {SystemVerilog} [get_files $f]
    }
}

#-------------------------------------------------------------------------------
# Set Include Directories
#-------------------------------------------------------------------------------
puts "Setting include directories..."

set include_dirs [list \
    $rtl_mac_dir \
    $rtl_phy_dir \
    "$tb_agents_dir/axi_stream/include" \
    "$tb_agents_dir/axi_stream/src" \
    "$tb_agents_dir/axi_stream" \
    "$tb_agents_dir/axi4/include" \
    "$tb_agents_dir/axi4/src" \
    "$tb_agents_dir/axi4" \
    "$tb_agents_dir/axi_lite/include" \
    "$tb_agents_dir/axi_lite/src" \
    "$tb_agents_dir/axi_lite" \
    "$tb_agents_dir/gmii/include" \
    "$tb_agents_dir/gmii/src" \
    "$tb_agents_dir/gmii" \
    "$tb_env_dir/mac/include" \
    "$tb_env_dir/mac/src" \
    "$tb_env_dir/mac" \
    "$tb_env_dir/dma/include" \
    "$tb_env_dir/dma/src" \
    "$tb_env_dir/dma" \
    "$tb_env_dir/eth_controller/include" \
    "$tb_env_dir/eth_controller/src" \
    "$tb_env_dir/eth_controller" \
    "$tb_seq_dir/lib" \
    "$tb_seq_dir/virtual" \
    "$tb_env_dir/mac/include" \
    "$tb_env_dir/mac/src" \
    "$tb_env_dir/mac" \
    "$tb_env_dir/dma/include" \
    "$tb_env_dir/dma/src" \
    "$tb_env_dir/dma" \
    "$tb_env_dir/eth_controller/include" \
    "$tb_env_dir/eth_controller/src" \
    "$tb_env_dir/eth_controller" \
    "$tb_tests_dir" \
    "$tb_tests_dir/src/base" \
    "$tb_tests_dir/src/system_tests" \
    "$tb_tests_dir/src/mac_tests" \
    "$tb_tests_dir/src/dma_tests" \
    $tb_top_dir \
    "$project_root/rtl" \
]

set_property include_dirs $include_dirs [get_filesets sim_1]

#-------------------------------------------------------------------------------
# Set Verilog Defines
#-------------------------------------------------------------------------------
puts "Setting Verilog defines..."

set verilog_defines [list \
    "SIMULATION" \
    "UVM_NO_DPI" \
    "UVM_REGEX_NO_DPI" \
    "UVM_NO_DEPRECATED" \
]

# Check for DEBUG mode from environment variable
if {[info exists ::env(DEBUG_MODE)] && $::env(DEBUG_MODE) == 1} {
    puts "DEBUG mode enabled - adding DEBUG define"
    lappend verilog_defines "DEBUG"
}

set_property verilog_define $verilog_defines [get_filesets sim_1]

#-------------------------------------------------------------------------------
# Set Simulation Properties
#-------------------------------------------------------------------------------
puts "Configuring simulation properties..."

# Set top module
set_property -name top -value $top_module -objects [get_filesets sim_1]
set_property -name top_lib -value work -objects [get_filesets sim_1]

# Enable SystemVerilog
set_property -name {xsim.compile.xvlog.more_options} \
    -value {-sv -L uvm} \
    -objects [get_filesets sim_1]

# Elaboration options
set_property -name {xsim.elaborate.xelab.more_options} \
    -value {-L uvm -debug typical} \
    -objects [get_filesets sim_1]

# Simulation runtime options (default verbosity)
set_property -name {xsim.simulate.runtime} \
    -value {-1} \
    -objects [get_filesets sim_1]

set_property -name {xsim.simulate.xsim.more_options} \
    -value {} \
    -objects [get_filesets sim_1]

#-------------------------------------------------------------------------------
# Update and Compile
#-------------------------------------------------------------------------------
puts "Updating compile order..."
update_compile_order -fileset sim_1

puts "Launching simulation compile..."
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]

# Generate simulation scripts
launch_simulation -scripts_only

puts "=============================================="
puts "Compilation complete!"
puts "Project: $work_dir/$project_name.xpr"
puts "=============================================="

# Save project
# save_project_as $project_name $work_dir -force
# puts "Project Saved"

# Close project
close_project

puts "Done. Use vivado_run.tcl to run simulations."
