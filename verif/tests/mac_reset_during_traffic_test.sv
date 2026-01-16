//==============================================================================
// Test: mac_reset_during_traffic_test
// Description: Reset assertion during active traffic test
//
// Purpose:
//   Verify that the MAC correctly handles reset assertion during active
//   frame transmission or reception. After reset, MAC should:
//   - Abort current frame gracefully
//   - Clear all state machines
//   - Be able to restart normal operation
//
// Test Flow:
//   1. Initialize MAC (set MAC address, enable TX/RX)
//   2. Start frame transmission
//   3. Assert reset mid-frame
//   4. Deassert reset
//   5. Verify MAC responds to register reads
//   6. Re-initialize MAC
//   7. Verify normal operation with new frame
//
// Pass Criteria:
//   - MAC enters reset state
//   - Control registers cleared after reset
//   - MAC is operational after reset
//   - New frames transmit/receive correctly
//   - No UVM errors (hung states)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_reset_during_traffic_test extends mac_base_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_reset_during_traffic_test)

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_reset_during_traffic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("TEST", "Building mac_reset_during_traffic_test", UVM_LOW)
        
        // Test-specific configuration
        test_timeout = 80000;  // 80us timeout
        
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        mac_init_seq                 init_seq;
        mac_reset_during_traffic_seq reset_seq;
        mac_rx_basic_seq             rx_seq;
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_reset_during_traffic_test running");
        `uvm_info("TEST", "=== Starting mac_reset_during_traffic_test ===", UVM_LOW)
        
        //----------------------------------------------------------------------
        // Wait for Reset
        //----------------------------------------------------------------------
        #100ns;
        
        //----------------------------------------------------------------------
        // Initialize MAC
        //----------------------------------------------------------------------
        init_seq = mac_init_seq::type_id::create("init_seq");
        init_seq.mac_addr = dut_mac_addr;
        init_seq.tx_enable = 1;
        init_seq.rx_enable = 1;
        init_seq.start(env.v_sqr);
        
        #200ns;
        
        //----------------------------------------------------------------------
        // Run Reset-During-Traffic Sequence
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Running reset-during-traffic sequence", UVM_MEDIUM)
        reset_seq = mac_reset_during_traffic_seq::type_id::create("reset_seq");
        reset_seq.start(env.v_sqr);
        
        #500ns;
        
        //----------------------------------------------------------------------
        // Verify Normal Operation Post-Reset with additional frames
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Verifying stable RX operation after reset", UVM_MEDIUM)
        rx_seq = mac_rx_basic_seq::type_id::create("post_reset_rx");
        rx_seq.frame_size = 64;
        rx_seq.dst_mac = dut_mac_addr;
        rx_seq.src_mac = 48'hAABBCCDDEEFF;
        rx_seq.start(env.v_sqr);
        
        //----------------------------------------------------------------------
        // Send Another Frame to Confirm Stable Operation
        //----------------------------------------------------------------------
        #500ns;
        
        rx_seq = mac_rx_basic_seq::type_id::create("stable_rx");
        rx_seq.frame_size = 128;
        rx_seq.dst_mac = dut_mac_addr;
        rx_seq.src_mac = 48'h112233445566;
        rx_seq.start(env.v_sqr);
        
        //----------------------------------------------------------------------
        // Drain Time
        //----------------------------------------------------------------------
        #1000ns;
        
        `uvm_info("TEST", "=== mac_reset_during_traffic_test Complete ===", UVM_LOW)
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_reset_during_traffic_test complete");
        
    endtask

endclass : mac_reset_during_traffic_test
