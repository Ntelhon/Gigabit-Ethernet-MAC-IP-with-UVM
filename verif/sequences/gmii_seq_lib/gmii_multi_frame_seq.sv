//==============================================================================
// Class: gmii_multi_frame_seq
// Description: GMII sequence for sending multiple frames
//
// Purpose:
//   Sends multiple Ethernet frames to the MAC with configurable inter-frame
//   gap timing.
//
// Usage:
//   gmii_multi_frame_seq seq = gmii_multi_frame_seq::type_id::create("seq");
//   seq.num_frames = 10;
//   seq.frame_size = 64;
//   seq.inter_frame_gap_ns = 960; // 96 bit times
//   seq.start(gmii_sequencer);
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_multi_frame_seq extends uvm_sequence #(gmii_frame);

    `uvm_object_utils(gmii_multi_frame_seq)
    
    //==========================================================================
    // Configuration Properties
    //==========================================================================
    
    int num_frames = 1;
    int frame_size = 64;  // Total frame size including header
    int inter_frame_gap_ns = 960;  // IFG in nanoseconds (96 bit times @ 1Gbps)
    
    // Frame addressing
    bit [47:0] dest_addr = 48'hFFFFFFFFFFFF;  // Broadcast
    bit [47:0] src_addr  = 48'h001122334455;
    bit [15:0] ether_type = 16'h0800;  // IPv4
    
    // Payload pattern
    bit [7:0] payload_pattern = 8'hA5;
    bit randomize_payload = 0;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "gmii_multi_frame_seq");
        super.new(name);
    endfunction
    
    //==========================================================================
    // Body Task
    //==========================================================================
    virtual task body();
        gmii_frame frame;
        
        `uvm_info("GMII_MULTI_FRM_SEQ", $sformatf("Sending %0d frames, size=%0d, IFG=%0dns", 
                  num_frames, frame_size, inter_frame_gap_ns), UVM_MEDIUM)
        
        for (int i = 0; i < num_frames; i++) begin
            // Create frame
            frame = gmii_frame::type_id::create($sformatf("frame_%0d", i));
            
            // Configure frame
            frame.dst_mac = dest_addr;
            frame.src_mac = src_addr;
            frame.ether_type = ether_type;
            
            // Create payload (frame_size - 18 bytes for header + FCS)
            frame.payload = new[frame_size - 18];
            for (int j = 0; j < frame.payload.size(); j++) begin
                if (randomize_payload) begin
                    frame.payload[j] = $urandom_range(0, 255);
                end else begin
                    frame.payload[j] = payload_pattern ^ i[7:0] ^ j[7:0];  // Add variety
                end
            end
            
            frame.has_fcs = 1;
            frame.inject_fcs_error = 0;
            
            // Send frame
            start_item(frame);
            finish_item(frame);
            
            `uvm_info("GMII_MULTI_FRM_SEQ", $sformatf("Sent frame %0d/%0d", i+1, num_frames), UVM_HIGH)
            
            // Inter-frame gap (except after last frame)
            if (i < num_frames - 1) begin
                #(inter_frame_gap_ns * 1ns);
            end
        end
        
        `uvm_info("GMII_MULTI_FRM_SEQ", $sformatf("Completed sending %0d frames", num_frames), UVM_MEDIUM)
    endtask

endclass : gmii_multi_frame_seq
