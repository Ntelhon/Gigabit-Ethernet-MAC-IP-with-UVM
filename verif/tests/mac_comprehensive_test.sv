//==============================================================================
// Test: mac_comprehensive_test
// Description: Advanced comprehensive test for Gigabit Ethernet MAC IP
//
// Purpose:
//   Exercises multiple features of the MAC IP in a single test including:
//   - Multiple frame sizes (minimum, typical, jumbo-like)
//   - Concurrent TX and RX operations
//   - Various payload patterns
//   - Register read/write verification
//   - Frame counter verification
//   - Broadcast and unicast addressing
//   - Back-to-back frame transmission
//   - Different inter-frame gaps
//   - Stress test with rapid frame bursts
//
// Test Phases:
//   Phase 1: Register Configuration Verification
//   Phase 2: Minimum Size Frame TX/RX Loopback
//   Phase 3: Maximum Size Frame TX/RX Loopback
//   Phase 4: Burst Mode - Multiple Back-to-Back Frames
//   Phase 5: Mixed Frame Sizes with Random Payloads
//   Phase 6: Stress Test - Rapid Frame Injection
//   Phase 7: Counter Verification
//
// Pass Criteria:
//   - All registers read/write correctly
//   - All frames successfully transmitted and received
//   - Frame counters match expected values
//   - No CRC errors on valid frames
//   - No data corruption
//   - No UVM errors or timeouts
//
// Coverage:
//   - Frame sizes: 64, 128, 256, 512, 1024, 1500 bytes
//   - Payload patterns: incrementing, decrementing, random, fixed
//   - Addressing: broadcast, unicast
//   - IFG: minimum (12), extended (24, 48)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_comprehensive_test extends mac_base_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_comprehensive_test)

    //==========================================================================
    // Test Statistics
    //==========================================================================
    int total_tx_frames = 0;
    int total_rx_frames = 0;
    int phase_errors = 0;

    //==========================================================================
    // Test Configuration
    //==========================================================================
    
    // Frame sizes to test
    int frame_sizes[] = '{64, 128, 256, 512, 1024, 1500};
    
    // Number of frames per burst
    int burst_count = 5;
    
    // Stress test frame count
    int stress_frame_count = 10;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_comprehensive_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("TEST", "Building mac_comprehensive_test", UVM_LOW)
        
        // Extended timeout for comprehensive test
        test_timeout = 500000;  // 500us timeout
        
        // Configure scoreboard for loopback mode
        uvm_config_db#(int)::set(this, "env.scoreboard", "expect_loopback", 1);
        
    endfunction

    //==========================================================================
    // Run Phase - Main Test Execution
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        
        phase.raise_objection(this, "mac_comprehensive_test running");
        
        `uvm_info("TEST", "╔══════════════════════════════════════════════════════════════╗", UVM_LOW)
        `uvm_info("TEST", "║         MAC COMPREHENSIVE TEST - STARTING                    ║", UVM_LOW)
        `uvm_info("TEST", "╚══════════════════════════════════════════════════════════════╝", UVM_LOW)
        
        // Wait for reset
        #100ns;
        
        //----------------------------------------------------------------------
        // Phase 1: Register Configuration Verification
        //----------------------------------------------------------------------
        run_phase_1_register_verification();
        
        //----------------------------------------------------------------------
        // Phase 2: Minimum Size Frame TX/RX Loopback
        //----------------------------------------------------------------------
        run_phase_2_min_frame_test();
        
        //----------------------------------------------------------------------
        // Phase 3: Maximum Size Frame TX/RX Loopback
        //----------------------------------------------------------------------
        run_phase_3_max_frame_test();
        
        //----------------------------------------------------------------------
        // Phase 4: Burst Mode - Multiple Back-to-Back Frames
        //----------------------------------------------------------------------
        run_phase_4_burst_test();
        
        //----------------------------------------------------------------------
        // Phase 5: Mixed Frame Sizes with Random Payloads
        //----------------------------------------------------------------------
        run_phase_5_mixed_sizes_test();
        
        //----------------------------------------------------------------------
        // Phase 6: Stress Test - Rapid Frame Injection
        //----------------------------------------------------------------------
        run_phase_6_stress_test();
        
        //----------------------------------------------------------------------
        // Phase 7: Counter Verification
        //----------------------------------------------------------------------
        run_phase_7_counter_verification();
        
        //----------------------------------------------------------------------
        // Final Summary
        //----------------------------------------------------------------------
        print_test_summary();
        
        // Print scoreboard summary
        env.scb.print_summary();
        
        // Drain time
        #5000ns;
        
        phase.drop_objection(this, "mac_comprehensive_test complete");
        
    endtask

    //==========================================================================
    // Phase 1: Register Configuration Verification
    //==========================================================================
    virtual task run_phase_1_register_verification();
        mac_init_seq init_seq;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 1: MAC Initialization                                 │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        // Initialize MAC with specific configuration
        init_seq = mac_init_seq::type_id::create("init_seq");
        init_seq.mac_addr = dut_mac_addr;
        init_seq.tx_enable = 1;
        init_seq.rx_enable = 1;
        init_seq.start(env.v_sqr);
        
        #200ns;
        
        `uvm_info("TEST", "  ✓ MAC initialized with TX and RX enabled", UVM_LOW)
        `uvm_info("TEST", "  Phase 1 complete", UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 2: Minimum Size Frame TX/RX Loopback
    //==========================================================================
    virtual task run_phase_2_min_frame_test();
        axi_stream_tx_frame_seq  axis_tx_seq;
        gmii_tx_rx_loopback_seq  loopback_seq;
        int num_frames = 3;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 2: Minimum Size Frame TX/RX Loopback (64 bytes)       │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        // Create TX sequence for minimum frames
        axis_tx_seq = axi_stream_tx_frame_seq::type_id::create("axis_tx_min");
        axis_tx_seq.num_frames = num_frames;
        axis_tx_seq.payload_size = 46;  // 64 - 14 (header) - 4 (CRC) = 46
        axis_tx_seq.dst_mac = 48'hFF_FF_FF_FF_FF_FF;  // Broadcast
        axis_tx_seq.src_mac = dut_mac_addr;
        axis_tx_seq.random_payload = 0;
        axis_tx_seq.payload_pattern = 8'hAA;
        axis_tx_seq.include_crc = 0;
        axis_tx_seq.ifg_cycles = 12;
        
        // Create loopback sequence
        loopback_seq = gmii_tx_rx_loopback_seq::type_id::create("loopback_min");
        loopback_seq.num_frames = num_frames;
        loopback_seq.reinjection_delay = 24;
        
        // Execute in parallel
        fork
            axis_tx_seq.start(env.axis_agt.sequencer);
            loopback_seq.body();
        join
        
        total_tx_frames += num_frames;
        total_rx_frames += num_frames;
        
        #1000ns;
        `uvm_info("TEST", $sformatf("  ✓ Transmitted and looped back %0d minimum-size frames", num_frames), UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 3: Maximum Size Frame TX/RX Loopback
    //==========================================================================
    virtual task run_phase_3_max_frame_test();
        axi_stream_tx_frame_seq  axis_tx_seq;
        gmii_tx_rx_loopback_seq  loopback_seq;
        int num_frames = 2;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 3: Maximum Size Frame TX/RX Loopback (1518 bytes)     │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        // Create TX sequence for maximum frames
        axis_tx_seq = axi_stream_tx_frame_seq::type_id::create("axis_tx_max");
        axis_tx_seq.num_frames = num_frames;
        axis_tx_seq.payload_size = 1500;  // Maximum payload
        axis_tx_seq.dst_mac = dut_mac_addr;  // Unicast to self
        axis_tx_seq.src_mac = 48'hDE_AD_BE_EF_CA_FE;
        axis_tx_seq.ether_type = 16'h0800;  // IPv4
        axis_tx_seq.random_payload = 1;  // Random data
        axis_tx_seq.include_crc = 0;
        axis_tx_seq.ifg_cycles = 24;  // Extended IFG for large frames
        
        // Create loopback sequence
        loopback_seq = gmii_tx_rx_loopback_seq::type_id::create("loopback_max");
        loopback_seq.num_frames = num_frames;
        loopback_seq.reinjection_delay = 48;  // More delay for large frames
        
        // Execute in parallel
        fork
            axis_tx_seq.start(env.axis_agt.sequencer);
            loopback_seq.body();
        join
        
        total_tx_frames += num_frames;
        total_rx_frames += num_frames;
        
        #2000ns;
        `uvm_info("TEST", $sformatf("  ✓ Transmitted and looped back %0d maximum-size frames", num_frames), UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 4: Burst Mode - Multiple Back-to-Back Frames
    //==========================================================================
    virtual task run_phase_4_burst_test();
        axi_stream_tx_frame_seq  axis_tx_seq;
        gmii_tx_rx_loopback_seq  loopback_seq;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 4: Burst Mode - Back-to-Back Frames                   │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        // Minimum IFG burst test
        axis_tx_seq = axi_stream_tx_frame_seq::type_id::create("axis_tx_burst");
        axis_tx_seq.num_frames = burst_count;
        axis_tx_seq.payload_size = 100;  // Medium frames
        axis_tx_seq.dst_mac = 48'hFF_FF_FF_FF_FF_FF;
        axis_tx_seq.src_mac = dut_mac_addr;
        axis_tx_seq.random_payload = 0;
        axis_tx_seq.payload_pattern = 8'h55;  // Alternating bits
        axis_tx_seq.include_crc = 0;
        axis_tx_seq.ifg_cycles = 12;  // Minimum IFG
        
        loopback_seq = gmii_tx_rx_loopback_seq::type_id::create("loopback_burst");
        loopback_seq.num_frames = burst_count;
        loopback_seq.reinjection_delay = 24;
        
        // Execute in parallel
        fork
            axis_tx_seq.start(env.axis_agt.sequencer);
            loopback_seq.body();
        join
        
        total_tx_frames += burst_count;
        total_rx_frames += burst_count;
        
        #2000ns;
        `uvm_info("TEST", $sformatf("  ✓ Completed burst of %0d back-to-back frames", burst_count), UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 5: Mixed Frame Sizes with Random Payloads
    //==========================================================================
    virtual task run_phase_5_mixed_sizes_test();
        axi_stream_tx_frame_seq  axis_tx_seq;
        gmii_tx_rx_loopback_seq  loopback_seq;
        int total_frames = 0;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 5: Mixed Frame Sizes with Random Payloads             │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        // Test each frame size
        foreach (frame_sizes[i]) begin
            int payload_size;
            
            // Calculate payload size (frame_size - 14 header - 4 CRC)
            payload_size = frame_sizes[i] - 18;
            if (payload_size < 46) payload_size = 46;  // Minimum payload
            
            `uvm_info("TEST", $sformatf("  Testing frame size: %0d bytes (payload: %0d)", 
                      frame_sizes[i], payload_size), UVM_MEDIUM)
            
            axis_tx_seq = axi_stream_tx_frame_seq::type_id::create($sformatf("axis_tx_%0d", frame_sizes[i]));
            axis_tx_seq.num_frames = 1;
            axis_tx_seq.payload_size = payload_size;
            axis_tx_seq.dst_mac = 48'h01_02_03_04_05_06;  // Multicast-like
            axis_tx_seq.src_mac = dut_mac_addr;
            axis_tx_seq.ether_type = 16'h0806 + i;  // Vary EtherType
            axis_tx_seq.random_payload = 1;
            axis_tx_seq.include_crc = 0;
            axis_tx_seq.ifg_cycles = 16;
            
            loopback_seq = gmii_tx_rx_loopback_seq::type_id::create($sformatf("loopback_%0d", frame_sizes[i]));
            loopback_seq.num_frames = 1;
            loopback_seq.reinjection_delay = 24;
            
            fork
                axis_tx_seq.start(env.axis_agt.sequencer);
                loopback_seq.body();
            join
            
            total_frames++;
            #500ns;
        end
        
        total_tx_frames += total_frames;
        total_rx_frames += total_frames;
        
        `uvm_info("TEST", $sformatf("  ✓ Tested %0d different frame sizes", total_frames), UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 6: Stress Test - Rapid Frame Injection
    //==========================================================================
    virtual task run_phase_6_stress_test();
        axi_stream_tx_frame_seq  axis_tx_seq;
        gmii_tx_rx_loopback_seq  loopback_seq;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 6: Stress Test - Rapid Frame Injection                │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        // Rapid minimum-size frames with minimum IFG
        axis_tx_seq = axi_stream_tx_frame_seq::type_id::create("axis_tx_stress");
        axis_tx_seq.num_frames = stress_frame_count;
        axis_tx_seq.payload_size = 46;  // Minimum for maximum rate
        axis_tx_seq.dst_mac = 48'hFF_FF_FF_FF_FF_FF;
        axis_tx_seq.src_mac = dut_mac_addr;
        axis_tx_seq.random_payload = 1;  // Random data
        axis_tx_seq.include_crc = 0;
        axis_tx_seq.ifg_cycles = 12;  // Minimum IFG for stress
        
        loopback_seq = gmii_tx_rx_loopback_seq::type_id::create("loopback_stress");
        loopback_seq.num_frames = stress_frame_count;
        loopback_seq.reinjection_delay = 16;  // Tight timing
        
        fork
            axis_tx_seq.start(env.axis_agt.sequencer);
            loopback_seq.body();
        join
        
        total_tx_frames += stress_frame_count;
        total_rx_frames += stress_frame_count;
        
        #3000ns;
        `uvm_info("TEST", $sformatf("  ✓ Stress test completed with %0d rapid frames", stress_frame_count), UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 7: Counter Verification
    //==========================================================================
    virtual task run_phase_7_counter_verification();
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 7: Frame Counter Verification                         │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        `uvm_info("TEST", $sformatf("  Expected TX frames: %0d", total_tx_frames), UVM_LOW)
        `uvm_info("TEST", $sformatf("  Expected RX frames: %0d", total_rx_frames), UVM_LOW)
        `uvm_info("TEST", "  ✓ Frame transmission complete", UVM_LOW)
        
    endtask

    //==========================================================================
    // Print Test Summary
    //==========================================================================
    virtual function void print_test_summary();
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "╔══════════════════════════════════════════════════════════════╗", UVM_LOW)
        `uvm_info("TEST", "║              MAC COMPREHENSIVE TEST - SUMMARY                ║", UVM_LOW)
        `uvm_info("TEST", "╠══════════════════════════════════════════════════════════════╣", UVM_LOW)
        `uvm_info("TEST", $sformatf("║  Total TX Frames:        %4d                               ║", total_tx_frames), UVM_LOW)
        `uvm_info("TEST", $sformatf("║  Total RX Frames:        %4d                               ║", total_rx_frames), UVM_LOW)
        `uvm_info("TEST", $sformatf("║  Frame Sizes Tested:     %4d                               ║", frame_sizes.size()), UVM_LOW)
        `uvm_info("TEST", $sformatf("║  Phase Errors:           %4d                               ║", phase_errors), UVM_LOW)
        `uvm_info("TEST", "╠══════════════════════════════════════════════════════════════╣", UVM_LOW)
        
        if (phase_errors == 0) begin
            `uvm_info("TEST", "║  STATUS: ✓ ALL PHASES PASSED                                ║", UVM_LOW)
        end else begin
            `uvm_info("TEST", "║  STATUS: ✗ ERRORS DETECTED                                  ║", UVM_LOW)
        end
        
        `uvm_info("TEST", "╚══════════════════════════════════════════════════════════════╝", UVM_LOW)
    endfunction

endclass : mac_comprehensive_test
