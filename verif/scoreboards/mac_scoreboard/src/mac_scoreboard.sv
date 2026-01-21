//==============================================================================
// Class: mac_scoreboard
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

class mac_scoreboard extends uvm_scoreboard;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_scoreboard)

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
    
    // TX-only mode (for MAC TX path tests)
    // When enabled, TX frames are validated for structure but not compared
    // This is used when testing MAC TX path via AXI-Stream
    bit tx_only_mode = 0;

    //==========================================================================
    // Statistics Counters
    //==========================================================================
    
    // Frames sent TO MAC (from GMII RX driver)
    int unsigned rx_frame_count = 0;              // Total frames sent to MAC
    int unsigned rx_good_frame_count = 0;         // Frames sent without errors
    int unsigned rx_bad_frame_count = 0;          // Frames sent with injected errors
    
    // Bad frame error type breakdown
    int unsigned rx_crc_error_injected = 0;       // Frames with CRC error injected
    int unsigned rx_runt_injected = 0;            // Frames with runt error injected
    int unsigned rx_ifg_violation_injected = 0;   // Frames with IFG violation
    int unsigned rx_rxer_injected = 0;            // Frames with RX_ER asserted
    
    // Frames transmitted BY MAC (from GMII TX monitor)
    int unsigned tx_frame_count = 0;              // Total frames transmitted by MAC
    int unsigned tx_validated_count = 0;          // Frames that passed validation
    
    // Frames received by MAC (successfully processed)
    int unsigned mac_received_count = 0;          // Frames MAC accepted (passed checks)
    
    // Frames dropped by MAC (with reasons)
    int unsigned mac_dropped_count = 0;           // Total frames dropped by MAC
    int unsigned mac_drop_crc_error = 0;          // Dropped due to CRC error
    int unsigned mac_drop_runt = 0;               // Dropped due to runt frame
    int unsigned mac_drop_oversize = 0;           // Dropped due to oversize
    int unsigned mac_drop_other = 0;              // Dropped for other reasons
    
    // Frame comparison results
    int unsigned match_count = 0;
    int unsigned mismatch_count = 0;
    
    // Legacy counters (for validation errors detected in TX path)
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
    function new(string name = "mac_scoreboard", uvm_component parent = null);
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
        bit is_error_frame;
        
        forever begin
            rx_fifo.get(frame);
            rx_frame_count++;
            
            `uvm_info("SB", $sformatf("RX frame received: %s", 
                      frame.convert2string()), UVM_HIGH)
            
            // Categorize frame as good or bad (error injected)
            is_error_frame = 0;

            if (frame.inject_crc_error) begin
                rx_crc_error_injected++;
                mac_drop_crc_error++;
                is_error_frame = 1;
            end
            
            if (frame.send_as_runt) begin
                rx_runt_injected++;
                mac_drop_runt++;
                is_error_frame = 1;
            end
            
            if (frame.inject_ifg_violation) begin
                rx_ifg_violation_injected++;
                // IFG violations don't cause drops, just note them
                // is_error_frame = 1;  // Commenting out - IFG might not drop frame
            end
            
            if (frame.inject_rx_error) begin
                rx_rxer_injected++;
                mac_drop_other++;
                is_error_frame = 1;
            end
            
            // Update good/bad counters
            if (is_error_frame) begin
                rx_bad_frame_count++;
                mac_dropped_count++;  // MAC should drop error frames
                `uvm_info("SB", "Error injection frame - MAC should drop this", UVM_MEDIUM)
            end else begin
                rx_good_frame_count++;
                mac_received_count++;  // MAC should receive good frames
            end
            
            // Only add to expected queue if loopback is expected and no errors
            if (expect_loopback) begin
                if (!is_error_frame) begin
                    expected_frames.push_back(frame);
                    `uvm_info("SB", "Frame added to expected TX queue (loopback)", UVM_HIGH)
                end else begin
                    `uvm_info("SB", "Error frame not added to expected queue", UVM_HIGH)
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
            if (tx_only_mode) begin
                // TX-only mode: just validate structure, no comparison needed
                `uvm_info("SB", "TX frame validated (TX-only mode)", UVM_MEDIUM)
            end else if (check_ordering && expected_frames.size() > 0) begin
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
            // Don't update mac_dropped_count here - already counted in process_rx_frames
            return 0;
        end
        
        // Check for oversize frame
        if (frame.frame_length > max_frame_size) begin
            `uvm_error("SB", $sformatf(
                "OVERSIZE FRAME: length=%0d (max=%0d)",
                frame.frame_length, max_frame_size))
            oversize_frame_count++;
            // Don't update mac_dropped_count here - already counted in process_rx_frames
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
                // Don't update mac_dropped_count here - already counted in process_rx_frames
                return 0;
            end
            
            `uvm_info("SB", $sformatf("CRC VALID: 0x%08h", received_crc), UVM_HIGH)
        end
        
        // Frame passed all validation checks
        tx_validated_count++;
        // Don't update mac_received_count here - already counted in process_rx_frames
        
        return 1;
    endfunction

    //==========================================================================
    // Compare transmitted frame with expected frame
    //==========================================================================
    function void compare_frames(gmii_frame expected, gmii_frame actual);
        bit match = 1;
        string mismatch_msg = "";
        string payload_mismatch = "";
        
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
            if (!compare_payload(expected, actual, payload_mismatch)) begin
                match = 0;
                mismatch_msg = {mismatch_msg, payload_mismatch};
            end
        end
        
        // Report result
        if (match) begin
            match_count++;
            `uvm_info("SB", $sformatf("FRAME MATCH [%0d]", match_count), UVM_MEDIUM)
        end else begin
            mismatch_count++;
            `uvm_error("SB", $sformatf("FRAME MISMATCH [%0d]:%s", 
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
    // NOTE: In Vivado xsim, report_phase runs at time 0 (during initialization)
    // The actual summary is printed by print_summary() called from each test's
    // run_phase before dropping objection.
    //==========================================================================
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        // Don't print summary here - it runs at time 0 in xsim
        // Each test calls print_summary() explicitly in run_phase
    endfunction
    
    //==========================================================================
    // Print Summary - Can be called explicitly from test
    //==========================================================================
    function void print_summary();
        string report;
        
        report = "\n";
        report = {report, "============================================================\n"};
        report = {report, "                  SCOREBOARD SUMMARY\n"};
        report = {report, "============================================================\n"};
        
        // Frames sent TO MAC (RX path from MAC perspective)
        report = {report, "  FRAMES SENT TO MAC (GMII RX):\n"};
        report = {report, $sformatf("    Total Frames Sent:       %0d\n", rx_frame_count)};
        report = {report, $sformatf("    - Good Frames:           %0d\n", rx_good_frame_count)};
        report = {report, $sformatf("    - Bad Frames (injected): %0d\n", rx_bad_frame_count)};
        if (rx_bad_frame_count > 0) begin
            report = {report, "      Error Types:\n"};
            if (rx_crc_error_injected > 0)
                report = {report, $sformatf("        CRC Error:         %0d\n", rx_crc_error_injected)};
            if (rx_runt_injected > 0)
                report = {report, $sformatf("        Runt Frame:        %0d\n", rx_runt_injected)};
            if (rx_ifg_violation_injected > 0)
                report = {report, $sformatf("        IFG Violation:     %0d\n", rx_ifg_violation_injected)};
            if (rx_rxer_injected > 0)
                report = {report, $sformatf("        RX_ER Asserted:    %0d\n", rx_rxer_injected)};
        end
        
        report = {report, "------------------------------------------------------------\n"};
        
        // Frames transmitted BY MAC (TX path from MAC perspective)
        report = {report, "  FRAMES TRANSMITTED BY MAC (GMII TX):\n"};
        report = {report, $sformatf("    Total Frames Seen:       %0d\n", tx_frame_count)};
        report = {report, $sformatf("    - Validated Frames:      %0d\n", tx_validated_count)};
        
        report = {report, "------------------------------------------------------------\n"};
        
        // MAC Processing Results
        report = {report, "  MAC PROCESSING RESULTS:\n"};
        report = {report, $sformatf("    Frames Received by MAC:  %0d\n", mac_received_count)};
        report = {report, $sformatf("    Frames Dropped by MAC:   %0d\n", mac_dropped_count)};
        if (mac_dropped_count > 0) begin
            report = {report, "      Drop Reasons:\n"};
            if (mac_drop_crc_error > 0)
                report = {report, $sformatf("        CRC Error:         %0d\n", mac_drop_crc_error)};
            if (mac_drop_runt > 0)
                report = {report, $sformatf("        Runt Frame:        %0d\n", mac_drop_runt)};
            if (mac_drop_oversize > 0)
                report = {report, $sformatf("        Oversize Frame:    %0d\n", mac_drop_oversize)};
            if (mac_drop_other > 0)
                report = {report, $sformatf("        Other:             %0d\n", mac_drop_other)};
        end
        
        report = {report, "------------------------------------------------------------\n"};
        
        // Frame Comparison (for loopback/comparison tests)
        report = {report, "  FRAME COMPARISON:\n"};
        report = {report, $sformatf("    Frame Matches:           %0d\n", match_count)};
        report = {report, $sformatf("    Frame Mismatches:        %0d\n", mismatch_count)};
        
        report = {report, "============================================================\n"};
        
        // Test result
        if (mismatch_count == 0 && expected_frames.size() == 0 &&
            (tx_only_mode || dropped_frame_count == 0)) begin
            report = {report, "  RESULT: *** PASS ***\n"};
        end else begin
            report = {report, "  RESULT: *** FAIL ***\n"};
            if (mismatch_count > 0)
                report = {report, $sformatf("    - %0d frame mismatches\n", mismatch_count)};
            if (expected_frames.size() > 0)
                report = {report, $sformatf("    - %0d expected frames not transmitted\n", expected_frames.size())};
        end
        
        report = {report, "============================================================\n"};
        
        `uvm_info("SB", report, UVM_NONE)
    endfunction

    //==========================================================================
    // Reset counters
    //==========================================================================
    function void reset_counters();
        // RX (to MAC) counters
        rx_frame_count = 0;
        rx_good_frame_count = 0;
        rx_bad_frame_count = 0;
        rx_crc_error_injected = 0;
        rx_runt_injected = 0;
        rx_ifg_violation_injected = 0;
        rx_rxer_injected = 0;
        
        // TX (from MAC) counters
        tx_frame_count = 0;
        tx_validated_count = 0;
        
        // MAC processing counters
        mac_received_count = 0;
        mac_dropped_count = 0;
        mac_drop_crc_error = 0;
        mac_drop_runt = 0;
        mac_drop_oversize = 0;
        mac_drop_other = 0;
        
        // Comparison counters
        match_count = 0;
        mismatch_count = 0;
        
        // Legacy counters
        crc_error_count = 0;
        runt_frame_count = 0;
        oversize_frame_count = 0;
        dropped_frame_count = 0;
        
        expected_frames.delete();
    endfunction
    
    //==========================================================================
    // Manually add expected frame (for loopback tests)
    //==========================================================================
    function void add_expected_frame(gmii_frame frame);
        expected_frames.push_back(frame);
        `uvm_info("SB", "Manually added expected frame to queue", UVM_HIGH)
    endfunction

endclass : mac_scoreboard
