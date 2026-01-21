//==============================================================================
// Sequence: mac_tx_frame_seq
// Description: TX frame generation sequence for MAC transmit path testing
//
// Purpose:
//   Generates Ethernet frames on the AXI-Stream TX interface to test the
//   MAC's transmit path. The MAC receives data via AXI-Stream, adds preamble,
//   SFD, and CRC, then outputs on GMII TX interface.
//
// Frame Generation:
//   - Builds Ethernet header (DA, SA, EtherType)
//   - Adds payload data
//   - Does NOT add CRC (MAC adds CRC automatically)
//
// Usage:
//   Start this sequence to send frames through the MAC TX path.
//   Monitor gmii_monitor to capture transmitted frames.
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_tx_frame_seq extends mac_base_seq;

    `uvm_object_utils(mac_tx_frame_seq)

    //==========================================================================
    // Configuration
    //==========================================================================
    
    // Frame parameters
    int unsigned num_frames = 1;
    int unsigned frame_size = 64;      // Min frame size (header + payload)
    int unsigned inter_frame_gap = 12; // IFG in bytes (96 bits = 12 bytes)
    
    // Destination MAC address
    bit [47:0] dst_mac = 48'hFF_FF_FF_FF_FF_FF;  // Broadcast by default
    
    // Source MAC address
    bit [47:0] src_mac = 48'h00_11_22_33_44_55;
    
    // EtherType
    bit [15:0] ether_type = 16'h0800;  // IPv4
    
    // Payload pattern
    bit [7:0] payload_pattern = 8'hA5;
    
    // Randomize payload
    bit randomize_payload = 0;

    // Virtual interface
    virtual axi_stream_if axis_vif;

    //==========================================================================
    // Constructor
    //==========================================================================
    
    function new(string name = "mac_tx_frame_seq");
        super.new(name);
    endfunction

    //==========================================================================
    // Body
    //==========================================================================
    
    virtual task body();
        logic [7:0] frame_data[];
        int frame_len;
        
        // Get virtual interface
        if (!uvm_config_db#(virtual axi_stream_if)::get(null, "*", "axis_vif", axis_vif)) begin
            `uvm_fatal("TX_SEQ", "Failed to get axis_vif from config_db")
        end
        
        `uvm_info("TX_SEQ", $sformatf("Starting TX sequence: %0d frames, size=%0d", 
                  num_frames, frame_size), UVM_MEDIUM)
        
        // Wait for reset to complete
        axis_vif.wait_reset_done();
        
        // Send frames
        for (int i = 0; i < num_frames; i++) begin
            // Build frame
            build_frame(frame_data, frame_len);
            
            `uvm_info("TX_SEQ", $sformatf("Sending TX frame %0d/%0d, len=%0d", 
                      i+1, num_frames, frame_len), UVM_HIGH)
            
            // Send frame via AXI-Stream
            send_frame_axis(frame_data, frame_len);
            
            // Inter-frame gap
            if (i < num_frames - 1) begin
                repeat (inter_frame_gap) @(posedge axis_vif.aclk);
            end
        end
        
        `uvm_info("TX_SEQ", "TX sequence complete", UVM_MEDIUM)
    endtask

    //==========================================================================
    // Build Frame
    //==========================================================================
    
    virtual function void build_frame(
        output logic [7:0] frame_data[],
        output int frame_len
    );
        int payload_len;
        int idx;
        
        // Calculate payload length (frame_size = header(14) + payload)
        // Note: CRC is added by MAC, not included in frame_size here
        payload_len = frame_size - 14;
        if (payload_len < 46) payload_len = 46;  // Minimum payload for 64-byte frame
        
        frame_len = 14 + payload_len;
        frame_data = new[frame_len];
        
        idx = 0;
        
        // Destination MAC (6 bytes)
        frame_data[idx++] = dst_mac[47:40];
        frame_data[idx++] = dst_mac[39:32];
        frame_data[idx++] = dst_mac[31:24];
        frame_data[idx++] = dst_mac[23:16];
        frame_data[idx++] = dst_mac[15:8];
        frame_data[idx++] = dst_mac[7:0];
        
        // Source MAC (6 bytes)
        frame_data[idx++] = src_mac[47:40];
        frame_data[idx++] = src_mac[39:32];
        frame_data[idx++] = src_mac[31:24];
        frame_data[idx++] = src_mac[23:16];
        frame_data[idx++] = src_mac[15:8];
        frame_data[idx++] = src_mac[7:0];
        
        // EtherType (2 bytes)
        frame_data[idx++] = ether_type[15:8];
        frame_data[idx++] = ether_type[7:0];
        
        // Payload
        for (int i = 0; i < payload_len; i++) begin
            if (randomize_payload) begin
                frame_data[idx++] = $urandom_range(0, 255);
            end else begin
                frame_data[idx++] = payload_pattern;
            end
        end
    endfunction

    //==========================================================================
    // Send Frame via AXI-Stream
    //==========================================================================
    
    virtual task send_frame_axis(
        input logic [7:0] frame_data[],
        input int frame_len
    );
        for (int i = 0; i < frame_len; i++) begin
            // Wait for tready - sample directly without clocking block
            @(posedge axis_vif.aclk);
            while (!axis_vif.tready) begin
                @(posedge axis_vif.aclk);
            end
            
            // Drive data directly (non-blocking to avoid delta cycle issues)
            axis_vif.tdata  <= frame_data[i];
            axis_vif.tvalid <= 1'b1;
            axis_vif.tuser  <= (i == 0) ? 1'b1 : 1'b0;  // SOF
            axis_vif.tlast  <= (i == frame_len - 1) ? 1'b1 : 1'b0;  // EOF
        end
        
        // Wait one cycle then deassert valid
        @(posedge axis_vif.aclk);
        axis_vif.tvalid <= 1'b0;
        axis_vif.tlast  <= 1'b0;
        axis_vif.tuser  <= 1'b0;
        
        @(posedge axis_vif.aclk);
    endtask

endclass : mac_tx_frame_seq

