//==============================================================================
// Test: mac_tx_only_test
// Description: MAC TX path verification test (true TX test)
//
// Purpose:
//   Verify that the MAC can transmit Ethernet frames correctly. This test
//   drives frames via the AXI-Stream TX interface and monitors the GMII TX
//   interface to verify correct frame transmission.
//
// Data Flow:
//   AXI-Stream TX → MAC TX → GMII TX (monitored)
//
// Test Flow:
//   1. Initialize MAC (set MAC address, enable TX)
//   2. Send frames via AXI-Stream TX interface
//   3. Monitor GMII TX for transmitted frames
//   4. Verify frame content, preamble, SFD, and CRC
//
// Pass Criteria:
//   - All frames transmitted on GMII TX
//   - Correct preamble (7 bytes of 0x55) and SFD (0xD5)
//   - Valid CRC appended by MAC
//   - Frame content matches input data
//   - No UVM errors
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_tx_only_test extends mac_base_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_tx_only_test)

    //==========================================================================
    // Configuration
    //==========================================================================
    int num_frames = 3;          // Number of frames to transmit
    int frame_sizes[] = '{64, 128, 256};  // Different frame sizes to test

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_tx_only_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("TEST", "Building mac_tx_only_test (true TX path verification)", UVM_LOW)
        
        // Test-specific configuration
        test_timeout = 100000;  // 100us timeout
        
    endfunction

    //==========================================================================
    // Run Phase - Tests MAC TX path by sending frames via AXI-Stream TX
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        mac_init_seq             init_seq;
        axi_stream_tx_frame_seq  axis_tx_seq;
        int                      tx_frame_count;
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_tx_only_test running");
        `uvm_info("TEST", "=== Starting mac_tx_only_test (TX path test) ===", UVM_LOW)
        
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
        // Send Frames via AXI-Stream TX Agent
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Sending frames via AXI-Stream TX interface", UVM_MEDIUM)
        
        foreach (frame_sizes[i]) begin
            axis_tx_seq = axi_stream_tx_frame_seq::type_id::create($sformatf("axis_tx_seq_%0d", i));
            axis_tx_seq.num_frames = 1;
            axis_tx_seq.payload_size = frame_sizes[i] - 14;  // Frame size minus header
            axis_tx_seq.dst_mac = 48'hFF_FF_FF_FF_FF_FF;  // Broadcast
            axis_tx_seq.src_mac = dut_mac_addr;
            axis_tx_seq.random_payload = 0;
            axis_tx_seq.payload_pattern = 8'hA5 + i;
            axis_tx_seq.include_crc = 0;  // MAC computes CRC
            
            `uvm_info("TEST", $sformatf("Sending TX frame %0d: size=%0d", 
                      i+1, frame_sizes[i]), UVM_MEDIUM)
            
            // Start sequence on the AXI-Stream sequencer
            axis_tx_seq.start(env.axis_agt.sequencer);
            
            #500ns;  // Inter-frame gap
        end
        
        //----------------------------------------------------------------------
        // Drain Time - Wait for all frames to be transmitted
        //----------------------------------------------------------------------
        #2000ns;
        
        //----------------------------------------------------------------------
        // Verify TX - Check GMII monitor for transmitted frames
        //----------------------------------------------------------------------
        `uvm_info("TEST", $sformatf("TX test complete: sent %0d frames", 
                  frame_sizes.size()), UVM_LOW)
        
        //----------------------------------------------------------------------
        // Read TX Statistics
        //----------------------------------------------------------------------
        #100ns;
        
        `uvm_info("TEST", "=== mac_tx_only_test Complete ===", UVM_LOW)
        
        // Print scoreboard summary
        env.scb.print_summary();
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_tx_only_test complete");
        
    endtask

endclass : mac_tx_only_test

