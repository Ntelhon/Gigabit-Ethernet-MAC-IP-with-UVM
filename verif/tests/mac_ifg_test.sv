//==============================================================================
// Test: mac_ifg_test
// Description: Inter-Frame Gap (IFG) verification test
//
// Purpose:
//   Verify that the MAC maintains proper Inter-Frame Gap timing between
//   consecutive transmitted frames. Per IEEE 802.3, minimum IFG is 96 bit
//   times (12 bytes at 1 Gbps = 96 ns).
//
// Test Flow:
//   1. Initialize MAC (set MAC address, enable TX/RX)
//   2. Send multiple back-to-back frames
//   3. Monitor observes timing between frames
//   4. Verify IFG >= 96 bit times (12 byte times at GMII)
//   5. Check all frames transmitted successfully
//
// Pass Criteria:
//   - All frames transmitted
//   - IFG between frames >= 12 GMII clock cycles
//   - Proper preamble/SFD on each frame
//   - No UVM errors
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_ifg_test extends mac_base_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_ifg_test)

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_ifg_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("TEST", "Building mac_ifg_test", UVM_LOW)
        
        // Test-specific configuration
        test_timeout = 100000;  // 100us timeout (multiple frames)
        
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        mac_init_seq     init_seq;
        mac_ifg_test_seq ifg_seq;
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_ifg_test running");
        `uvm_info("TEST", "=== Starting mac_ifg_test ===", UVM_LOW)
        
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
        // Run IFG Test Sequence (2 back-to-back frames)
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Running IFG test with back-to-back frames", UVM_MEDIUM)
        ifg_seq = mac_ifg_test_seq::type_id::create("ifg_seq");
        ifg_seq.start(env.v_sqr);
        
        #1000ns;
        
        //----------------------------------------------------------------------
        // Run Multiple Bursts
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Running additional IFG burst", UVM_MEDIUM)
        ifg_seq = mac_ifg_test_seq::type_id::create("ifg_seq_2");
        ifg_seq.start(env.v_sqr);
        
        #1000ns;
        
        ifg_seq = mac_ifg_test_seq::type_id::create("ifg_seq_3");
        ifg_seq.start(env.v_sqr);
        
        //----------------------------------------------------------------------
        // Drain Time
        //----------------------------------------------------------------------
        #2000ns;
        
        `uvm_info("TEST", "=== mac_ifg_test Complete ===", UVM_LOW)
        `uvm_info("TEST", "Note: IFG timing verified by GMII monitor", UVM_MEDIUM)
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_ifg_test complete");
        
    endtask

endclass : mac_ifg_test
