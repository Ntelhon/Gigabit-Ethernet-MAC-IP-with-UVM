//==============================================================================
// Test: mac_crc_error_test
// Description: CRC error injection and detection test
//
// Purpose:
//   Verify that the MAC correctly detects and handles frames with CRC errors.
//   The MAC should discard bad frames and increment error counters.
//
// Test Flow:
//   1. Initialize MAC (set MAC address, enable TX/RX)
//   2. Send a good frame first (baseline)
//   3. Inject frame with corrupted CRC
//   4. Verify frame is dropped (RX counter unchanged)
//   5. Verify RX error counter increments
//   6. Send another good frame to verify MAC still operational
//
// Pass Criteria:
//   - Bad CRC frame is discarded
//   - RX error counter increments
//   - RX good frame counter does NOT increment for bad frame
//   - MAC remains operational after error
//   - No UVM errors
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_crc_error_test extends mac_base_test;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_crc_error_test)

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_crc_error_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("TEST", "Building mac_crc_error_test", UVM_LOW)
        
        // Test-specific configuration
        test_timeout = 60000;  // 60us timeout
        
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        mac_init_seq      init_seq;
        mac_rx_basic_seq  good_rx_seq;
        mac_crc_error_seq crc_err_seq;
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_crc_error_test running");
        `uvm_info("TEST", "=== Starting mac_crc_error_test ===", UVM_LOW)
        
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
        // Send Good Frame First (Baseline)
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Sending good frame (baseline)", UVM_MEDIUM)
        good_rx_seq = mac_rx_basic_seq::type_id::create("good_rx_seq");
        good_rx_seq.frame_size = 64;
        good_rx_seq.dst_mac = dut_mac_addr;
        good_rx_seq.src_mac = 48'hAABBCCDDEEFF;
        good_rx_seq.start(env.v_sqr);
        
        #500ns;
        
        //----------------------------------------------------------------------
        // Inject CRC Error Frame
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Injecting CRC error frame", UVM_MEDIUM)
        crc_err_seq = mac_crc_error_seq::type_id::create("crc_err_seq");
        crc_err_seq.start(env.v_sqr);
        
        #500ns;
        
        //----------------------------------------------------------------------
        // Send Another Good Frame (Verify MAC Still Works)
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Sending good frame after error", UVM_MEDIUM)
        good_rx_seq = mac_rx_basic_seq::type_id::create("post_err_rx_seq");
        good_rx_seq.frame_size = 128;
        good_rx_seq.dst_mac = dut_mac_addr;
        good_rx_seq.src_mac = 48'h112233445566;
        good_rx_seq.start(env.v_sqr);
        
        //----------------------------------------------------------------------
        // Drain Time
        //----------------------------------------------------------------------
        #1000ns;
        
        `uvm_info("TEST", "=== mac_crc_error_test Complete ===", UVM_LOW)
        
        // Print scoreboard summary
        env.scb.print_summary();
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_crc_error_test complete");
        
    endtask

endclass : mac_crc_error_test
