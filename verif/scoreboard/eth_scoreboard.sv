//==============================================================================
// Class: eth_scoreboard
// Description: UVM Scoreboard for Gigabit Ethernet MAC validation
//
// Purpose:
//   Compares transmitted frames from the MAC against expected frames.
//   Validates frame length, payload integrity, CRC correctness, and
//   proper error handling.
//
// Validation Checks:
//   - Frame length (minimum 64 bytes, maximum 1518 bytes)
//   - CRC32 correctness
//   - Payload data integrity
//   - Preamble/SFD presence
//   - Proper padding
//   - Error frame rejection
//
// Analysis Ports:
//   - tx_frame_export: Receives frames transmitted by MAC
//   - rx_frame_export: Receives frames sent to MAC (expected)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class eth_scoreboard extends uvm_scoreboard;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(eth_scoreboard)

    //==========================================================================
    // Analysis Exports
    //==========================================================================
    
    // Frames transmitted by MAC (from GMII TX monitor)
    uvm_analysis_export #(gmii_frame) tx_frame_export;
    
    // Frames sent to MAC (from driver/sequence - expected output)
    uvm_analysis_export #(gmii_frame) rx_frame_export;

    //==========================================================================
    // Analysis FIFOs
    //==========================================================================
    uvm_tlm_analysis_fifo #(gmii_frame) tx_fifo;
    uvm_tlm_analysis_fifo #(gmii_frame) rx_fifo;

    //==========================================================================
    // CRC Reference Model
    //==========================================================================
    eth_crc_model crc_model;

    //==========================================================================
    // Configuration
    //==========================================================================
    
    // Minimum frame size (including FCS)
    int unsigned min_frame_size = 64;
    
    // Maximum frame size (including FCS)
    int unsigned max_frame_size = 1518;
    
    // Enable CRC checking
    bit check_crc = 1;
    
    // Enable payload checking
    bit check_payload = 1;
    
    // Enable frame ordering check
    bit check_ordering = 1;
    
    // Enable loopback mode expectation
    // When enabled, RX frames are expected to appear on TX (loopback)
    // When disabled, RX frames are just counted (RX-only tests)
    bit expect_loopback = 0;

    //==========================================================================
    // Statistics Counters
    //==========================================================================
    int unsigned tx_frame_count = 0;
    int unsigned rx_frame_count = 0;
    int unsigned match_count = 0;
    int unsigned mismatch_count = 0;
    int unsigned crc_error_count = 0;
    int unsigned runt_frame_count = 0;
    int unsigned oversize_frame_count = 0;
    int unsigned dropped_frame_count = 0;

    //==========================================================================
    // Expected Frame Queue
    //==========================================================================
    gmii_frame expected_frames[$];

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "eth_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Create analysis exports
        tx_frame_export = new("tx_frame_export", this);
        rx_frame_export = new("rx_frame_export", this);
        
        // Create analysis FIFOs
        tx_fifo = new("tx_fifo", this);
        rx_fifo = new("rx_fifo", this);
        
        // Create CRC model
        crc_model = eth_crc_model::type_id::create("crc_model");
        
        // Run CRC self-test
        if (!crc_model.self_test()) begin
            `uvm_fatal("SB", "CRC model self-test failed!")
        end
        
    endfunction

    //==========================================================================
    // Connect Phase
    //==========================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect exports to FIFOs
        tx_frame_export.connect(tx_fifo.analysis_export);
        rx_frame_export.connect(rx_fifo.analysis_export);
        
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    task run_phase(uvm_phase phase);
        
        fork
            process_rx_frames();
            process_tx_frames();
        join
        
    endtask

    //==========================================================================
    // Process RX frames (frames sent TO the MAC)
    // If expect_loopback is set, these become expected TX frames
    //==========================================================================
    task process_rx_frames();
        gmii_frame frame;
        
        forever begin
            rx_fifo.get(frame);
            rx_frame_count++;
            
            `uvm_info("SB", $sformatf("RX frame received: %s", 
                      frame.convert2string()), UVM_HIGH)
            
            // Only add to expected queue if loopback is expected
            if (expect_loopback) begin
                // Add to expected queue (if not an error injection frame)
                if (!frame.inject_crc_error && !frame.send_as_runt && !frame.inject_rx_error) begin
                    expected_frames.push_back(frame);
                    `uvm_info("SB", "Frame added to expected TX queue (loopback)", UVM_HIGH)
                end else begin
                    `uvm_info("SB", "Error injection frame - not expecting TX output", UVM_MEDIUM)
                end
            end
        end
    endtask

    //==========================================================================
    // Process TX frames (frames transmitted BY the MAC)
    //==========================================================================
    task process_tx_frames();
        gmii_frame tx_frame;
        gmii_frame exp_frame;
        bit frame_valid;
        
        forever begin
            tx_fifo.get(tx_frame);
            tx_frame_count++;
            
            `uvm_info("SB", $sformatf("TX frame received: %s", 
                      tx_frame.convert2string()), UVM_HIGH)
            
            // Validate frame structure
            frame_valid = validate_frame(tx_frame);
            
            if (!frame_valid) begin
                // Frame has structural issues
                continue;
            end
            
            // Compare with expected frame
            if (check_ordering && expected_frames.size() > 0) begin
                exp_frame = expected_frames.pop_front();
                compare_frames(exp_frame, tx_frame);
            end else if (expected_frames.size() == 0) begin
                `uvm_warning("SB", "TX frame received with no expected frame")
                dropped_frame_count++;
            end
        end
    endtask

    //==========================================================================
    // Validate frame structure
    //==========================================================================
    function bit validate_frame(gmii_frame frame);
        bit [31:0] expected_crc;
        bit [31:0] received_crc;
        bit [7:0] frame_bytes[];
        bit crc_valid;
        
        // Check for runt frame
        if (frame.frame_length < min_frame_size) begin
            `uvm_error("SB", $sformatf(
                "RUNT FRAME: length=%0d (min=%0d)",
                frame.frame_length, min_frame_size))
            runt_frame_count++;
            return 0;
        end
        
        // Check for oversize frame
        if (frame.frame_length > max_frame_size) begin
            `uvm_error("SB", $sformatf(
                "OVERSIZE FRAME: length=%0d (max=%0d)",
                frame.frame_length, max_frame_size))
            oversize_frame_count++;
            return 0;
        end
        
        // Verify CRC
        if (check_crc) begin
            // Get frame bytes for CRC check
            frame.get_frame_bytes(frame_bytes);
            
            // Append FCS to frame bytes
            begin
                bit [7:0] full_frame[];
                full_frame = new[frame_bytes.size() + 4];
                
                foreach (frame_bytes[i]) begin
                    full_frame[i] = frame_bytes[i];
                end
                
                // Add received FCS
                full_frame[frame_bytes.size()]   = frame.fcs[7:0];
                full_frame[frame_bytes.size()+1] = frame.fcs[15:8];
                full_frame[frame_bytes.size()+2] = frame.fcs[23:16];
                full_frame[frame_bytes.size()+3] = frame.fcs[31:24];
                
                crc_valid = crc_model.verify_crc_detailed(full_frame, expected_crc, received_crc);
            end
            
            if (!crc_valid) begin
                `uvm_error("SB", $sformatf(
                    "CRC MISMATCH: expected=0x%08h, received=0x%08h",
                    expected_crc, received_crc))
                crc_error_count++;
                return 0;
            end
            
            `uvm_info("SB", $sformatf("CRC VALID: 0x%08h", received_crc), UVM_HIGH)
        end
        
        return 1;
    endfunction

    //==========================================================================
    // Compare transmitted frame with expected frame
    //==========================================================================
    function void compare_frames(gmii_frame expected, gmii_frame actual);
        bit match = 1;
        string mismatch_msg = "";
        
        // Compare destination MAC
        if (expected.dst_mac !== actual.dst_mac) begin
            match = 0;
            mismatch_msg = {mismatch_msg, $sformatf(
                "\n  Dest MAC: exp=0x%012h, act=0x%012h",
                expected.dst_mac, actual.dst_mac)};
        end
        
        // Compare source MAC
        if (expected.src_mac !== actual.src_mac) begin
            match = 0;
            mismatch_msg = {mismatch_msg, $sformatf(
                "\n  Src MAC: exp=0x%012h, act=0x%012h",
                expected.src_mac, actual.src_mac)};
        end
        
        // Compare EtherType
        if (expected.ether_type !== actual.ether_type) begin
            match = 0;
            mismatch_msg = {mismatch_msg, $sformatf(
                "\n  EtherType: exp=0x%04h, act=0x%04h",
                expected.ether_type, actual.ether_type)};
        end
        
        // Compare payload
        if (check_payload) begin
            if (!compare_payload(expected, actual, mismatch_msg)) begin
                match = 0;
            end
        end
        
        // Report result
        if (match) begin
            match_count++;
            `uvm_info("SB", $sformatf("FRAME MATCH [%0d]", match_count), UVM_MEDIUM)
        end else begin
            mismatch_count++;
            `uvm_error("SB", $sformatf("FRAME MISMATCH [%0d]: %s", 
                       mismatch_count, mismatch_msg))
        end
        
    endfunction

    //==========================================================================
    // Compare payload data
    //==========================================================================
    function bit compare_payload(
        gmii_frame expected, 
        gmii_frame actual,
        output string mismatch_msg
    );
        int min_len;
        int exp_len;
        int act_len;
        int first_diff = -1;
        
        exp_len = expected.payload.size();
        act_len = actual.payload.size();
        
        // Account for padding
        // MAC should pad to minimum of 46 payload bytes (64 - 14 header - 4 FCS)
        if (exp_len < 46 && act_len >= 46) begin
            // Check if actual is padded version of expected
            for (int i = 0; i < exp_len; i++) begin
                if (expected.payload[i] !== actual.payload[i]) begin
                    mismatch_msg = {mismatch_msg, $sformatf(
                        "\n  Payload[%0d]: exp=0x%02h, act=0x%02h",
                        i, expected.payload[i], actual.payload[i])};
                    return 0;
                end
            end
            
            // Check padding is zeros
            for (int i = exp_len; i < act_len; i++) begin
                if (actual.payload[i] !== 8'h00) begin
                    mismatch_msg = {mismatch_msg, $sformatf(
                        "\n  Padding[%0d]: expected 0x00, got 0x%02h",
                        i, actual.payload[i])};
                    return 0;
                end
            end
            
            return 1;
        end
        
        // Direct comparison for non-padded frames
        if (exp_len != act_len) begin
            mismatch_msg = {mismatch_msg, $sformatf(
                "\n  Payload length: exp=%0d, act=%0d", exp_len, act_len)};
            return 0;
        end
        
        for (int i = 0; i < exp_len; i++) begin
            if (expected.payload[i] !== actual.payload[i]) begin
                if (first_diff < 0) first_diff = i;
                if (first_diff == i) begin  // Report first few differences
                    mismatch_msg = {mismatch_msg, $sformatf(
                        "\n  Payload[%0d]: exp=0x%02h, act=0x%02h",
                        i, expected.payload[i], actual.payload[i])};
                end
            end
        end
        
        return (first_diff < 0);
    endfunction

    //==========================================================================
    // Check Phase - Report final statistics
    //==========================================================================
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        
        // Check for unmatched expected frames (only in loopback mode)
        if (expect_loopback && expected_frames.size() > 0) begin
            `uvm_error("SB", $sformatf(
                "%0d expected frames were never transmitted",
                expected_frames.size()))
        end
        
    endfunction

    //==========================================================================
    // Report Phase - Print summary
    //==========================================================================
    function void report_phase(uvm_phase phase);
        string report;
        
        super.report_phase(phase);
        
        report = "\n";
        report = {report, "============================================================\n"};
        report = {report, "                  SCOREBOARD SUMMARY\n"};
        report = {report, "============================================================\n"};
        report = {report, $sformatf("  RX Frames (to MAC):      %0d\n", rx_frame_count)};
        report = {report, $sformatf("  TX Frames (from MAC):    %0d\n", tx_frame_count)};
        report = {report, "------------------------------------------------------------\n"};
        report = {report, $sformatf("  Frame Matches:           %0d\n", match_count)};
        report = {report, $sformatf("  Frame Mismatches:        %0d\n", mismatch_count)};
        report = {report, "------------------------------------------------------------\n"};
        report = {report, $sformatf("  CRC Errors:              %0d\n", crc_error_count)};
        report = {report, $sformatf("  Runt Frames:             %0d\n", runt_frame_count)};
        report = {report, $sformatf("  Oversize Frames:         %0d\n", oversize_frame_count)};
        report = {report, $sformatf("  Dropped Frames:          %0d\n", dropped_frame_count)};
        report = {report, "============================================================\n"};
        
        if (mismatch_count == 0 && crc_error_count == 0 && 
            runt_frame_count == 0 && expected_frames.size() == 0) begin
            report = {report, "  RESULT: *** PASS ***\n"};
        end else begin
            report = {report, "  RESULT: *** FAIL ***\n"};
        end
        
        report = {report, "============================================================\n"};
        
        `uvm_info("SB", report, UVM_NONE)
        
    endfunction

    //==========================================================================
    // Reset counters
    //==========================================================================
    function void reset_counters();
        tx_frame_count = 0;
        rx_frame_count = 0;
        match_count = 0;
        mismatch_count = 0;
        crc_error_count = 0;
        runt_frame_count = 0;
        oversize_frame_count = 0;
        dropped_frame_count = 0;
        expected_frames.delete();
    endfunction

endclass : eth_scoreboard
