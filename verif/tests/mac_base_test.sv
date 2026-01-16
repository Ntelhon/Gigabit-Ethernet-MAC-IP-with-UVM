//==============================================================================
// Class: mac_base_test
// Description: Base test class for all MAC directed tests
//
// Purpose:
//   Provides common setup, configuration, and utility methods for all
//   MAC verification tests.
//
// Features:
//   - Environment instantiation
//   - Clock/reset control
//   - Common register programming sequences
//   - Test timeout handling
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_base_test extends uvm_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_base_test)

    //==========================================================================
    // Environment Handle
    //==========================================================================
    mac_env env;

    //==========================================================================
    // Test Configuration
    //==========================================================================
    
    // Default MAC address for DUT
    bit [47:0] dut_mac_addr = 48'h001122334455;
    
    // Test timeout (in ns)
    int unsigned test_timeout = 100000;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("TEST", "Building MAC base test", UVM_MEDIUM)
        
        // Create environment
        env = mac_env::type_id::create("env", this);
        
    endfunction

    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        // Print test topology
        uvm_top.print_topology();
        
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        
        // Fork timeout watchdog - will be killed when phase ends
        fork
            begin
                #(test_timeout * 1ns);
                `uvm_fatal("TIMEOUT", $sformatf("Test timeout after %0d ns", test_timeout))
            end
            begin
                // Wait for phase to end, then disable the timeout
                phase.wait_for_state(UVM_PHASE_ENDED, UVM_GTE);
            end
        join_any
        disable fork;
        
    endtask

    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        uvm_report_server srv;
        int unsigned err_cnt;
        
        super.report_phase(phase);
        
        srv = uvm_report_server::get_server();
        err_cnt = srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL);
        
        `uvm_info("TEST", "========================================", UVM_NONE)
        if (err_cnt == 0) begin
            `uvm_info("TEST", "           TEST PASSED", UVM_NONE)
        end else begin
            `uvm_info("TEST", $sformatf("           TEST FAILED (%0d errors)", err_cnt), UVM_NONE)
        end
        `uvm_info("TEST", "========================================", UVM_NONE)
        
    endfunction

endclass : mac_base_test
