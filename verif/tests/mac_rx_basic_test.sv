//==============================================================================
// Test: mac_rx_basic_test
// Description: Basic RX path verification test
//
// Purpose:
//   Verify that the MAC can receive a single Ethernet frame correctly.
//   Checks preamble/SFD detection, frame reception, and CRC verification.
//
// Test Flow:
//   1. Initialize MAC (set MAC address, enable TX/RX)
//   2. Inject a single 64-byte frame on GMII RX interface
//   3. Verify frame is received by MAC
//   4. Check RX frame counter increments
//   5. Scoreboard verifies frame integrity
//
// Pass Criteria:
//   - Frame received correctly after preamble/SFD
//   - FCS verified by MAC (no error)
//   - RX frame counter increments
//   - No UVM errors
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_rx_basic_test extends mac_base_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_rx_basic_test)

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_rx_basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("TEST", "Building mac_rx_basic_test", UVM_LOW)
        
        // Test-specific configuration
        test_timeout = 50000;  // 50us timeout
        
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        mac_init_seq     init_seq;
        mac_rx_basic_seq rx_seq;
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_rx_basic_test running");
        `uvm_info("TEST", "=== Starting mac_rx_basic_test ===", UVM_LOW)
        
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
        // Run RX Basic Sequence - Minimum Size Frame
        //----------------------------------------------------------------------
        rx_seq = mac_rx_basic_seq::type_id::create("rx_seq_min");
        rx_seq.frame_size = 64;  // Minimum frame size
        rx_seq.dst_mac = dut_mac_addr;  // Frame addressed to DUT
        rx_seq.src_mac = 48'hAABBCCDDEEFF;
        rx_seq.start(env.v_sqr);
        
        //----------------------------------------------------------------------
        // Run RX Basic Sequence - Medium Size Frame
        //----------------------------------------------------------------------
        #500ns;
        
        rx_seq = mac_rx_basic_seq::type_id::create("rx_seq_med");
        rx_seq.frame_size = 256;
        rx_seq.dst_mac = dut_mac_addr;
        rx_seq.src_mac = 48'h112233445566;
        rx_seq.start(env.v_sqr);
        
        //----------------------------------------------------------------------
        // Run RX Basic Sequence - Maximum Size Frame
        //----------------------------------------------------------------------
        #1000ns;
        
        rx_seq = mac_rx_basic_seq::type_id::create("rx_seq_max");
        rx_seq.frame_size = 1518;  // Maximum standard frame size
        rx_seq.dst_mac = dut_mac_addr;
        rx_seq.src_mac = 48'hDEADBEEF0000;
        rx_seq.start(env.v_sqr);
        
        //----------------------------------------------------------------------
        // Drain Time
        //----------------------------------------------------------------------
        #2000ns;
        
        `uvm_info("TEST", "=== mac_rx_basic_test Complete ===", UVM_LOW)
        
        // Print scoreboard summary
        env.scb.print_summary();
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_rx_basic_test complete");
        
    endtask

endclass : mac_rx_basic_test
