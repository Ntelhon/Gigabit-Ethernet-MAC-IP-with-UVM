//==============================================================================
// Class: axi_stream_txn
// Description: AXI-Stream transaction representing an Ethernet frame
//
// Purpose:
//   Encapsulates all data and control fields for an Ethernet frame
//   transferred via AXI-Stream interface. Used for both TX and RX paths.
//
// Fields:
//   - Frame data (complete Ethernet frame: DA + SA + Type + Payload)
//   - Control flags for error injection and verification
//
// Notes:
//   - FCS is NOT included (added/checked by MAC)
//   - Preamble/SFD is NOT included (added/stripped by MAC)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_stream_txn extends uvm_sequence_item;

    //==========================================================================
    // Frame Data
    //==========================================================================
    
    // Complete frame data (DA + SA + Type + Payload, no FCS)
    rand bit [7:0] data[];
    
    // Frame metadata
    bit [47:0] dst_mac;      // Destination MAC (extracted from data)
    bit [47:0] src_mac;      // Source MAC (extracted from data)
    bit [15:0] ether_type;   // EtherType (extracted from data)
    byte unsigned payload[]; // Payload data (extracted from data)
    
    // Frame type: 0=TX, 1=RX
    bit frame_type;
    
    //==========================================================================
    // Control Flags
    //==========================================================================
    
    // Inject incomplete frame (no tlast)
    rand bit inject_no_tlast;
    
    // Inject backpressure during transfer
    rand bit inject_backpressure;
    
    // Number of cycles to delay for backpressure
    rand int unsigned backpressure_cycles;
    
    // Inter-frame gap (cycles between frames)
    rand int unsigned ifg_cycles;
    
    //==========================================================================
    // Status Fields (set by monitor)
    //==========================================================================
    
    // Timestamp when frame started
    time start_time;
    
    // Timestamp when frame ended
    time end_time;
    
    // Frame had error (tuser asserted on RX)
    bit frame_error;
    
    // RX frame status (from tuser)
    bit frame_good;  // Frame passed CRC check
    bit frame_bad;   // Frame failed CRC check
    
    // Transfer completed successfully
    bit transfer_complete;

    //==========================================================================
    // UVM Field Macros
    //==========================================================================
    `uvm_object_utils_begin(axi_stream_txn)
        `uvm_field_array_int(data, UVM_ALL_ON)
        `uvm_field_int(dst_mac, UVM_ALL_ON)
        `uvm_field_int(src_mac, UVM_ALL_ON)
        `uvm_field_int(ether_type, UVM_ALL_ON)
        `uvm_field_array_int(payload, UVM_ALL_ON)
        `uvm_field_int(frame_type, UVM_ALL_ON)
        `uvm_field_int(inject_no_tlast, UVM_ALL_ON)
        `uvm_field_int(inject_backpressure, UVM_ALL_ON)
        `uvm_field_int(backpressure_cycles, UVM_ALL_ON)
        `uvm_field_int(ifg_cycles, UVM_ALL_ON)
        `uvm_field_int(start_time, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(end_time, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(frame_error, UVM_ALL_ON)
        `uvm_field_int(frame_good, UVM_ALL_ON)
        `uvm_field_int(frame_bad, UVM_ALL_ON)
        `uvm_field_int(transfer_complete, UVM_ALL_ON)
    `uvm_object_utils_end

    //==========================================================================
    // Constraints
    //==========================================================================
    
    // Minimum frame size: 14 (header) + 46 (min payload) = 60 bytes
    // Maximum frame size: 1514 bytes (no jumbo)
    constraint c_frame_size {
        data.size() >= 60;
        data.size() <= 1514;
    }
    
    // Default: no error injection
    constraint c_default_no_errors {
        soft inject_no_tlast == 0;
        soft inject_backpressure == 0;
    }
    
    // Backpressure cycles range
    constraint c_backpressure {
        backpressure_cycles inside {[1:10]};
    }
    
    // IFG cycles range
    constraint c_ifg {
        soft ifg_cycles inside {[12:24]};
    }

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_stream_txn");
        super.new(name);
        transfer_complete = 0;
        frame_error = 0;
    endfunction

    //==========================================================================
    // Build frame from class fields (overloaded version)
    //==========================================================================
    function void build_frame(input bit add_crc = 0);
        int payload_size_local;
        int total_size;
        int idx;
        
        // Calculate payload size (minimum 46 bytes)
        payload_size_local = payload.size();
        if (payload_size_local < 46) payload_size_local = 46;
        
        // Calculate total frame size (14 header + payload)
        total_size = 14 + payload_size_local;
        
        // Allocate frame
        data = new[total_size];
        
        idx = 0;
        
        // Destination MAC (6 bytes, MSB first)
        data[idx++] = dst_mac[47:40];
        data[idx++] = dst_mac[39:32];
        data[idx++] = dst_mac[31:24];
        data[idx++] = dst_mac[23:16];
        data[idx++] = dst_mac[15:8];
        data[idx++] = dst_mac[7:0];
        
        // Source MAC (6 bytes, MSB first)
        data[idx++] = src_mac[47:40];
        data[idx++] = src_mac[39:32];
        data[idx++] = src_mac[31:24];
        data[idx++] = src_mac[23:16];
        data[idx++] = src_mac[15:8];
        data[idx++] = src_mac[7:0];
        
        // EtherType (2 bytes, MSB first)
        data[idx++] = ether_type[15:8];
        data[idx++] = ether_type[7:0];
        
        // Payload
        for (int i = 0; i < payload_size_local; i++) begin
            if (i < payload.size()) begin
                data[idx++] = payload[i];
            end else begin
                data[idx++] = 8'h00;  // Padding
            end
        end
        
        // Note: add_crc is unused - MAC always adds CRC
        // This parameter is kept for interface compatibility
    endfunction

    //==========================================================================
    // Build frame from explicit parameters
    //==========================================================================
    function void build_frame_explicit(
        input bit [47:0] dst,
        input bit [47:0] src,
        input bit [15:0] ethtype,
        input bit [7:0]  payload_arg[]
    );
        int payload_size;
        int idx;
        
        // Store metadata
        dst_mac = dst;
        src_mac = src;
        ether_type = ethtype;
        
        // Calculate payload size (minimum 46 bytes)
        payload_size = payload_arg.size();
        if (payload_size < 46) payload_size = 46;
        
        // Allocate frame
        data = new[14 + payload_size];
        
        idx = 0;
        
        // Destination MAC (6 bytes, MSB first)
        data[idx++] = dst[47:40];
        data[idx++] = dst[39:32];
        data[idx++] = dst[31:24];
        data[idx++] = dst[23:16];
        data[idx++] = dst[15:8];
        data[idx++] = dst[7:0];
        
        // Source MAC (6 bytes, MSB first)
        data[idx++] = src[47:40];
        data[idx++] = src[39:32];
        data[idx++] = src[31:24];
        data[idx++] = src[23:16];
        data[idx++] = src[15:8];
        data[idx++] = src[7:0];
        
        // EtherType (2 bytes, MSB first)
        data[idx++] = ethtype[15:8];
        data[idx++] = ethtype[7:0];
        
        // Payload
        for (int i = 0; i < payload_size; i++) begin
            if (i < payload_arg.size()) begin
                data[idx++] = payload_arg[i];
            end else begin
                data[idx++] = 8'h00;  // Padding
            end
        end
    endfunction

    //==========================================================================
    // Extract header fields from data
    //==========================================================================
    function void extract_header();
        if (data.size() >= 14) begin
            dst_mac = {data[0], data[1], data[2], data[3], data[4], data[5]};
            src_mac = {data[6], data[7], data[8], data[9], data[10], data[11]};
            ether_type = {data[12], data[13]};
        end
    endfunction

    //==========================================================================
    // Get payload (data after header)
    //==========================================================================
    function void get_payload(output bit [7:0] payload[]);
        if (data.size() > 14) begin
            payload = new[data.size() - 14];
            for (int i = 14; i < data.size(); i++) begin
                payload[i-14] = data[i];
            end
        end else begin
            payload = new[0];
        end
    endfunction

    //==========================================================================
    // Convert to string for debug
    //==========================================================================
    function string convert2string();
        string s;
        s = $sformatf("AXI-Stream Frame: len=%0d", data.size());
        if (data.size() >= 14) begin
            extract_header();
            s = {s, $sformatf(" DST=%012h SRC=%012h Type=%04h", 
                 dst_mac, src_mac, ether_type)};
        end
        if (frame_error) s = {s, " [ERROR]"};
        return s;
    endfunction

endclass : axi_stream_txn
