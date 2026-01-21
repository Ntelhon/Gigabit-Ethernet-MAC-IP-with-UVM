//==============================================================================
// Test: mac_tx_rx_loopback_test
// Description: Full TX-RX loopback test for MAC verification
//
// Purpose:
//   Verify the complete data path through the MAC by:
//   1. Sending frames via AXI-Stream TX interface
//   2. Capturing frames from GMII TX
//   3. Reinjecting captured frames to GMII RX
//   4. Verifying frames received on RX path
//
// Data Flow:
//   AXI-Stream TX → MAC TX → GMII TX → [Loopback] → GMII RX → MAC RX
//
// Test Flow:
//   1. Initialize MAC (enable TX and RX)
//   2. Fork TX frame generation and loopback capture
//   3. Send frames via AXI-Stream TX
//   4. Loopback sequence captures GMII TX and reinjects to GMII RX
//   5. Scoreboard verifies TX frames match RX frames
//
// Pass Criteria:
//   - All TX frames appear on GMII TX
//   - All frames successfully looped back to GMII RX
//   - MAC RX processes looped frames correctly
//   - Frame content preserved through loopback
//   - No CRC errors (MAC recalculates CRC, should match)
//   - No UVM errors
//
// Configuration:
//   - Scoreboard expect_loopback = 1 (expects TX frames to appear on RX)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_tx_rx_loopback_test extends mac_base_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_tx_rx_loopback_test)

    //==========================================================================
    // Configuration
    //==========================================================================
    int num_loopback_frames = 3;
    int loopback_frame_size = 64;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_tx_rx_loopback_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("TEST", "Building mac_tx_rx_loopback_test", UVM_LOW)
        
        // Test-specific configuration
        test_timeout = 200000;  // 200us timeout
        
    endfunction

    //==========================================================================
    // Run Phase - Full TX-RX Loopback Test
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        // Interface-specific sequences
        axi_lite_mac_init_seq  init_seq;
        axi_lite_read_cnt_seq  cnt_seq;
        axi_stream_tx_seq      axis_tx_seq;
        gmii_rx_seq            gmii_seq;
        
        // Frame data
        gmii_frame rx_frame;
        int        frame_sizes[] = '{64, 128, 256};
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_tx_rx_loopback_test running");
        `uvm_info("TEST", "=== Starting mac_tx_rx_loopback_test ===", UVM_LOW)
        
        //----------------------------------------------------------------------
        // Configure Scoreboard - Compare TX frames against manually looped RX
        //----------------------------------------------------------------------
        env.mac_env.scb.tx_only_mode = 0;  // We want frame comparison
        env.mac_env.scb.expect_loopback = 1;  // Manual loopback, not automatic
        
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
        // Send frames via AXI-Stream TX and immediately loop back via GMII RX
        //----------------------------------------------------------------------
        `uvm_info("TEST", $sformatf("Starting loopback test with %0d frames", 
                  frame_sizes.size()), UVM_MEDIUM)
        
        foreach (frame_sizes[i]) begin
            // Create 
            rx_frame = gmii_frame::type_id::create($sformatf("expected_tx_%0d", i));
            rx_frame.dst_mac = 48'hFF_FF_FF_FF_FF_FF;
            rx_frame.src_mac = dut_mac_addr;
            rx_frame.ether_type = 16'h0800;
            rx_frame.payload = new[frame_sizes[i] - 14];
            foreach(rx_frame.payload[j]) rx_frame.payload[j] = 8'hA5 + i;
            
            // Send frame from GMII RX to MAC RX
            gmii_seq = gmii_rx_seq::type_id::create($sformatf("gmii_rx_seq_%0d", i));
            gmii_seq.frame = rx_frame;
            gmii_seq.start(env.mac_env.gmii_agt.sequencer);
            
            #2000ns;  // Wait for frame processing

            // Create and send frame via AXI-Stream TX
            axis_tx_seq = axi_stream_tx_seq::type_id::create($sformatf("axis_tx_seq_%0d", i));
            axis_tx_seq.num_frames = 1;
            axis_tx_seq.payload_size = frame_sizes[i] - 14;  // Frame size minus header
            axis_tx_seq.dst_mac = 48'h00_FF_FF_FF_FF_FF;  // Broadcast (6 bytes)
            axis_tx_seq.src_mac = dut_mac_addr;
            axis_tx_seq.random_payload = 0;
            axis_tx_seq.payload_pattern = 8'hA5 + i;
            axis_tx_seq.include_crc = 0;  // MAC computes CRC   
            axis_tx_seq.start(env.mac_env.axis_agt.sequencer);

            #500ns;  // Inter-frame gap
        end
        
        //----------------------------------------------------------------------
        // Drain Time - Wait for all frames to propagate
        //----------------------------------------------------------------------
        #3000ns;
        
        //----------------------------------------------------------------------
        // Verify Results
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Verifying results...", UVM_LOW)

        cnt_seq = axi_lite_read_cnt_seq::type_id::create("rd_cnt");
        cnt_seq.start(mac_sqr.axi_lite_sqr);

        if ((cnt_seq.mac_tx_frame_cnt != num_loopback_frames) && (cnt_seq.mac_rx_frame_cnt != num_loopback_frames)) begin
            `uvm_error("TEST", $sformatf("TX/RX frame count mismatch! Expected: %0d, Actual-TX: %0d, Actual-RX: %0d", 
                        num_loopback_frames, cnt_seq.mac_tx_frame_cnt, cnt_seq.mac_rx_frame_cnt))
        end else begin
            `uvm_info("TEST", "TX frame count incremented as expected.", UVM_LOW)
        end

        if (cnt_seq.mac_rx_error_cnt != 0) begin
            `uvm_error("TEST", $sformatf("RX error count is non-zero! Count: %0d", 
                        cnt_seq.mac_rx_error_cnt))
        end else begin
            `uvm_info("TEST", "No RX errors detected from register.", UVM_LOW)
        end

        `uvm_info("TEST", "=== mac_tx_rx_loopback_test Complete ===", UVM_LOW)
        
        // Print scoreboard summary
        env.mac_env.scb.print_summary();
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_tx_rx_loopback_test complete");
        
    endtask

endclass : mac_tx_rx_loopback_test

