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
#   vivado -mode batch -source vivado_compile.tcl -tclargs -top tb_top
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
set top_module "tb_top"
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
set rtl_phy_dir    "$project_root/rtl/phy_if"
set rtl_dma_dir    "$project_root/rtl/dma"
set tb_if_dir      "$project_root/verif/interfaces"
set tb_agents_dir  "$project_root/verif/agents"
set tb_env_dir     "$project_root/verif/env"
set tb_scb_dir     "$project_root/verif/scoreboard"
set tb_seq_dir     "$project_root/verif/sequences"
set tb_tests_dir   "$project_root/verif/tests"
set tb_top_dir     "$project_root/verif/tb"

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

# PHY Interface RTL
foreach f [glob -nocomplain -directory $rtl_phy_dir *.v] {
    lappend rtl_files $f
}

# DMA RTL (if exists)
if {[file exists $rtl_dma_dir]} {
    foreach f [glob -nocomplain -directory $rtl_dma_dir *.v] {
        lappend rtl_files $f
    }
}

puts "Found [llength $rtl_files] RTL files"

#-------------------------------------------------------------------------------
# Collect Testbench Source Files (SystemVerilog)
#-------------------------------------------------------------------------------
puts "Collecting testbench sources..."

set tb_files [list]

# CRITICAL: Add axi_mm_if first (must be before packages that use it)
set axi_mm_if_file "$tb_if_dir/axi_mm_if.sv"
if {[file exists $axi_mm_if_file]} {
    lappend tb_files $axi_mm_if_file
    puts "Added axi_mm_if.sv first"
}

# Then add other interfaces
set axi_lite_if_file "$tb_if_dir/axi_lite_if.sv"
if {[file exists $axi_lite_if_file]} {
    lappend tb_files $axi_lite_if_file
}

set axi_stream_if_file "$tb_if_dir/axi_stream_if.sv"
if {[file exists $axi_stream_if_file]} {
    lappend tb_files $axi_stream_if_file
}

set gmii_if_file "$tb_if_dir/gmii_if.sv"
if {[file exists $gmii_if_file]} {
    lappend tb_files $gmii_if_file
}

# 2. Agent packages (no cross-dependencies)
set axi_pkg_file "$tb_agents_dir/axi_lite_agent/axi_lite_agent_pkg.sv"
if {[file exists $axi_pkg_file]} {
    lappend tb_files $axi_pkg_file
}

set axi_mm_pkg_file "$tb_agents_dir/axi_mm_agent/axi_mm_agent_pkg.sv"
if {[file exists $axi_mm_pkg_file]} {
    lappend tb_files $axi_mm_pkg_file
}

set gmii_pkg_file "$tb_agents_dir/gmii_agent/gmii_agent_pkg.sv"
if {[file exists $gmii_pkg_file]} {
    lappend tb_files $gmii_pkg_file
}

# 3. AXI-Stream agent package
set axis_pkg_file "$tb_agents_dir/axi_stream_agent/axi_stream_agent_pkg.sv"
if {[file exists $axis_pkg_file]} {
    lappend tb_files $axis_pkg_file
}

# 4. Scoreboard packages (new structure)
# MAC scoreboard
set mac_scb_pkg_file "$project_root/verif/scoreboards/mac_scoreboard/mac_scoreboard_pkg.sv"
if {[file exists $mac_scb_pkg_file]} {
    lappend tb_files $mac_scb_pkg_file
    puts "Added MAC scoreboard package"
}

# DMA scoreboard
set dma_scb_pkg_file "$project_root/verif/scoreboards/dma_scoreboard/dma_scoreboard_pkg.sv"
if {[file exists $dma_scb_pkg_file]} {
    lappend tb_files $dma_scb_pkg_file
    puts "Added DMA scoreboard package"
}

# 5. Interface-specific sequence library packages
# AXI-Lite sequences (register access)
set axi_lite_seq_pkg_file "$project_root/verif/sequences/axi_lite_seq_lib/axi_lite_seq_lib_pkg.sv"
if {[file exists $axi_lite_seq_pkg_file]} {
    lappend tb_files $axi_lite_seq_pkg_file
    puts "Added AXI-Lite sequence library"
}

# GMII sequences (frame injection)
set gmii_seq_pkg_file "$project_root/verif/sequences/gmii_seq_lib/gmii_seq_lib_pkg.sv"
if {[file exists $gmii_seq_pkg_file]} {
    lappend tb_files $gmii_seq_pkg_file
    puts "Added GMII sequence library"
}

# AXI-Stream sequences (data transfer)
set axis_seq_pkg_file "$project_root/verif/sequences/axi_stream_seq_lib/axi_stream_seq_lib_pkg.sv"
if {[file exists $axis_seq_pkg_file]} {
    lappend tb_files $axis_seq_pkg_file
    puts "Added AXI-Stream sequence library"
}

# 6. Sub-environment packages
# MAC sub-environment
set mac_sub_env_pkg_file "$project_root/verif/env/mac_sub_env/mac_sub_env_pkg.sv"
if {[file exists $mac_sub_env_pkg_file]} {
    lappend tb_files $mac_sub_env_pkg_file
    puts "Added MAC sub-environment package"
}

# DMA sub-environment
set dma_sub_env_pkg_file "$project_root/verif/env/dma_sub_env/dma_sub_env_pkg.sv"
if {[file exists $dma_sub_env_pkg_file]} {
    lappend tb_files $dma_sub_env_pkg_file
    puts "Added DMA sub-environment package"
}

# 7. Top-level environment package
set eth_env_pkg_file "$tb_env_dir/eth_env_pkg.sv"
if {[file exists $eth_env_pkg_file]} {
    lappend tb_files $eth_env_pkg_file
    puts "Added top-level environment package"
}

# 8. Test package (depends on environment and sequences)
set test_pkg_file "$tb_tests_dir/eth_test_pkg.sv"
if {[file exists $test_pkg_file]} {
    lappend tb_files $test_pkg_file
    puts "Added test package"
}

# Testbench top
foreach f [glob -nocomplain -directory $tb_top_dir *.sv] {
    lappend tb_files $f
}

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
    $rtl_dma_dir \
    $tb_if_dir \
    "$tb_agents_dir/gmii_agent" \
    "$tb_agents_dir/axi_lite_agent" \
    "$tb_agents_dir/axi_stream_agent" \
    "$tb_agents_dir/axi_mm_agent" \
    "$project_root/verif/scoreboards/mac_scoreboard/src" \
    "$project_root/verif/scoreboards/dma_scoreboard/src" \
    "$project_root/verif/sequences/gmii_seq_lib" \
    "$project_root/verif/sequences/mac_seq_lib" \
    "$project_root/verif/sequences/dma_seq_lib" \
    "$project_root/verif/env/mac_sub_env" \
    "$project_root/verif/env/dma_sub_env" \
    "$project_root/verif/tests/src" \
    $tb_env_dir \
    $tb_tests_dir \
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

# Set compile order to manual to preserve our ordering
set_property source_mgmt_mode None [current_project]

# Update compile order to resolve dependencies properly
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
