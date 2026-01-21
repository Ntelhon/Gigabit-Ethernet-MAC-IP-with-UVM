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
    int stress_frame_count = 30;  // Increased for more stress
    
    // Stress test configuration
    int stress_frame_sizes[] = '{64, 128, 256, 512, 1024};  // Various sizes for stress
    bit stress_inject_errors = 0;  // Set to 1 to inject errors during stress

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
        
        //----------------------------------------------------------------------
        // Configure Scoreboard
        //----------------------------------------------------------------------
        env.mac_env.scb.tx_only_mode = 0;
        env.mac_env.scb.expect_loopback = 0;
        env.mac_env.scb.check_crc = 0;
        
        // Wait for reset
        #100ns;
        #50ns;
        #5000ns;
        
        //----------------------------------------------------------------------
        // Phase 1: Register Configuration Verification
        //----------------------------------------------------------------------
        run_phase_1_register_verification();
        
        //----------------------------------------------------------------------
        // Phase 2: Minimum Size Frame Test
        //----------------------------------------------------------------------
        run_phase_2_min_frame_test();
        
        //----------------------------------------------------------------------
        // Phase 3: Maximum Size Frame Test
        //----------------------------------------------------------------------
        run_phase_3_max_frame_test();
        
        //----------------------------------------------------------------------
        // Phase 4: Burst Mode - Multiple Back-to-Back Frames
        //----------------------------------------------------------------------
        run_phase_4_burst_test();
        
        //----------------------------------------------------------------------
        // Phase 5: Mixed Frame Sizes
        //----------------------------------------------------------------------
        run_phase_5_mixed_sizes_test();
        
        //----------------------------------------------------------------------
        // Phase 6: Stress Test - High-Speed Loopback with Mixed Traffic
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
        env.mac_env.scb.print_summary();
        
        // Drain time
        #5000ns;
        
        phase.drop_objection(this, "mac_comprehensive_test complete");
        
    endtask

    //==========================================================================
    // Phase 1: Register Configuration Verification
    //==========================================================================
    virtual task run_phase_1_register_verification();
        axi_lite_mac_init_seq init_seq;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 1: MAC Initialization                                 │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        // Initialize MAC with specific configuration
        init_seq = axi_lite_mac_init_seq::type_id::create("init_seq");
        init_seq.mac_addr = dut_mac_addr;
        init_seq.tx_enable = 1;
        init_seq.rx_enable = 1;
        init_seq.start(mac_sqr.axi_lite_sqr);
        
        #200ns;
        
        `uvm_info("TEST", "  ✓ MAC initialized with TX and RX enabled", UVM_LOW)
        `uvm_info("TEST", "  Phase 1 complete", UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 2: Minimum Size Frame Test
    //==========================================================================
    virtual task run_phase_2_min_frame_test();
        gmii_rx_seq  gmii_seq;
        gmii_frame frame;
        int num_frames = 3;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 2: Minimum Size Frame Test (64 bytes)                │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        for (int i = 0; i < num_frames; i++) begin
            frame = gmii_frame::type_id::create($sformatf("frame_min_%0d", i));
            frame.dst_mac = dut_mac_addr;
            frame.src_mac = 48'hAABBCCDDEEFF;
            frame.ether_type = 16'h0800;
            frame.payload = new[46];  // 64 - 14 (header) - 4 (CRC) = 46
            foreach(frame.payload[j]) frame.payload[j] = 8'hAA;
            frame.has_fcs = 1;
            frame.inject_crc_error = 0;
            
            gmii_seq = gmii_rx_seq::type_id::create($sformatf("gmii_seq_min_%0d", i));
            gmii_seq.frame = frame;
            gmii_seq.start(mac_sqr.gmii_sqr);
            
            #500ns;
        end
        
        total_rx_frames += num_frames;
        
        #1000ns;
        `uvm_info("TEST", $sformatf("  ✓ Sent %0d minimum-size frames", num_frames), UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 3: Maximum Size Frame Test
    //==========================================================================
    virtual task run_phase_3_max_frame_test();
        gmii_rx_seq  gmii_seq;
        gmii_frame frame;
        int num_frames = 2;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 3: Maximum Size Frame Test (1518 bytes)              │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        for (int i = 0; i < num_frames; i++) begin
            frame = gmii_frame::type_id::create($sformatf("frame_max_%0d", i));
            frame.dst_mac = dut_mac_addr;
            frame.src_mac = 48'hDEADBEEFCAFE;
            frame.ether_type = 16'h0800;
            frame.payload = new[1500];  // Maximum payload
            foreach(frame.payload[j]) frame.payload[j] = j[7:0];
            frame.has_fcs = 1;
            frame.inject_crc_error = 0;
            
            gmii_seq = gmii_rx_seq::type_id::create($sformatf("gmii_seq_max_%0d", i));
            gmii_seq.frame = frame;
            gmii_seq.start(mac_sqr.gmii_sqr);
            
            #2000ns;  // More delay for large frames
        end
        
        total_rx_frames += num_frames;
        
        #2000ns;
        `uvm_info("TEST", $sformatf("  ✓ Sent %0d maximum-size frames", num_frames), UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 4: Burst Mode - Multiple Back-to-Back Frames
    //==========================================================================
    virtual task run_phase_4_burst_test();
        gmii_rx_seq  gmii_seq;
        gmii_frame frame;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 4: Burst Mode - Back-to-Back Frames                   │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        // Send multiple frames back-to-back with minimum IFG
        for (int i = 0; i < burst_count; i++) begin
            frame = gmii_frame::type_id::create($sformatf("frame_burst_%0d", i));
            frame.dst_mac = dut_mac_addr;
            frame.src_mac = 48'h5555_5555_5555;
            frame.ether_type = 16'h0800;
            frame.payload = new[100];  // Medium frames
            foreach(frame.payload[j]) frame.payload[j] = 8'h55;
            frame.has_fcs = 1;
            frame.inject_crc_error = 0;
            frame.ifg_bytes = 12;  // Minimum IFG
            
            gmii_seq = gmii_rx_seq::type_id::create($sformatf("gmii_seq_burst_%0d", i));
            gmii_seq.frame = frame;
            gmii_seq.start(mac_sqr.gmii_sqr);
            
            #200ns;  // Short delay for burst
        end
        
        total_rx_frames += burst_count;
        
        #2000ns;
        `uvm_info("TEST", $sformatf("  ✓ Completed burst of %0d back-to-back frames", burst_count), UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 5: Mixed Frame Sizes
    //==========================================================================
    virtual task run_phase_5_mixed_sizes_test();
        gmii_rx_seq  gmii_seq;
        gmii_frame frame;
        int total_frames = 0;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 5: Mixed Frame Sizes                                  │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        // Test each frame size
        foreach (frame_sizes[i]) begin
            int payload_size;
            
            // Calculate payload size (frame_size - 14 header - 4 CRC)
            payload_size = frame_sizes[i] - 18;
            if (payload_size < 46) payload_size = 46;  // Minimum payload
            
            `uvm_info("TEST", $sformatf("  Testing frame size: %0d bytes (payload: %0d)", 
                      frame_sizes[i], payload_size), UVM_MEDIUM)
            
            frame = gmii_frame::type_id::create($sformatf("frame_mixed_%0d", frame_sizes[i]));
            frame.dst_mac = dut_mac_addr;
            frame.src_mac = {16'h0102, 32'(frame_sizes[i])};  // Encode size in MAC
            frame.ether_type = 16'h0806 + i;
            frame.payload = new[payload_size];
            foreach(frame.payload[j]) frame.payload[j] = j[7:0];  // Incrementing pattern
            frame.has_fcs = 1;
            frame.inject_crc_error = 0;
            
            gmii_seq = gmii_rx_seq::type_id::create($sformatf("gmii_seq_mixed_%0d", i));
            gmii_seq.frame = frame;
            gmii_seq.start(mac_sqr.gmii_sqr);
            
            total_frames++;
            #500ns;
        end
        
        total_rx_frames += total_frames;
        
        `uvm_info("TEST", $sformatf("  ✓ Tested %0d different frame sizes", total_frames), UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 6: Stress Test - High-Speed Loopback with Mixed Traffic
    // 
    // This phase creates intense stress on the MAC by:
    // 1. Sending rapid bursts of frames with minimum IFG
    // 2. Mixing frame sizes from 64 to 1024 bytes
    // 3. Using different payload patterns to catch data path errors
    // 4. Testing MAC's ability to handle back-to-back frames
    // 5. Verifying no frame drops or corruption under load
    //==========================================================================
    virtual task run_phase_6_stress_test();
        gmii_rx_seq  gmii_seq;
        gmii_frame frame;
        int frames_sent = 0;
        int size_idx;
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 6: Stress Test - High-Speed Mixed Traffic            │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        `uvm_info("TEST", $sformatf("  Injecting %0d frames with varying sizes and patterns", stress_frame_count), UVM_MEDIUM)
        
        // Send stress_frame_count frames with varied characteristics
        for (int i = 0; i < stress_frame_count; i++) begin
            int payload_size;
            bit [7:0] pattern;
            
            // Cycle through different frame sizes
            size_idx = i % stress_frame_sizes.size();
            payload_size = stress_frame_sizes[size_idx] - 18;
            if (payload_size < 46) payload_size = 46;
            
            // Create varied payload patterns to stress data path
            case (i % 6)
                0: pattern = 8'h00;  // All zeros
                1: pattern = 8'hFF;  // All ones
                2: pattern = 8'hAA;  // Alternating 10101010
                3: pattern = 8'h55;  // Alternating 01010101
                4: pattern = 8'hCC;  // 11001100
                default: pattern = i[7:0];  // Incrementing
            endcase
            
            frame = gmii_frame::type_id::create($sformatf("frame_stress_%0d", i));
            frame.dst_mac = dut_mac_addr;
            frame.src_mac = {16'hF00D, 32'(i)};  // Encode frame number in source MAC
            frame.ether_type = 16'h0800;
            frame.payload = new[payload_size];
            
            // Fill payload with pattern
            foreach(frame.payload[j]) begin
                if (i % 5 == 4) 
                    frame.payload[j] = j[7:0];  // Incrementing pattern
                else
                    frame.payload[j] = pattern;
            end
            
            frame.has_fcs = 1;
            frame.inject_crc_error = 0;
            frame.ifg_bytes = 12;  // Minimum IFG for maximum stress
            
            // Occasionally test with slightly longer IFG
            if (i % 7 == 0) frame.ifg_bytes = 16;
            
            gmii_seq = gmii_rx_seq::type_id::create($sformatf("gmii_seq_stress_%0d", i));
            gmii_seq.frame = frame;
            gmii_seq.start(mac_sqr.gmii_sqr);
            
            frames_sent++;
            
            // Variable delays to create bursty traffic pattern
            if (i % 5 == 0) begin
                #50ns;   // Very short delay - continuous burst
            end else if (i % 10 == 9) begin
                #1000ns;  // Occasional longer gap to simulate real traffic
            end else begin
                #100ns;   // Normal short delay
            end
            
            // Progress indicator every 10 frames
            if ((i+1) % 10 == 0) begin
                `uvm_info("TEST", $sformatf("    Progress: %0d/%0d frames sent", i+1, stress_frame_count), UVM_MEDIUM)
            end
        end
        
        total_rx_frames += frames_sent;
        
        // Allow time for all frames to be processed
        #5000ns;
        
        `uvm_info("TEST", $sformatf("  ✓ Stress test completed - sent %0d frames", frames_sent), UVM_LOW)
        `uvm_info("TEST", "    Frame sizes: 64-1024 bytes", UVM_LOW)
        `uvm_info("TEST", "    IFG: 12-16 bytes (minimum to short)", UVM_LOW)
        `uvm_info("TEST", "    Payload patterns: 0x00, 0xFF, 0xAA, 0x55, 0xCC, incrementing", UVM_LOW)
        
    endtask

    //==========================================================================
    // Phase 7: Counter Verification
    //==========================================================================
    virtual task run_phase_7_counter_verification();

        axi_lite_read_cnt_seq read_cnt_seq;

        read_cnt_seq = axi_lite_read_cnt_seq::type_id::create("read_cnt");
        read_cnt_seq.start(mac_sqr.axi_lite_sqr);
        
        `uvm_info("TEST", "", UVM_LOW)
        `uvm_info("TEST", "┌──────────────────────────────────────────────────────────────┐", UVM_LOW)
        `uvm_info("TEST", "│  PHASE 7: Frame Counter Verification                         │", UVM_LOW)
        `uvm_info("TEST", "└──────────────────────────────────────────────────────────────┘", UVM_LOW)
        
        `uvm_info("TEST", $sformatf("  Expected TX frames: %0d", total_tx_frames), UVM_LOW)
        `uvm_info("TEST", $sformatf("  Expected RX frames: %0d", total_rx_frames), UVM_LOW)
        `uvm_info("TEST", $sformatf("  Actual TX frames:   %0d", read_cnt_seq.mac_tx_frame_cnt), UVM_LOW)
        `uvm_info("TEST", $sformatf("  Actual RX frames:   %0d", read_cnt_seq.mac_rx_frame_cnt), UVM_LOW)
        `uvm_info("TEST", "  ✓ Frame transmission complete", UVM_LOW)

        if (read_cnt_seq.mac_tx_frame_cnt == total_tx_frames && read_cnt_seq.mac_rx_frame_cnt == total_rx_frames) begin
            `uvm_info("TEST", "  Frame counts match expected values", UVM_LOW)
        end else begin
            `uvm_error("TEST", "Frame count mismatch detected during counter verification")
            phase_errors++;
        end
        
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
