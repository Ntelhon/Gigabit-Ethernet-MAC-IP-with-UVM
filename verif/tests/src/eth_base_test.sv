//==============================================================================
// Class: eth_base_test
// Description: Base test class for all Ethernet Controller tests
//
// Purpose:
//   Provides common setup, configuration, and utility methods for all
//   Ethernet Controller verification tests (MAC-only, DMA-only, or full tests).
//
// Features:
//   - Top-level eth_env instantiation
//   - Sub-environment enable/disable control
//   - Clock/reset control
//   - Common register programming sequences
//   - Test timeout handling
//
// Usage:
//   Extend this class for specific test scenarios:
//   - MAC-only tests: enable_dma = 0
//   - DMA-enabled tests: enable_dma = 1
//   - Full controller tests: enable_mac = 1, enable_dma = 1
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim, Xcelium
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

// Include register address definitions
`include "mac_reg_defines.svh"
`include "dma_reg_defines.svh"

class eth_base_test extends uvm_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(eth_base_test)

    //==========================================================================
    // Environment Handle
    //==========================================================================
    eth_env env;

    //==========================================================================
    // Test Configuration
    //==========================================================================
    
    // Sub-environment enables
    bit enable_mac = 1;  // Default: MAC enabled
    bit enable_dma = 0;  // Default: DMA disabled (MAC-only tests)
    
    // Default MAC address for DUT
    bit [47:0] dut_mac_addr = 48'h001122334455;
    
    // Test timeout (in ns)
    int unsigned test_timeout = 100000;
    
    // Test verbosity
    int test_verbosity = UVM_MEDIUM;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "eth_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("ETH_TEST", $sformatf("Building %s", get_type_name()), UVM_LOW)
        
        // Set environment configuration
        uvm_config_db#(bit)::set(this, "env", "enable_mac", enable_mac);
        uvm_config_db#(bit)::set(this, "env", "enable_dma", enable_dma);
        
        // Create top-level environment
        env = eth_env::type_id::create("env", this);
        
        `uvm_info("ETH_TEST", $sformatf("Test Configuration: MAC=%0d, DMA=%0d", 
                  enable_mac, enable_dma), UVM_LOW)
        
    endfunction

    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        // Print test topology
        `uvm_info("ETH_TEST", "==============================================", UVM_LOW)
        `uvm_info("ETH_TEST", $sformatf("  Test: %s", get_type_name()), UVM_LOW)
        `uvm_info("ETH_TEST", "==============================================", UVM_LOW)
        
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
                `uvm_fatal("TIMEOUT", $sformatf("Test timeout of %0d ns reached!", test_timeout))
            end
        join_none
        
    endtask

    //==========================================================================
    // Extract Phase
    //==========================================================================
    virtual function void extract_phase(uvm_phase phase);
        super.extract_phase(phase);
        // Placeholder for coverage extraction
    endfunction

    //==========================================================================
    // Check Phase
    //==========================================================================
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        // Placeholder for additional checks
    endfunction

    //==========================================================================
    // Register Access Helper Methods
    //==========================================================================
    //
    //// Read-Modify-Write register
    //task rmw_reg(bit [31:0] addr, bit [31:0] mask, bit [31:0] value);
    //    eth_base_seq seq;
    //    seq = eth_base_seq::type_id::create("rmw_reg_seq");
    //    seq.rmw_reg(addr, mask, value);
    //    seq.start(env.axi_lite_agt.sequencer);
    //endtask

    //==========================================================================
    // GMII Frame Transmission Helper
    //==========================================================================
    
    //// Send a GMII frame (for test-level use)
    //task send_frame(gmii_frame frame);
    //    gmii_tx_seq seq;
    //    seq = gmii_tx_seq::type_id::create("send_frame_seq");
    //    seq.frame = frame;
    //    seq.start(env.mac_env.gmii_agt.sequencer);
    //endtask
    //
    //// Receive GMII frames (for test-level use)
    //task receive_frames(int expected_frames, ref gmii_frame received_frames[]);
    //    gmii_rx_seq seq;
    //    seq = gmii_rx_seq::type_id::create("receive_frames_seq");
    //    seq.expected_frames = expected_frames;
    //    seq.start(env.mac_env.gmii_agt.sequencer);
    //    received_frames = seq.received_frames;
    //endtask
    //==========================================================================

    //==========================================================================
    // High-Level MAC Configuration Helpers
    //==========================================================================
    //
    //// Clear MAC interrupts
    //task clear_interrupts(bit [31:0] mask = 32'hFFFF_FFFF);
    //    write_reg(ADDR_INT_STATUS, mask);
    //    `uvm_info("ETH_TEST", $sformatf("Cleared interrupts with mask 0x%08h", mask), UVM_HIGH)
    //endtask
    //==========================================================================

    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        uvm_report_server rs;
        int err_count;
        
        super.report_phase(phase);
        
        rs = uvm_report_server::get_server();
        err_count = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
        
        `uvm_info("ETH_TEST", "==============================================", UVM_LOW)
        `uvm_info("ETH_TEST", $sformatf("  Test: %s", get_type_name()), UVM_LOW)
        `uvm_info("ETH_TEST", $sformatf("  Status: %s", (err_count == 0) ? "PASSED" : "FAILED"), UVM_LOW)
        `uvm_info("ETH_TEST", $sformatf("  Errors: %0d", err_count), UVM_LOW)
        `uvm_info("ETH_TEST", "==============================================", UVM_LOW)
        
    endfunction

    //==========================================================================
    // Final Phase
    //==========================================================================
    virtual function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        
        `uvm_info("ETH_TEST", $sformatf("%s complete", get_type_name()), UVM_LOW)
        
    endfunction

endclass : eth_base_test
