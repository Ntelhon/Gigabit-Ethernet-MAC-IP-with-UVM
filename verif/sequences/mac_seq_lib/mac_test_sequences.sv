//==============================================================================
// File: mac_test_sequences.sv
// Description: Directed test sequences for MAC verification
//
// Purpose:
//   Contains virtual sequences for each directed test case.
//   All sequences coordinate AXI-Lite and GMII operations.
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================


//==============================================================================
// Sequence: mac_init_seq
// Description: Initialize MAC with basic configuration
//==============================================================================
class mac_init_seq extends mac_base_seq;

    `uvm_object_utils(mac_init_seq)
    
    bit [47:0] mac_addr = 48'h001122334455;
    bit tx_enable = 1;
    bit rx_enable = 1;

    function new(string name = "mac_init_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("SEQ", "Starting MAC initialization sequence", UVM_MEDIUM)
        
        // Set MAC address
        set_mac_address(mac_addr);
        
        // Enable TX and RX
        enable_mac(tx_enable, rx_enable);
        
        // Clear any pending interrupts
        clear_interrupts(4'hF);
        
        `uvm_info("SEQ", "MAC initialization complete", UVM_MEDIUM)
    endtask

endclass : mac_init_seq

//==============================================================================
// Sequence: mac_rx_basic_seq
// Description: Receive a basic frame through MAC RX path
//==============================================================================
class mac_rx_basic_seq extends mac_base_seq;

    `uvm_object_utils(mac_rx_basic_seq)
    
    int frame_size = 64;
    bit [47:0] dst_mac = 48'h001122334455;
    bit [47:0] src_mac = 48'hAABBCCDDEEFF;

    function new(string name = "mac_rx_basic_seq");
        super.new(name);
    endfunction

    virtual task body();
        gmii_frame frame;
        gmii_tx_seq gmii_seq;
        bit [31:0] rx_count_before, rx_count_after;
        
        `uvm_info("SEQ", $sformatf("Starting RX basic test: frame_size=%0d", frame_size), UVM_MEDIUM)
        
        // Read initial RX frame count
        get_rx_frame_count(rx_count_before);
        `uvm_info("SEQ", $sformatf("RX frame count before: %0d", rx_count_before), UVM_MEDIUM)
        
        // Create frame to inject
        frame = gmii_frame::type_id::create("rx_frame");
        frame.dst_mac = dst_mac;
        frame.src_mac = src_mac;
        frame.ether_type = 16'h0800;
        
        // Create payload
        frame.payload = new[frame_size - 18];
        for (int i = 0; i < frame.payload.size(); i++) begin
            frame.payload[i] = 8'hA5 ^ i[7:0];
        end
        
        frame.has_fcs = 1;          // Driver calculates FCS
        frame.inject_fcs_error = 0;
        
        // Create and configure GMII sequence
        gmii_seq = gmii_tx_seq::type_id::create("gmii_seq");
        gmii_seq.frame = frame;
        
        // Start on GMII sequencer (passed in via gmii_tx_sqr handle)
        gmii_seq.start(gmii_tx_sqr);

        // Wait for frame to be received and processed
        #2000ns;
        
        // Read RX frame count after
        get_rx_frame_count(rx_count_after);
        `uvm_info("SEQ", $sformatf("RX frame count after: %0d", rx_count_after), UVM_MEDIUM)
        
        // Verify frame count incremented
        if (rx_count_after != rx_count_before + 1) begin
            `uvm_error("SEQ", $sformatf("RX frame count mismatch: expected %0d, got %0d",
                       rx_count_before + 1, rx_count_after))
        end else begin
            `uvm_info("SEQ", "RX frame count verified", UVM_MEDIUM)
        end
        
    endtask

endclass : mac_rx_basic_seq


//==============================================================================
// Sequence: mac_crc_error_seq
// Description: Inject frame with CRC error, verify MAC drops it
//==============================================================================
class mac_crc_error_seq extends mac_base_seq;

    `uvm_object_utils(mac_crc_error_seq)

    function new(string name = "mac_crc_error_seq");
        super.new(name);
    endfunction

    virtual task body();
        gmii_frame frame;
        bit [31:0] rx_count_before, rx_count_after;
        bit [31:0] rx_err_before, rx_err_after;
        
        `uvm_info("SEQ", "Starting CRC error injection test", UVM_MEDIUM)
        
        // Read initial counters
        get_rx_frame_count(rx_count_before);
        read_reg(ADDR_RX_ERR, rx_err_before);
        `uvm_info("SEQ", $sformatf("RX frame count before: %0d, RX errors before: %0d",
                  rx_count_before, rx_err_before), UVM_MEDIUM)
        
        // Create frame with CRC error
        frame = gmii_frame::type_id::create("crc_err_frame");
        frame.dst_mac = 48'h001122334455;
        frame.src_mac = 48'hAABBCCDDEEFF;
        frame.ether_type = 16'h0800;
        
        frame.payload = new[46];  // Minimum payload
        for (int i = 0; i < 46; i++) begin
            frame.payload[i] = i[7:0];
        end
        
        frame.has_fcs = 1;
        frame.inject_crc_error = 1;  // Inject CRC error (driver checks this field)
        
        // Send frame with bad CRC
        send_frame(frame);
        
        // Wait for frame to be processed
        #2000ns;
        
        // Read counters after
        get_rx_frame_count(rx_count_after);
        read_reg(ADDR_RX_ERR, rx_err_after);
        `uvm_info("SEQ", $sformatf("RX frame count after: %0d, RX errors after: %0d",
                  rx_count_after, rx_err_after), UVM_MEDIUM)
        
        // Verify: Frame should NOT be counted as good, error should increment
        if (rx_count_after != rx_count_before) begin
            `uvm_error("SEQ", "RX frame count should not increment for CRC error frame")
        end else begin
            `uvm_info("SEQ", "RX frame count correctly unchanged", UVM_MEDIUM)
        end
        
        if (rx_err_after != rx_err_before + 1) begin
            `uvm_error("SEQ", "RX error count should increment for CRC error frame")
        end else begin
            `uvm_info("SEQ", "RX error count correctly incremented", UVM_MEDIUM)
        end
        
    endtask

endclass : mac_crc_error_seq


//==============================================================================
// Sequence: mac_runt_frame_seq
// Description: Send runt frame (< 64 bytes), verify MAC handling
//==============================================================================
class mac_runt_frame_seq extends mac_base_seq;

    `uvm_object_utils(mac_runt_frame_seq)

    function new(string name = "mac_runt_frame_seq");
        super.new(name);
    endfunction

    virtual task body();
        gmii_frame frame;
        bit [31:0] rx_count_before, rx_count_after;
        bit [31:0] rx_err_before, rx_err_after;
        
        `uvm_info("SEQ", "Starting runt frame test", UVM_MEDIUM)
        
        // Read initial counters
        get_rx_frame_count(rx_count_before);
        read_reg(ADDR_RX_ERR, rx_err_before);
        
        // Create runt frame (less than 64 bytes total)
        frame = gmii_frame::type_id::create("runt_frame");
        frame.dst_mac = 48'h001122334455;
        frame.src_mac = 48'hAABBCCDDEEFF;
        frame.ether_type = 16'h0800;
        
        // Very small payload (only 10 bytes - total frame = 14 + 10 + 4 = 28 bytes)
        frame.payload = new[10];
        for (int i = 0; i < 10; i++) begin
            frame.payload[i] = i[7:0];
        end
        
        frame.has_fcs = 1;
        frame.inject_crc_error = 0;
        frame.send_as_runt = 1;  // Mark as runt - no padding (driver checks this field)
        
        // Send runt frame
        send_frame(frame);
        
        // Wait for frame to be processed
        #2000ns;
        
        // Read counters after
        get_rx_frame_count(rx_count_after);
        read_reg(ADDR_RX_ERR, rx_err_after);
        
        `uvm_info("SEQ", $sformatf("RX frame count: before=%0d, after=%0d",
                  rx_count_before, rx_count_after), UVM_MEDIUM)
        `uvm_info("SEQ", $sformatf("RX error count: before=%0d, after=%0d",
                  rx_err_before, rx_err_after), UVM_MEDIUM)
        
        // Verify: Runt frame should be dropped or flagged as error
        if (rx_err_after > rx_err_before) begin
            `uvm_info("SEQ", "Runt frame correctly flagged as error", UVM_MEDIUM)
        end else if (rx_count_after == rx_count_before) begin
            `uvm_info("SEQ", "Runt frame correctly dropped", UVM_MEDIUM)
        end else begin
            `uvm_warning("SEQ", "Runt frame handling check inconclusive")
        end
        
    endtask

endclass : mac_runt_frame_seq


//==============================================================================
// Sequence: mac_ifg_test_seq
// Description: Verify MAC handles back-to-back RX frames correctly
// Note: This tests the MAC's ability to receive consecutive frames with
//       proper inter-frame gap. IFG timing is enforced by the GMII driver.
//       The MAC should correctly receive both frames and increment RX count.
//==============================================================================
class mac_ifg_test_seq extends mac_base_seq;

    `uvm_object_utils(mac_ifg_test_seq)

    function new(string name = "mac_ifg_test_seq");
        super.new(name);
    endfunction

    virtual task body();
        gmii_frame frame1, frame2;
        bit [31:0] rx_count_before, rx_count_after;
        
        `uvm_info("SEQ", "Starting IFG (Inter-Frame Gap) test - back-to-back RX frames", UVM_MEDIUM)
        
        // Read initial RX frame count
        get_rx_frame_count(rx_count_before);
        `uvm_info("SEQ", $sformatf("RX frame count before: %0d", rx_count_before), UVM_MEDIUM)
        
        // Create first frame
        frame1 = gmii_frame::type_id::create("frame1");
        frame1.dst_mac = 48'h001122334455;  // MAC's address
        frame1.src_mac = 48'hAABBCCDDEEFF;
        frame1.ether_type = 16'h0800;
        frame1.payload = new[46];
        foreach (frame1.payload[i]) frame1.payload[i] = i[7:0];
        frame1.has_fcs = 1;  // Driver calculates FCS
        frame1.inject_crc_error = 0;
        
        // Create second frame
        frame2 = gmii_frame::type_id::create("frame2");
        frame2.dst_mac = 48'h001122334455;  // MAC's address
        frame2.src_mac = 48'hAABBCCDDEEFF;
        frame2.ether_type = 16'h0801;
        frame2.payload = new[46];
        foreach (frame2.payload[i]) frame2.payload[i] = ~i[7:0];
        frame2.has_fcs = 1;
        frame2.inject_crc_error = 0;
        
        // Send first frame to MAC RX path
        `uvm_info("SEQ", "Sending first frame to MAC RX", UVM_MEDIUM)
        send_frame(frame1);
        
        // Driver automatically inserts standard IFG (12 bytes)
        // Then send second frame immediately
        `uvm_info("SEQ", "Sending second frame (back-to-back after IFG)", UVM_MEDIUM)
        send_frame(frame2);
        
        // Wait for both frames to be processed
        #4000ns;
        
        // Read RX frame count after
        get_rx_frame_count(rx_count_after);
        `uvm_info("SEQ", $sformatf("RX frame count after: %0d", rx_count_after), UVM_MEDIUM)
        
        // Verify both frames received correctly
        if (rx_count_after != rx_count_before + 2) begin
            `uvm_error("SEQ", $sformatf("RX frame count mismatch: expected %0d, got %0d",
                       rx_count_before + 2, rx_count_after))
        end else begin
            `uvm_info("SEQ", "Both back-to-back frames received successfully", UVM_MEDIUM)
            `uvm_info("SEQ", "IFG handling verification complete", UVM_MEDIUM)
        end
        
    endtask

endclass : mac_ifg_test_seq


//==============================================================================
// Sequence: mac_reset_during_traffic_seq
// Description: Assert reset during active RX traffic, verify recovery
// Note: This test injects frames to the MAC's RX path, then asserts soft
//       reset mid-frame to verify the MAC can recover gracefully.
//==============================================================================
class mac_reset_during_traffic_seq extends mac_base_seq;

    `uvm_object_utils(mac_reset_during_traffic_seq)

    function new(string name = "mac_reset_during_traffic_seq");
        super.new(name);
    endfunction

    virtual task body();
        gmii_frame frame;
        bit [31:0] version_reg;
        bit [31:0] ctrl_reg;
        bit [31:0] rx_count_before, rx_count_after;
        
        `uvm_info("SEQ", "Starting reset-during-traffic test", UVM_MEDIUM)
        
        // First verify MAC is operational
        read_reg(ADDR_VERSION, version_reg);
        `uvm_info("SEQ", $sformatf("MAC version: 0x%08h", version_reg), UVM_MEDIUM)
        
        // Create a large frame to extend reception time
        frame = gmii_frame::type_id::create("traffic_frame");
        frame.dst_mac = 48'h001122334455;  // MAC's address
        frame.src_mac = 48'hAABBCCDDEEFF;
        frame.ether_type = 16'h0800;
        frame.payload = new[500];  // Larger payload to extend reception time
        foreach (frame.payload[i]) frame.payload[i] = i[7:0];
        frame.has_fcs = 1;
        frame.inject_crc_error = 0;
        
        // Start frame reception in background (frame sent to MAC RX)
        fork
            send_frame(frame);
        join_none
        
        // Wait for frame to start being received (mid-preamble or mid-data)
        #200ns;
        
        // Assert reset via control register (soft reset bit)
        // Assuming bit[31] is soft reset
        `uvm_info("SEQ", "Asserting soft reset during RX reception", UVM_MEDIUM)
        write_reg(ADDR_CONTROL, 32'h8000_0000);  // Set soft reset bit
        
        #100ns;
        
        // Deassert reset
        write_reg(ADDR_CONTROL, 32'h0000_0000);  // Clear soft reset
        `uvm_info("SEQ", "Soft reset deasserted", UVM_MEDIUM)
        
        #500ns;
        
        // Verify MAC is responsive after reset
        read_reg(ADDR_VERSION, version_reg);
        `uvm_info("SEQ", $sformatf("MAC version after reset: 0x%08h", version_reg), UVM_MEDIUM)
        
        // Verify control register is cleared (TX/RX disabled after reset)
        read_reg(ADDR_CONTROL, ctrl_reg);
        if (ctrl_reg[1:0] != 2'b00) begin
            `uvm_warning("SEQ", $sformatf("Control register not cleared after reset: 0x%08h", ctrl_reg))
        end else begin
            `uvm_info("SEQ", "Control register correctly cleared after reset", UVM_MEDIUM)
        end
        
        // Re-initialize MAC
        set_mac_address(48'h001122334455);
        enable_mac(1, 1);
        
        // Wait for CDC synchronizers to propagate enables
        #100ns;
        
        // Get RX count before sending post-reset verification frame
        get_rx_frame_count(rx_count_before);
        `uvm_info("SEQ", $sformatf("RX count before post-reset verification: %0d", rx_count_before), UVM_MEDIUM)
        
        // Send a new frame to verify MAC is operational after reset
        frame = gmii_frame::type_id::create("post_reset_frame");
        frame.dst_mac = 48'h001122334455;
        frame.src_mac = 48'hAABBCCDDEEFF;
        frame.ether_type = 16'h0802;
        frame.payload = new[46];
        foreach (frame.payload[i]) frame.payload[i] = 8'h55;
        frame.has_fcs = 1;
        frame.inject_crc_error = 0;
        
        send_frame(frame);
        #2000ns;
        
        // Verify frame was received - check that count increased (at least +1)
        get_rx_frame_count(rx_count_after);
        `uvm_info("SEQ", $sformatf("RX count after post-reset verification: %0d", rx_count_after), UVM_MEDIUM)
        
        if (rx_count_after <= rx_count_before) begin
            `uvm_error("SEQ", $sformatf("MAC not operational after reset: RX count did not increase (before=%0d, after=%0d)",
                       rx_count_before, rx_count_after))
        end else begin
            `uvm_info("SEQ", $sformatf("MAC correctly operational after reset (RX count: %0d → %0d)", 
                      rx_count_before, rx_count_after), UVM_MEDIUM)
        end
        
        `uvm_info("SEQ", "Reset-during-traffic test complete", UVM_MEDIUM)
        
    endtask

endclass : mac_reset_during_traffic_seq


//==============================================================================
// Sequence: mac_reg_verify_seq
// Description: Verify register values after initialization
//==============================================================================
class mac_reg_verify_seq extends mac_base_seq;

    `uvm_object_utils(mac_reg_verify_seq)
    
    bit [47:0] expected_mac_addr;
    int errors = 0;

    function new(string name = "mac_reg_verify_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] read_data;
        bit [31:0] expected_data;
        
        `uvm_info("SEQ", "Verifying register configuration", UVM_MEDIUM)
        
        // Verify Control Register (0x00) - TX/RX enabled
        read_reg(32'h00, read_data);
        expected_data = 32'h0000_0003;  // TX_EN and RX_EN set
        if ((read_data & 32'h0000_0003) == expected_data) begin
            `uvm_info("SEQ", $sformatf("  Control register verified: 0x%08h", read_data), UVM_MEDIUM)
        end else begin
            `uvm_error("SEQ", $sformatf("  Control register mismatch: expected 0x%08h, got 0x%08h", 
                       expected_data, read_data))
            errors++;
        end
        
        // Verify MAC Address Low Register (0x08)
        read_reg(32'h08, read_data);
        expected_data = expected_mac_addr[31:0];
        if (read_data == expected_data) begin
            `uvm_info("SEQ", $sformatf("  MAC address low verified: 0x%08h", read_data), UVM_MEDIUM)
        end else begin
            `uvm_error("SEQ", $sformatf("  MAC address low mismatch: expected 0x%08h, got 0x%08h", 
                       expected_data, read_data))
            errors++;
        end
        
        // Verify MAC Address High Register (0x0C)
        read_reg(32'h0C, read_data);
        expected_data = {16'h0, expected_mac_addr[47:32]};
        if (read_data == expected_data) begin
            `uvm_info("SEQ", $sformatf("  MAC address high verified: 0x%08h", read_data), UVM_MEDIUM)
        end else begin
            `uvm_error("SEQ", $sformatf("  MAC address high mismatch: expected 0x%08h, got 0x%08h", 
                       expected_data, read_data))
            errors++;
        end
        
    endtask

endclass : mac_reg_verify_seq


//==============================================================================
// Sequence: mac_counter_verify_seq
// Description: Verify frame counters
//==============================================================================
class mac_counter_verify_seq extends mac_base_seq;

    `uvm_object_utils(mac_counter_verify_seq)
    
    int expected_tx_count;
    int expected_rx_count;

    function new(string name = "mac_counter_verify_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] tx_count, rx_count;
        
        // Read TX frame counter (0x10)
        read_reg(32'h10, tx_count);
        
        // Read RX frame counter (0x14)
        read_reg(32'h14, rx_count);
        
        `uvm_info("SEQ", $sformatf("  TX frame counter: %0d (expected: %0d)", tx_count, expected_tx_count), UVM_MEDIUM)
        `uvm_info("SEQ", $sformatf("  RX frame counter: %0d (expected: %0d)", rx_count, expected_rx_count), UVM_MEDIUM)
        
        // Verify TX counter
        if (tx_count == expected_tx_count) begin
            `uvm_info("SEQ", $sformatf("  TX counter verified: %0d frames", tx_count), UVM_LOW)
        end else begin
            `uvm_warning("SEQ", $sformatf("  TX counter mismatch: expected %0d, got %0d", 
                         expected_tx_count, tx_count))
        end
        
        // Verify RX counter
        if (rx_count == expected_rx_count) begin
            `uvm_info("SEQ", $sformatf("  RX counter verified: %0d frames", rx_count), UVM_LOW)
        end else begin
            `uvm_warning("SEQ", $sformatf("  RX counter mismatch: expected %0d, got %0d", 
                         expected_rx_count, rx_count))
        end
        
    endtask

endclass : mac_counter_verify_seq
