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
        
        // Configure scoreboard for loopback mode
        // In loopback mode, we expect TX frames to reappear on RX
        uvm_config_db#(int)::set(this, "env.scoreboard", "expect_loopback", 1);
        
    endfunction

    //==========================================================================
    // Run Phase - Full TX-RX Loopback Test
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        mac_init_seq             init_seq;
        axi_stream_tx_frame_seq  axis_tx_seq;
        gmii_tx_rx_loopback_seq  loopback_seq;
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_tx_rx_loopback_test running");
        `uvm_info("TEST", "=== Starting mac_tx_rx_loopback_test ===", UVM_LOW)
        
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
        // Create Sequences
        //----------------------------------------------------------------------
        axis_tx_seq = axi_stream_tx_frame_seq::type_id::create("axis_tx_seq");
        axis_tx_seq.num_frames = num_loopback_frames;
        axis_tx_seq.payload_size = loopback_frame_size - 14;  // Frame size minus header
        axis_tx_seq.dst_mac = 48'hFF_FF_FF_FF_FF_FF;  // Broadcast
        axis_tx_seq.src_mac = dut_mac_addr;
        axis_tx_seq.random_payload = 0;
        axis_tx_seq.payload_pattern = 8'h5A;
        axis_tx_seq.include_crc = 0;  // MAC computes CRC
        axis_tx_seq.ifg_cycles = 20;  // Larger gap for loopback processing
        
        loopback_seq = gmii_tx_rx_loopback_seq::type_id::create("loopback_seq");
        loopback_seq.num_frames = num_loopback_frames;
        loopback_seq.reinjection_delay = 24;  // 2x IFG for safety
        
        //----------------------------------------------------------------------
        // Run TX and Loopback in Parallel
        //----------------------------------------------------------------------
        `uvm_info("TEST", $sformatf("Starting loopback test with %0d frames", 
                  num_loopback_frames), UVM_MEDIUM)
        
        fork
            // TX path: Send frames via AXI-Stream agent
            begin
                `uvm_info("TEST", "Starting AXI-Stream TX sequence", UVM_HIGH)
                axis_tx_seq.start(env.axis_agt.sequencer);
                `uvm_info("TEST", "AXI-Stream TX sequence complete", UVM_HIGH)
            end
            
            // Loopback: Capture GMII TX and reinject to GMII RX
            begin
                `uvm_info("TEST", "Starting loopback sequence", UVM_HIGH)
                loopback_seq.body();
                `uvm_info("TEST", "Loopback sequence complete", UVM_HIGH)
            end
        join
        
        //----------------------------------------------------------------------
        // Drain Time - Wait for all frames to propagate through RX path
        //----------------------------------------------------------------------
        #3000ns;
        
        //----------------------------------------------------------------------
        // Verify Results
        //----------------------------------------------------------------------
        `uvm_info("TEST", $sformatf("Loopback test complete: %0d frames processed", 
                  num_loopback_frames), UVM_LOW)
        
        `uvm_info("TEST", "=== mac_tx_rx_loopback_test Complete ===", UVM_LOW)
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_tx_rx_loopback_test complete");
        
    endtask

endclass : mac_tx_rx_loopback_test

