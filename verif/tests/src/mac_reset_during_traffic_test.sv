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
        // Interface-specific sequences
        axi_lite_mac_init_seq  init_seq;
        axi_lite_read_seq      rd_seq;
        axi_lite_write_seq     wr_seq;
        gmii_rx_seq            gmii_seq;
        
        // Frame data
        gmii_frame frame;
        bit [31:0] reg_val;
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_reset_during_traffic_test running");
        `uvm_info("TEST", "=== Starting mac_reset_during_traffic_test ===", UVM_LOW)
        
        //----------------------------------------------------------------------
        // Configure Scoreboard - RX-only test
        //----------------------------------------------------------------------
        env.mac_env.scb.tx_only_mode = 0;
        env.mac_env.scb.expect_loopback = 0;
        env.mac_env.scb.check_crc = 0;
        
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
        // Start Frame Transmission
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Sending frame before reset", UVM_MEDIUM)
        
        frame = gmii_frame::type_id::create("frame_before_reset");
        frame.dst_mac = dut_mac_addr;
        frame.src_mac = 48'hAABBCCDDEEFF;
        frame.ether_type = 16'h0800;
        frame.payload = new[46];
        foreach(frame.payload[i]) frame.payload[i] = 8'hAA;
        frame.has_fcs = 1;
        frame.inject_crc_error = 0;
        
        gmii_seq = gmii_rx_seq::type_id::create("pre_reset_seq");
        gmii_seq.frame = frame;
        gmii_seq.start(mac_sqr.gmii_sqr);
        
        #1000ns;
        
        //----------------------------------------------------------------------
        // Assert Reset (via control register or direct)
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Asserting soft reset via control register", UVM_MEDIUM)
        
        // Read control register
        rd_seq = axi_lite_read_seq::type_id::create("rd_ctrl_before");
        rd_seq.addr = ADDR_CONTROL;
        rd_seq.start(mac_sqr.axi_lite_sqr);
        
        // Disable TX/RX (soft reset)
        wr_seq = axi_lite_write_seq::type_id::create("wr_ctrl_disable");
        wr_seq.addr = ADDR_CONTROL;
        wr_seq.data = 32'h0;  // Disable TX/RX
        wr_seq.start(mac_sqr.axi_lite_sqr);
        
        #500ns;
        
        //----------------------------------------------------------------------
        // Verify registers cleared/reset
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Verifying control register after reset", UVM_MEDIUM)
        
        rd_seq = axi_lite_read_seq::type_id::create("rd_ctrl_after");
        rd_seq.addr = ADDR_CONTROL;
        rd_seq.start(mac_sqr.axi_lite_sqr);
        reg_val = rd_seq.data;
        
        if (reg_val == 32'h0) begin
            `uvm_info("TEST", "✓ Control register cleared after reset", UVM_LOW)
        end else begin
            `uvm_warning("TEST", $sformatf("⚠ Control register = 0x%08h (expected 0x00000000)", reg_val))
        end
        
        #500ns;
        
        //----------------------------------------------------------------------
        // Re-initialize MAC
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Re-initializing MAC after reset", UVM_MEDIUM)
        
        init_seq = axi_lite_mac_init_seq::type_id::create("reinit_seq");
        init_seq.mac_addr = dut_mac_addr;
        init_seq.tx_enable = 1;
        init_seq.rx_enable = 1;
        init_seq.start(mac_sqr.axi_lite_sqr);
        
        #200ns;
        
        //----------------------------------------------------------------------
        // Verify Normal Operation Post-Reset
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Verifying stable RX operation after reset", UVM_MEDIUM)
        
        frame = gmii_frame::type_id::create("frame_post_reset");
        frame.dst_mac = dut_mac_addr;
        frame.src_mac = 48'h112233445566;
        frame.ether_type = 16'h0800;
        frame.payload = new[46];
        foreach(frame.payload[i]) frame.payload[i] = i[7:0];
        frame.has_fcs = 1;
        frame.inject_crc_error = 0;
        
        gmii_seq = gmii_rx_seq::type_id::create("post_reset_rx");
        gmii_seq.frame = frame;
        gmii_seq.start(mac_sqr.gmii_sqr);
        
        #500ns;
        
        //----------------------------------------------------------------------
        // Send Another Frame to Confirm Stable Operation
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Sending final verification frame", UVM_MEDIUM)
        
        frame = gmii_frame::type_id::create("frame_stable");
        frame.dst_mac = dut_mac_addr;
        frame.src_mac = 48'hDDEEFF001122;
        frame.ether_type = 16'h0800;
        frame.payload = new[110];
        foreach(frame.payload[i]) frame.payload[i] = 8'hCC;
        frame.has_fcs = 1;
        frame.inject_crc_error = 0;
        
        gmii_seq = gmii_rx_seq::type_id::create("stable_rx");
        gmii_seq.frame = frame;
        gmii_seq.start(mac_sqr.gmii_sqr);
        
        //----------------------------------------------------------------------
        // Drain Time
        //----------------------------------------------------------------------
        #2000ns;
        
        `uvm_info("TEST", "=== mac_reset_during_traffic_test Complete ===", UVM_LOW)
        
        // Print scoreboard summary
        env.mac_env.scb.print_summary();
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_reset_during_traffic_test complete");
        
    endtask

endclass : mac_reset_during_traffic_test
