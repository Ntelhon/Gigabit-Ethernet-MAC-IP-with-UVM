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
        // Interface-specific sequences
        axi_lite_mac_init_seq  init_seq;
        axi_stream_tx_seq      axis_tx_seq;
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_ifg_test running");
        `uvm_info("TEST", "=== Starting mac_ifg_test ===", UVM_LOW)
        
        //----------------------------------------------------------------------
        // Configure Scoreboard for TX-only mode
        //----------------------------------------------------------------------
        env.mac_env.scb.tx_only_mode = 1;
        env.mac_env.scb.expect_loopback = 0;
        
        //----------------------------------------------------------------------
        // Wait for Reset
        //----------------------------------------------------------------------
        #100ns;
        #50ns;
        #5000ns;
        
        //----------------------------------------------------------------------
        // Initialize MAC via AXI-Lite
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Configuring MAC...", UVM_LOW)
        
        init_seq = axi_lite_mac_init_seq::type_id::create("init_seq");
        init_seq.mac_addr = dut_mac_addr;
        init_seq.tx_enable = 1;
        init_seq.rx_enable = 1;
        init_seq.start(mac_sqr.axi_lite_sqr);
        
        #200ns;
        
        //----------------------------------------------------------------------
        // Run IFG Test Sequence (Multiple back-to-back frames)
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Running IFG test with back-to-back frames", UVM_MEDIUM)
        
        // Send 5 frames back-to-back with minimal IFG
        axis_tx_seq = axi_stream_tx_seq::type_id::create("ifg_seq");
        axis_tx_seq.num_frames = 5;
        axis_tx_seq.payload_size = 50;  // 64 byte frames
        axis_tx_seq.dst_mac = 48'hFF_FF_FF_FF_FF_FF;
        axis_tx_seq.src_mac = dut_mac_addr;
        axis_tx_seq.random_payload = 0;
        axis_tx_seq.payload_pattern = 8'hAA;
        axis_tx_seq.include_crc = 0;
        axis_tx_seq.ifg_cycles = 12;  // Minimum IFG (12 byte times = 96 ns)
        
        axis_tx_seq.start(env.mac_env.axis_agt.sequencer);
        
        #5000ns;
        
        //----------------------------------------------------------------------
        // Run Additional Burst with Different IFG
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Running additional IFG burst with larger gap", UVM_MEDIUM)
        
        axis_tx_seq = axi_stream_tx_seq::type_id::create("ifg_seq_2");
        axis_tx_seq.num_frames = 3;
        axis_tx_seq.payload_size = 110;  // 128 byte frames
        axis_tx_seq.dst_mac = 48'hFF_FF_FF_FF_FF_FF;
        axis_tx_seq.src_mac = dut_mac_addr;
        axis_tx_seq.random_payload = 0;
        axis_tx_seq.payload_pattern = 8'h55;
        axis_tx_seq.include_crc = 0;
        axis_tx_seq.ifg_cycles = 24;  // 2x minimum IFG
        
        axis_tx_seq.start(env.mac_env.axis_agt.sequencer);
        
        #5000ns;
        
        //----------------------------------------------------------------------
        // Run Another Burst
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Running final IFG burst", UVM_MEDIUM)
        
        axis_tx_seq = axi_stream_tx_seq::type_id::create("ifg_seq_3");
        axis_tx_seq.num_frames = 4;
        axis_tx_seq.payload_size = 50;
        axis_tx_seq.dst_mac = 48'hFF_FF_FF_FF_FF_FF;
        axis_tx_seq.src_mac = dut_mac_addr;
        axis_tx_seq.random_payload = 1;  // Random payload
        axis_tx_seq.include_crc = 0;
        axis_tx_seq.ifg_cycles = 12;
        
        axis_tx_seq.start(env.mac_env.axis_agt.sequencer);
        
        //----------------------------------------------------------------------
        // Drain Time
        //----------------------------------------------------------------------
        #2000ns;
        
        `uvm_info("TEST", "=== mac_ifg_test Complete ===", UVM_LOW)
        `uvm_info("TEST", "Note: IFG timing verified by GMII monitor", UVM_MEDIUM)
        
        // Print scoreboard summary
        env.mac_env.scb.print_summary();
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_ifg_test complete");
        
    endtask

endclass : mac_ifg_test
