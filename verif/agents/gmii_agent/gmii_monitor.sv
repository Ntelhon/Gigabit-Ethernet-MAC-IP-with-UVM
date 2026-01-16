//==============================================================================
// Class: gmii_monitor
// Description: UVM Monitor for GMII TX path (monitors data FROM the DUT)
//
// Purpose:
//   Observes Ethernet frames transmitted by the MAC on the GMII TX interface.
//   Reconstructs complete frames from byte stream and sends them to the
//   scoreboard via analysis port.
//
// Monitored Signals:
//   - txd[7:0]  : Transmit data from MAC
//   - tx_en     : Transmit enable
//   - tx_er     : Transmit error
//
// Features:
//   - Preamble and SFD detection
//   - Frame boundary detection via TX_EN
//   - Byte stream reconstruction
//   - CRC32 verification
//   - Error detection (TX_ER, CRC errors, runt frames)
//   - Analysis port for scoreboard integration
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_monitor extends uvm_monitor;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(gmii_monitor)

    //==========================================================================
    // Analysis Port
    //==========================================================================
    uvm_analysis_port #(gmii_frame) frame_port;

    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual gmii_if.tx_monitor vif;

    //==========================================================================
    // Configuration
    //==========================================================================
    
    // Enable CRC checking
    bit check_crc = 1;
    
    // Minimum frame size for runt detection
    int unsigned min_frame_size = 64;

    //==========================================================================
    // Constants
    //==========================================================================
    localparam bit [7:0] PREAMBLE_BYTE = 8'h55;
    localparam bit [7:0] SFD_BYTE      = 8'hD5;

    //==========================================================================
    // Internal State
    //==========================================================================
    typedef enum {
        MON_IDLE,
        MON_PREAMBLE,
        MON_DATA
    } monitor_state_e;

    monitor_state_e state;
    bit [7:0] frame_buffer[$];
    int unsigned preamble_count;
    bit tx_error_seen;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "gmii_monitor", uvm_component parent = null);
        super.new(name, parent);
        frame_port = new("frame_port", this);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual gmii_if.tx_monitor)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not found for gmii_monitor")
        end
    endfunction

    //==========================================================================
    // Run Phase - Main monitor loop
    //==========================================================================
    task run_phase(uvm_phase phase);
        
        // Initialize state
        state = MON_IDLE;
        frame_buffer.delete();
        preamble_count = 0;
        tx_error_seen = 0;
        
        forever begin
            @(vif.tx_mon_cb);
            monitor_cycle();
        end
    endtask

    //==========================================================================
    // Monitor one clock cycle
    //==========================================================================
    task monitor_cycle();
        bit [7:0] data;
        bit       tx_en;
        bit       tx_er;
        
        // Sample signals
        data  = vif.tx_mon_cb.txd;
        tx_en = vif.tx_mon_cb.tx_en;
        tx_er = vif.tx_mon_cb.tx_er;
        
        case (state)
            //------------------------------------------------------------------
            // IDLE: Waiting for TX_EN assertion
            //------------------------------------------------------------------
            MON_IDLE: begin
                if (tx_en) begin
                    if (data == PREAMBLE_BYTE) begin
                        state = MON_PREAMBLE;
                        preamble_count = 1;
                        frame_buffer.delete();
                        tx_error_seen = 0;
                        `uvm_info("GMII_MON", "Preamble detected, frame starting", UVM_HIGH)
                    end else if (data == SFD_BYTE) begin
                        // Short preamble or immediate SFD
                        state = MON_DATA;
                        frame_buffer.delete();
                        tx_error_seen = 0;
                        `uvm_info("GMII_MON", "SFD detected (short preamble)", UVM_HIGH)
                    end
                end
            end
            
            //------------------------------------------------------------------
            // PREAMBLE: Receiving preamble bytes, waiting for SFD
            //------------------------------------------------------------------
            MON_PREAMBLE: begin
                if (!tx_en) begin
                    // Premature end
                    `uvm_warning("GMII_MON", "TX_EN deasserted during preamble")
                    state = MON_IDLE;
                end else if (data == PREAMBLE_BYTE) begin
                    preamble_count++;
                end else if (data == SFD_BYTE) begin
                    state = MON_DATA;
                    `uvm_info("GMII_MON", $sformatf("SFD detected after %0d preamble bytes", 
                              preamble_count), UVM_HIGH)
                end else begin
                    `uvm_warning("GMII_MON", $sformatf("Invalid preamble byte: 0x%02h", data))
                    state = MON_IDLE;
                end
                
                if (tx_er) begin
                    tx_error_seen = 1;
                end
            end
            
            //------------------------------------------------------------------
            // DATA: Receiving frame data until TX_EN deasserts
            //------------------------------------------------------------------
            MON_DATA: begin
                if (!tx_en) begin
                    // End of frame
                    process_frame();
                    state = MON_IDLE;
                end else begin
                    // Capture data byte
                    frame_buffer.push_back(data);
                    `uvm_info("GMII_MON", $sformatf("DATA[%0d] = %02h", frame_buffer.size()-1, data), UVM_DEBUG)
                    
                    if (tx_er) begin
                        tx_error_seen = 1;
                        `uvm_info("GMII_MON", $sformatf("TX_ER asserted at byte %0d", 
                                  frame_buffer.size()), UVM_MEDIUM)
                    end
                end
            end
            
            default: begin
                state = MON_IDLE;
            end
        endcase
    endtask

    //==========================================================================
    // Process completed frame
    //==========================================================================
    task process_frame();
        gmii_frame frame;
        bit [7:0] frame_bytes[];
        bit [31:0] calc_crc;
        bit [31:0] recv_crc;
        int data_len;
        
        if (frame_buffer.size() < 4) begin
            `uvm_warning("GMII_MON", $sformatf("Frame too short: %0d bytes", frame_buffer.size()))
            return;
        end
        
        // Create frame object
        frame = gmii_frame::type_id::create("monitored_frame");
        
        // Record timing
        frame.end_time = $time;
        
        // Copy buffer to array
        frame_bytes = new[frame_buffer.size()];
        foreach (frame_buffer[i]) begin
            frame_bytes[i] = frame_buffer[i];
        end
        
        // Set frame from bytes
        frame.set_from_bytes(frame_bytes);
        
        // Check frame length
        frame.frame_length = frame_buffer.size();
        if (frame.frame_length < min_frame_size) begin
            frame.runt_detected = 1;
            `uvm_info("GMII_MON", $sformatf("Runt frame detected: %0d bytes", 
                      frame.frame_length), UVM_MEDIUM)
        end
        
        // Verify CRC if enabled
        if (check_crc && frame_buffer.size() >= 18) begin
            // Calculate CRC on data (excluding received FCS)
            data_len = frame_buffer.size() - 4;
            calc_crc = calculate_crc(frame_bytes, data_len);
            
            // Get received CRC (last 4 bytes)
            // Ethernet FCS is transmitted LSB first, so:
            // frame_bytes[size-4] = CRC[7:0]   (first transmitted)
            // frame_bytes[size-3] = CRC[15:8]
            // frame_bytes[size-2] = CRC[23:16]
            // frame_bytes[size-1] = CRC[31:24] (last transmitted)
            recv_crc = {frame_bytes[frame_buffer.size()-1],
                        frame_bytes[frame_buffer.size()-2],
                        frame_bytes[frame_buffer.size()-3],
                        frame_bytes[frame_buffer.size()-4]};
            
            if (calc_crc != recv_crc) begin
                frame.crc_error_detected = 1;
                frame.frame_valid = 0;
                `uvm_info("GMII_MON", $sformatf("CRC error: calc=0x%08h recv=0x%08h", 
                          calc_crc, recv_crc), UVM_MEDIUM)
            end else begin
                frame.frame_valid = !tx_error_seen && !frame.runt_detected;
            end
        end
        
        // Log frame info
        `uvm_info("GMII_MON", $sformatf("Frame captured: %0d bytes, valid=%0b, crc_err=%0b, runt=%0b",
                  frame.frame_length, frame.frame_valid, 
                  frame.crc_error_detected, frame.runt_detected), UVM_MEDIUM)
        
        // Send to analysis port
        frame_port.write(frame);
        
    endtask

    //==========================================================================
    // Calculate CRC32
    //==========================================================================
    function bit [31:0] calculate_crc(input bit [7:0] data[], int length);
        bit [31:0] crc;
        bit [31:0] poly;
        int i, j;
        
        crc = 32'hFFFFFFFF;
        poly = 32'hEDB88320;
        
        for (i = 0; i < length; i++) begin
            crc = crc ^ {24'h0, data[i]};
            
            for (j = 0; j < 8; j++) begin
                if (crc[0])
                    crc = (crc >> 1) ^ poly;
                else
                    crc = crc >> 1;
            end
        end
        
        return ~crc;
    endfunction

endclass : gmii_monitor
