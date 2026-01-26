#===============================================================================
# File: vivado_run.tcl
# Description: Vivado xsim simulation run script for UVM tests
#
# Purpose:
#   Runs UVM tests using xsim with configurable test name, verbosity,
#   and waveform dumping.
#
# Usage:
#   vivado -mode batch -source vivado_run.tcl -tclargs -test mac_tx_basic_test
#   vivado -mode batch -source vivado_run.tcl -tclargs -test mac_rx_basic_test -verbosity UVM_HIGH
#   vivado -mode batch -source vivado_run.tcl -tclargs -test mac_crc_error_test -waves
#
# Arguments:
#   -test <name>      : UVM test name (required)
#   -verbosity <lvl>  : UVM verbosity (UVM_NONE/LOW/MEDIUM/HIGH/FULL/DEBUG)
#   -waves            : Enable waveform dumping
#   -seed <value>     : Random seed (default: 1)
#   -timeout <ns>     : Simulation timeout in ns (default: 1000000)
#   -gui              : Open GUI after simulation
#
# Author: AI-IP Generator
# License: MIT
#===============================================================================

#-------------------------------------------------------------------------------
# Default Parameters
#-------------------------------------------------------------------------------
set test_name      ""
set verbosity      "UVM_MEDIUM"
set enable_waves   0
set random_seed    1
set sim_timeout    1000000
set open_gui       0
set project_name   "mac_sim"
set top_module     "eth_tb_top"

#-------------------------------------------------------------------------------
# Parse Command Line Arguments
#-------------------------------------------------------------------------------
for {set i 0} {$i < $argc} {incr i} {
    set arg [lindex $argv $i]
    switch -exact -- $arg {
        "-test" {
            incr i
            set test_name [lindex $argv $i]
        }
        "-verbosity" {
            incr i
            set verbosity [lindex $argv $i]
        }
        "-waves" {
            set enable_waves 1
        }
        "-seed" {
            incr i
            set random_seed [lindex $argv $i]
        }
        "-timeout" {
            incr i
            set sim_timeout [lindex $argv $i]
        }
        "-gui" {
            set open_gui 1
        }
        "-project" {
            incr i
            set project_name [lindex $argv $i]
        }
    }
}

#-------------------------------------------------------------------------------
# Validate Required Arguments
#-------------------------------------------------------------------------------
if {$test_name eq ""} {
    puts "=============================================="
    puts "ERROR: Test name required!"
    puts ""
    puts "Usage: vivado -mode batch -source vivado_run.tcl -tclargs -test <test_name>"
    puts ""
    puts "Available tests:"
    puts "  mac_tx_basic_test"
    puts "  mac_rx_basic_test"
    puts "  mac_crc_error_test"
    puts "  mac_runt_frame_test"
    puts "  mac_ifg_test"
    puts "  mac_reset_during_traffic_test"
    puts ""
    puts "Options:"
    puts "  -verbosity <UVM_NONE|UVM_LOW|UVM_MEDIUM|UVM_HIGH|UVM_FULL|UVM_DEBUG>"
    puts "  -waves           : Dump waveforms to WDB file"
    puts "  -seed <value>    : Set random seed"
    puts "  -timeout <ns>    : Simulation timeout"
    puts "  -gui             : Open waveform viewer after simulation"
    puts "=============================================="
    exit 1
}

#-------------------------------------------------------------------------------
# Directory Setup
#-------------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize "$script_dir/../.."]
set sim_dir "$project_root/sim/vivado"
set work_dir "$sim_dir/work"
set results_dir "$sim_dir/results"
set log_dir "$results_dir/$test_name"

# Create results directory
file mkdir $log_dir

#-------------------------------------------------------------------------------
# Print Configuration
#-------------------------------------------------------------------------------
puts "=============================================="
puts "Vivado xsim Simulation Run Script"
puts "=============================================="
puts "Test Name:   $test_name"
puts "Verbosity:   $verbosity"
puts "Waves:       [expr {$enable_waves ? "Enabled" : "Disabled"}]"
puts "Seed:        $random_seed"
puts "Timeout:     $sim_timeout ns"
puts "Results Dir: $log_dir"
puts "=============================================="

#-------------------------------------------------------------------------------
# Open Project
#-------------------------------------------------------------------------------
set project_file "$work_dir/${project_name}.xpr"

if {![file exists $project_file]} {
    puts "ERROR: Project file not found: $project_file"
    puts "Please run vivado_compile.tcl first."
    exit 1
}

puts "Opening project: $project_file"
open_project $project_file

#-------------------------------------------------------------------------------
# Configure UVM Test Parameters
#-------------------------------------------------------------------------------
puts "Configuring UVM test parameters..."

# Build UVM plusargs
set uvm_plusargs "+UVM_TESTNAME=$test_name +UVM_VERBOSITY=$verbosity"

# Add seed
append uvm_plusargs " +UVM_SEED=$random_seed"

# Add timeout
append uvm_plusargs " +UVM_TIMEOUT=$sim_timeout"

# Set xsim runtime options
set xsim_options "-testplusarg UVM_TESTNAME=$test_name"
append xsim_options " -testplusarg UVM_VERBOSITY=$verbosity"
append xsim_options " -sv_seed $random_seed"

# Waveform options
if {$enable_waves} {
    append xsim_options " -wdb $log_dir/${test_name}.wdb"
    set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]
} else {
    set_property -name {xsim.simulate.log_all_signals} -value {false} -objects [get_filesets sim_1]
}

set_property -name {xsim.simulate.xsim.more_options} \
    -value $xsim_options \
    -objects [get_filesets sim_1]

#-------------------------------------------------------------------------------
# Run Simulation
#-------------------------------------------------------------------------------
puts "Launching simulation..."
set start_time [clock seconds]

# Launch simulation
if {[catch {
    launch_simulation
    
    # Run simulation
    run all
    
    # Close simulation to ensure logs are flushed
    close_sim
    
} err]} {
    puts "=============================================="
    puts "SIMULATION ERROR: $err"
    puts "=============================================="
}

set end_time [clock seconds]
set elapsed [expr {$end_time - $start_time}]

#-------------------------------------------------------------------------------
# Collect Results
#-------------------------------------------------------------------------------
puts ""
puts "=============================================="
puts "Simulation Complete"
puts "=============================================="
puts "Elapsed Time: $elapsed seconds"
puts "Log Dir:      $log_dir"

# Copy log files to results directory
# simulate.log contains simulation (UVM) output
if {[file exists "$work_dir/${project_name}.sim/sim_1/behav/xsim/simulate.log"]} {
    file copy -force \
        "$work_dir/${project_name}.sim/sim_1/behav/xsim/simulate.log" \
        "$log_dir/simulate.log"
    puts "Simulation log: $log_dir/simulate.log"
}

# elaborate.log contains compilation output
if {[file exists "$work_dir/${project_name}.sim/sim_1/behav/xsim/elaborate.log"]} {
    file copy -force \
        "$work_dir/${project_name}.sim/sim_1/behav/xsim/elaborate.log" \
        "$log_dir/elaborate.log"
}

# xvlog.log contains analysis output  
if {[file exists "$work_dir/${project_name}.sim/sim_1/behav/xsim/xvlog.log"]} {
    file copy -force \
        "$work_dir/${project_name}.sim/sim_1/behav/xsim/xvlog.log" \
        "$log_dir/compile.log"
}

if {$enable_waves} {
    puts "Waveform file:  $log_dir/${test_name}.wdb"
}

#-------------------------------------------------------------------------------
# Check Results
#-------------------------------------------------------------------------------
puts ""
puts "Checking results..."

# Parse log for UVM results
set log_file "$log_dir/simulate.log"
set result_status "UNKNOWN"
set err_count 0
set warn_count 0

if {[file exists $log_file]} {
    set fp [open $log_file r]
    set log_content [read $fp]
    close $fp
    
    # Check for test pass/fail
    if {[regexp {TEST PASSED} $log_content]} {
        set result_status "PASSED"
        puts "=============================================="
        puts "       *** TEST PASSED ***"
        puts "=============================================="
    } elseif {[regexp {TEST FAILED} $log_content]} {
        set result_status "FAILED"
        puts "=============================================="
        puts "       *** TEST FAILED ***"
        puts "=============================================="
    } elseif {[regexp {UVM_FATAL} $log_content]} {
        set result_status "FATAL"
        puts "=============================================="
        puts "       *** TEST FAILED (UVM_FATAL) ***"
        puts "=============================================="
    } else {
        puts "=============================================="
        puts "       *** TEST RESULT UNKNOWN ***"
        puts "=============================================="
    }
    
    # Extract error/warning counts
    if {[regexp {UVM_ERROR\s*:\s*(\d+)} $log_content match cnt]} {
        set err_count $cnt
        puts "UVM Errors:   $err_count"
    }
    if {[regexp {UVM_WARNING\s*:\s*(\d+)} $log_content match cnt]} {
        set warn_count $cnt
        puts "UVM Warnings: $warn_count"
    }
}

#-------------------------------------------------------------------------------
# Write Summary File
#-------------------------------------------------------------------------------
set summary_file "$log_dir/summary.txt"
set fp [open $summary_file w]
puts $fp "==============================================================================="
puts $fp "Test Summary"
puts $fp "==============================================================================="
puts $fp "Test Name:    $test_name"
puts $fp "Result:       $result_status"
puts $fp "UVM Errors:   $err_count"
puts $fp "UVM Warnings: $warn_count"
puts $fp "Elapsed Time: $elapsed seconds"
puts $fp "Seed:         $random_seed"
puts $fp "Verbosity:    $verbosity"
puts $fp "==============================================================================="
puts $fp ""
puts $fp "Output Files:"
puts $fp "  simulate.log  - Raw simulation output (includes xsim messages)"
puts $fp "  uvm_output.log - Clean UVM messages only"
puts $fp "  compile.log   - Compilation/analysis output"
puts $fp "  elaborate.log - Elaboration output"
if {$enable_waves} {
    puts $fp "  ${test_name}.wdb - Waveform database"
}
puts $fp "==============================================================================="
close $fp
puts "Summary:        $log_dir/summary.txt"

#-------------------------------------------------------------------------------
# Open GUI (Optional)
#-------------------------------------------------------------------------------
if {$open_gui && $enable_waves} {
    puts "Opening waveform viewer..."
    open_wave_database "$log_dir/${test_name}.wdb"
} else {
    close_project
    puts "Done."
}
