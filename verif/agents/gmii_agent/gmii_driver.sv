//==============================================================================
// Class: gmii_driver
// Description: UVM Driver for GMII RX path (drives data TO the DUT)
//
// Purpose:
//   Acts as a behavioral PHY model, driving Ethernet frames into the MAC's
//   RX interface. Generates preamble, SFD, frame data, and FCS according
//   to GMII timing at 125 MHz.
//
// Driven Signals:
//   - rxd[7:0]  : Receive data to MAC
//   - rx_dv     : Receive data valid
//   - rx_er     : Receive error
//
// Features:
//   - Correct preamble (7 × 0x55) and SFD (0xD5) generation
//   - CRC32 calculation and transmission
//   - Automatic padding to minimum frame size (optional)
//   - Error injection: CRC errors, runt frames, IFG violations, RX_ER
//   - Clock-accurate GMII timing
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_driver extends uvm_driver #(gmii_frame);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(gmii_driver)

    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual gmii_if.rx_driver vif;

    //==========================================================================
    // Analysis Port - broadcasts frames driven to MAC
    //==========================================================================
    uvm_analysis_port #(gmii_frame) frame_port;

    //==========================================================================
    // Configuration
    //==========================================================================
    
    // Enable automatic padding to 64 bytes
    bit enable_padding = 1;
    
    // Minimum frame size (excluding preamble/SFD, including FCS)
    int unsigned min_frame_size = 64;
    
    // Default IFG in bytes
    int unsigned default_ifg = 12;

    //==========================================================================
    // Constants
    //==========================================================================
    localparam bit [7:0] PREAMBLE_BYTE = 8'h55;
    localparam bit [7:0] SFD_BYTE      = 8'hD5;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "gmii_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Create analysis port for driven frames
        frame_port = new("frame_port", this);
        
        if (!uvm_config_db#(virtual gmii_if.rx_driver)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not found for gmii_driver")
        end
    endfunction

    //==========================================================================
    // Run Phase - Main driver loop
    //==========================================================================
    task run_phase(uvm_phase phase);
        gmii_frame frame;
        
        // Initialize signals
        reset_signals();
        
        forever begin
            // Wait for reset to be released
            wait_for_reset_release();
            
            // Get next frame from sequencer
            seq_item_port.get_next_item(frame);
            
            `uvm_info("GMII_DRV", $sformatf("Driving frame: %s", frame.convert2string()), UVM_MEDIUM)
            
            // Drive the frame
            drive_frame(frame);
            
            // Broadcast frame to analysis port (for scoreboard tracking)
            frame_port.write(frame);
            
            // Signal completion
            seq_item_port.item_done();
        end
    endtask

    //==========================================================================
    // Reset signals to idle state
    //==========================================================================
    task reset_signals();
        @(vif.rx_drv_cb);
        vif.rx_drv_cb.rxd   <= 8'h00;
        vif.rx_drv_cb.rx_dv <= 1'b0;
        vif.rx_drv_cb.rx_er <= 1'b0;
        vif.rx_drv_cb.col   <= 1'b0;
        vif.rx_drv_cb.crs   <= 1'b0;
    endtask

    //==========================================================================
    // Wait for reset release
    //==========================================================================
    task wait_for_reset_release();
        // Simple wait - in real implementation, monitor reset signal
        @(vif.rx_drv_cb);
    endtask

    //==========================================================================
    // Drive a complete Ethernet frame
    //==========================================================================
    task drive_frame(gmii_frame frame);
        bit [7:0] frame_bytes[];
        bit [7:0] padded_frame[];
        bit [31:0] crc;
        int unsigned ifg;
        int total_data_len;
        
        // Record start time
        frame.start_time = $time;
        
        // Get frame bytes (header + payload)
        frame.get_frame_bytes(frame_bytes);
        
        // Handle padding
        if (!frame.send_as_runt && enable_padding) begin
            total_data_len = frame_bytes.size() + 4;  // +4 for FCS
            if (total_data_len < min_frame_size) begin
                int pad_bytes = min_frame_size - 4 - frame_bytes.size();
                padded_frame = new[frame_bytes.size() + pad_bytes];
                foreach (frame_bytes[i]) padded_frame[i] = frame_bytes[i];
                for (int i = frame_bytes.size(); i < padded_frame.size(); i++) begin
                    padded_frame[i] = 8'h00;  // Pad with zeros
                end
                frame_bytes = padded_frame;
            end
        end
        
        // Calculate CRC
        crc = calculate_crc(frame_bytes);
        
        // Inject CRC error if requested
        if (frame.inject_crc_error) begin
            crc = crc ^ 32'hDEADBEEF;
        end
        
        // Assert carrier sense
        vif.rx_drv_cb.crs <= 1'b1;
        
        // Drive preamble
        drive_preamble(frame.preamble_bytes);
        
        // Drive SFD
        drive_byte(SFD_BYTE, 1'b0, 1'b0);
        
        // Drive frame data
        drive_data(frame_bytes, frame.inject_rx_error, frame.rx_error_byte_pos);
        
        // Drive FCS (4 bytes, LSB first)
        drive_byte(crc[7:0],   1'b0, 1'b0);
        drive_byte(crc[15:8],  1'b0, 1'b0);
        drive_byte(crc[23:16], 1'b0, 1'b0);
        drive_byte(crc[31:24], 1'b0, 1'b0);
        
        // Deassert data valid
        @(vif.rx_drv_cb);
        vif.rx_drv_cb.rxd   <= 8'h00;
        vif.rx_drv_cb.rx_dv <= 1'b0;
        vif.rx_drv_cb.rx_er <= 1'b0;
        vif.rx_drv_cb.crs   <= 1'b0;
        
        // Record end time
        frame.end_time = $time;
        
        // Inter-frame gap
        ifg = frame.inject_ifg_violation ? frame.ifg_bytes : default_ifg;
        drive_ifg(ifg);
        
    endtask

    //==========================================================================
    // Drive preamble bytes
    //==========================================================================
    task drive_preamble(int unsigned num_bytes);
        for (int i = 0; i < num_bytes; i++) begin
            drive_byte(PREAMBLE_BYTE, 1'b0, 1'b0);
        end
    endtask

    //==========================================================================
    // Drive a single byte on GMII
    //==========================================================================
    task drive_byte(bit [7:0] data, bit rx_error, bit is_preamble);
        @(vif.rx_drv_cb);
        vif.rx_drv_cb.rxd   <= data;
        vif.rx_drv_cb.rx_dv <= 1'b1;
        vif.rx_drv_cb.rx_er <= rx_error;
    endtask

    //==========================================================================
    // Drive frame data bytes
    //==========================================================================
    task drive_data(input bit [7:0] data[], bit inject_error, int unsigned error_pos);
        for (int i = 0; i < data.size(); i++) begin
            bit rx_err = inject_error && (i == error_pos);
            drive_byte(data[i], rx_err, 1'b0);
        end
    endtask

    //==========================================================================
    // Drive inter-frame gap (idle)
    //==========================================================================
    task drive_ifg(int unsigned num_bytes);
        for (int i = 0; i < num_bytes; i++) begin
            @(vif.rx_drv_cb);
            vif.rx_drv_cb.rxd   <= 8'h00;
            vif.rx_drv_cb.rx_dv <= 1'b0;
            vif.rx_drv_cb.rx_er <= 1'b0;
        end
    endtask

    //==========================================================================
    // Calculate CRC32 for frame data
    // Standard Ethernet CRC32 with reflected polynomial
    //==========================================================================
    function bit [31:0] calculate_crc(input bit [7:0] data[]);
        bit [31:0] crc;
        bit [31:0] poly;
        int i, j;
        
        crc = 32'hFFFFFFFF;
        poly = 32'hEDB88320;  // Reflected polynomial
        
        for (i = 0; i < data.size(); i++) begin
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

endclass : gmii_driver
