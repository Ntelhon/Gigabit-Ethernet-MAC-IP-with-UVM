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
        test_timeout = 500000;  // 500us timeout (enough for frame transmission)
        
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        // Interface-specific sequences
        axi_lite_mac_init_seq   init_seq;
        axi_lite_read_cnt_seq   cnt_seq;
        gmii_rx_seq             gmii_seq;
        
        // Frame data
        gmii_frame frame;
        bit [31:0] rx_count_before, rx_count_after;
        
        super.run_phase(phase);
        
        //----------------------------------------------------------------------
        // Raise Objection
        //----------------------------------------------------------------------
        phase.raise_objection(this, "mac_rx_basic_test running");
        `uvm_info("TEST", "=== Starting mac_rx_basic_test ===", UVM_LOW)
        
        //----------------------------------------------------------------------
        // Configure Scoreboard - RX only test, no TX comparison needed
        //----------------------------------------------------------------------
        env.mac_env.scb.tx_only_mode = 0;
        env.mac_env.scb.expect_loopback = 0;
        
        //----------------------------------------------------------------------
        // Wait for Reset
        //----------------------------------------------------------------------
        #100ns;
        
        // Wait for clocks to stabilize and drivers to be ready
        #50ns;  // A few clock cycles for all clocks
        
        // Give time for all run_phase tasks to start
        #5000ns;
        
        //----------------------------------------------------------------------
        // Initialize MAC via AXI-Lite
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Configuring MAC...", UVM_LOW)
        
        // Set MAC address (low)
        init_seq = axi_lite_mac_init_seq::type_id::create("init_seq");
        init_seq.mac_addr = dut_mac_addr;
        init_seq.tx_enable = 1;
        init_seq.rx_enable = 1;
        init_seq.start(mac_sqr.axi_lite_sqr);
        
        #200ns;
        
        //----------------------------------------------------------------------
        // Test 1: Minimum Size Frame (64 bytes)
        //----------------------------------------------------------------------
        `uvm_info("TEST", "Test 1: Sending 64-byte frame", UVM_LOW)
        
        // Read RX frame count before
        cnt_seq = axi_lite_read_cnt_seq::type_id::create("rd_cnt_1");
        cnt_seq.start(mac_sqr.axi_lite_sqr);
        rx_count_before = cnt_seq.mac_rx_frame_cnt;
        `uvm_info("TEST", $sformatf("RX count before: %0d", rx_count_before), UVM_LOW)
        
        // Create and send frame via GMII
        frame = gmii_frame::type_id::create("frame_64");
        frame.dst_mac = dut_mac_addr;
        frame.src_mac = 48'hAABBCCDDEEFF;
        frame.ether_type = 16'h0800;
        frame.payload = new[46];  // 64 - 18 (header+FCS) = 46
        foreach(frame.payload[i]) frame.payload[i] = 8'hA5 ^ i[7:0];
        frame.has_fcs = 1;
        frame.inject_fcs_error = 0;

        gmii_seq = gmii_rx_seq::type_id::create("gmii_64");
        gmii_seq.frame = frame;
        
        `uvm_info("TEST", "About to call gmii_seq.start()...", UVM_LOW)
        gmii_seq.start(mac_sqr.gmii_sqr);
        `uvm_info("TEST", "gmii_seq.start() returned!", UVM_LOW)
        
        // Wait for MAC to process the frame
        #5000ns;
        
        // Read RX frame count after
        cnt_seq = axi_lite_read_cnt_seq::type_id::create("rd_cnt_2");
        cnt_seq.start(mac_sqr.axi_lite_sqr);
        rx_count_after = cnt_seq.mac_rx_frame_cnt;

        if (rx_count_after != rx_count_before + 1) begin
            `uvm_error("TEST", $sformatf("RX frame count did not increment as expected! Before: %0d, After: %0d", 
                        rx_count_before, rx_count_after))
        end else begin
            `uvm_info("TEST", "RX frame count incremented as expected.", UVM_LOW)
        end
        
        //----------------------------------------------------------------------
        // Test 2: Medium Size Frame (256 bytes)
        //----------------------------------------------------------------------
        #500ns;
        `uvm_info("TEST", "Test 2: Sending 256-byte frame", UVM_LOW)
        
        frame = gmii_frame::type_id::create("frame_256");
        frame.dst_mac = dut_mac_addr;
        frame.src_mac = 48'h112233445566;
        frame.ether_type = 16'h0800;
        frame.payload = new[238];  // 256 - 18 = 238
        foreach(frame.payload[i]) frame.payload[i] = i[7:0];
        frame.has_fcs = 1;
        frame.inject_fcs_error = 0;

        gmii_seq = gmii_rx_seq::type_id::create("gmii_256");
        gmii_seq.frame = frame;
        gmii_seq.start(mac_sqr.gmii_sqr);
        
        // Wait for MAC to process
        #10000ns;
        
        //----------------------------------------------------------------------
        // Test 3: Maximum Size Frame (1518 bytes)
        //----------------------------------------------------------------------
        #1000ns;
        `uvm_info("TEST", "Test 3: Sending 1518-byte frame", UVM_LOW)
        
        frame = gmii_frame::type_id::create("frame_1518");
        frame.dst_mac = dut_mac_addr;
        frame.src_mac = 48'hDEADBEEF0000;
        frame.ether_type = 16'h0800;
        frame.payload = new[1500];  // 1518 - 18 = 1500
        foreach(frame.payload[i]) frame.payload[i] = i[7:0];
        frame.has_fcs = 1;
        frame.inject_fcs_error = 0;

        gmii_seq = gmii_rx_seq::type_id::create("gmii_1518");
        gmii_seq.frame = frame;
        gmii_seq.start(mac_sqr.gmii_sqr);
        
        // Wait for MAC to process large frame
        #20000ns;

        //----------------------------------------------------------------------
        // Drain Time
        //----------------------------------------------------------------------
        #2000ns;

        //----------------------------------------------------------------------
        // Verify RX Frame Count and Error Status
        //----------------------------------------------------------------------
        cnt_seq = axi_lite_read_cnt_seq::type_id::create("rd_cnt_3");
        cnt_seq.start(mac_sqr.axi_lite_sqr);
        rx_count_after = cnt_seq.mac_rx_frame_cnt;

        if (rx_count_after != rx_count_before + 3) begin
            `uvm_error("TEST", $sformatf("RX frame count did not increment as expected! Before: %0d, After: %0d", 
                        rx_count_before, rx_count_after))
        end else begin
            `uvm_info("TEST", "RX frame count incremented as expected.", UVM_LOW)
        end

        if (cnt_seq.mac_rx_error_cnt != 0) begin
            `uvm_error("TEST", $sformatf("RX error count is non-zero! Count: %0d", 
                        cnt_seq.mac_rx_error_cnt))
        end else begin
            `uvm_info("TEST", "No RX errors detected from register.", UVM_LOW)
        end

        //----------------------------------------------------------------------
        // Test Complete
        `uvm_info("TEST", "=== mac_rx_basic_test Complete ===", UVM_LOW)
        
        // Print scoreboard summary
        env.mac_env.scb.print_summary();
        
        //----------------------------------------------------------------------
        // Drop Objection
        //----------------------------------------------------------------------
        phase.drop_objection(this, "mac_rx_basic_test complete");
        
    endtask

endclass : mac_rx_basic_test
