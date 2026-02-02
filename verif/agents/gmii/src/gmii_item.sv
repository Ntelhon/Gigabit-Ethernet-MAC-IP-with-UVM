//==============================================================================
// Class: gmii_item
// Description: GMII transaction representing an Ethernet frame
//
// Purpose:
//   Encapsulates all data and control fields for an Ethernet frame
//   transmitted or received via GMII interface. Supports error injection
//   and various frame configurations for verification.
//
// Fields:
//   - Frame data (payload including headers)
//   - Control flags (CRC error, runt, IFG violation)
//   - Timing parameters
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_item extends uvm_sequence_item;

    //==========================================================================
    // Frame Data
    //==========================================================================
    
    // Destination MAC address (6 bytes)
    rand bit [47:0] dst_mac;
    
    // Source MAC address (6 bytes)
    rand bit [47:0] src_mac;
    
    // EtherType / Length field (2 bytes)
    rand bit [15:0] ether_type;
    
    // Payload data (variable length)
    rand bit [7:0] payload[];
    
    // Frame Check Sequence (CRC32) - calculated or injected
    bit [31:0] fcs;
    
    // Frame control flags
    bit has_fcs;              // If true, FCS is included/will be calculated
    bit inject_fcs_error;     // If true, corrupt FCS
    bit is_runt;              // If true, frame is smaller than minimum size
    
    //==========================================================================
    // Control Flags
    //==========================================================================
    
    // Inject CRC error (corrupt FCS)
    rand bit inject_crc_error;
    
    // Send as runt frame (< 64 bytes, no padding)
    rand bit send_as_runt;
    
    // Inject IFG violation (reduced inter-frame gap)
    rand bit inject_ifg_violation;
    
    // Custom IFG in bytes (default 12)
    rand int unsigned ifg_bytes;
    
    // Inject RX error during frame
    rand bit inject_rx_error;
    
    // Byte position to inject RX error
    rand int unsigned rx_error_byte_pos;
    
    // Number of preamble bytes (default 7)
    rand int unsigned preamble_bytes;
    
    //==========================================================================
    // Timing Information (set by monitor, informational)
    //==========================================================================
    
    // Timestamp when frame started
    time start_time;
    
    // Timestamp when frame ended
    time end_time;
    
    //==========================================================================
    // Calculated Fields
    //==========================================================================
    
    // Total frame length (excluding preamble/SFD)
    int unsigned frame_length;
    
    // Frame valid flag (set by monitor after CRC check)
    bit frame_valid;
    
    // CRC error detected (set by monitor)
    bit crc_error_detected;
    
    // Runt frame detected (set by monitor)
    bit runt_detected;

    //==========================================================================
    // UVM Field Macros
    //==========================================================================
    `uvm_object_utils_begin(gmii_item)
        `uvm_field_int(dst_mac, UVM_ALL_ON)
        `uvm_field_int(src_mac, UVM_ALL_ON)
        `uvm_field_int(ether_type, UVM_ALL_ON)
        `uvm_field_array_int(payload, UVM_ALL_ON)
        `uvm_field_int(fcs, UVM_ALL_ON)
        `uvm_field_int(has_fcs, UVM_ALL_ON)
        `uvm_field_int(inject_fcs_error, UVM_ALL_ON)
        `uvm_field_int(is_runt, UVM_ALL_ON)
        `uvm_field_int(inject_crc_error, UVM_ALL_ON)
        `uvm_field_int(send_as_runt, UVM_ALL_ON)
        `uvm_field_int(inject_ifg_violation, UVM_ALL_ON)
        `uvm_field_int(ifg_bytes, UVM_ALL_ON)
        `uvm_field_int(inject_rx_error, UVM_ALL_ON)
        `uvm_field_int(rx_error_byte_pos, UVM_ALL_ON)
        `uvm_field_int(preamble_bytes, UVM_ALL_ON)
        `uvm_field_int(start_time, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(end_time, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(frame_length, UVM_ALL_ON)
        `uvm_field_int(frame_valid, UVM_ALL_ON)
        `uvm_field_int(crc_error_detected, UVM_ALL_ON)
        `uvm_field_int(runt_detected, UVM_ALL_ON)
    `uvm_object_utils_end

    //==========================================================================
    // Constraints
    //==========================================================================
    
    // Payload size constraints
    constraint c_payload_size {
        payload.size() inside {[0:1500]};  // Standard MTU
    }
    
    // Default no error injection
    constraint c_default_no_errors {
        soft inject_crc_error == 0;
        soft send_as_runt == 0;
        soft inject_ifg_violation == 0;
        soft inject_rx_error == 0;
    }
    
    // Default timing
    constraint c_default_timing {
        soft ifg_bytes == 12;
        soft preamble_bytes == 7;
    }
    
    // IFG range
    constraint c_ifg_range {
        ifg_bytes inside {[0:24]};
    }
    
    // Preamble range
    constraint c_preamble_range {
        preamble_bytes inside {[1:15]};
    }
    
    // RX error position within frame
    constraint c_rx_error_pos {
        if (inject_rx_error) {
            rx_error_byte_pos < (14 + payload.size());  // Within frame data
        }
    }

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "gmii_item");
        super.new(name);
        frame_valid = 0;
        crc_error_detected = 0;
        runt_detected = 0;
    endfunction

    //==========================================================================
    // Get frame as byte array (excluding preamble/SFD/FCS)
    //==========================================================================
    function void get_frame_bytes(output bit [7:0] bytes[]);
        int idx;
        int total_len;
        
        // Calculate total length: dest(6) + src(6) + type(2) + payload
        total_len = 14 + payload.size();
        bytes = new[total_len];
        
        idx = 0;
        
        // Destination MAC (MSB first)
        bytes[idx++] = dst_mac[47:40];
        bytes[idx++] = dst_mac[39:32];
        bytes[idx++] = dst_mac[31:24];
        bytes[idx++] = dst_mac[23:16];
        bytes[idx++] = dst_mac[15:8];
        bytes[idx++] = dst_mac[7:0];
        
        // Source MAC (MSB first)
        bytes[idx++] = src_mac[47:40];
        bytes[idx++] = src_mac[39:32];
        bytes[idx++] = src_mac[31:24];
        bytes[idx++] = src_mac[23:16];
        bytes[idx++] = src_mac[15:8];
        bytes[idx++] = src_mac[7:0];
        
        // EtherType (MSB first)
        bytes[idx++] = ether_type[15:8];
        bytes[idx++] = ether_type[7:0];
        
        // Payload
        foreach (payload[i]) begin
            bytes[idx++] = payload[i];
        end
        
        frame_length = total_len;
    endfunction

    //==========================================================================
    // Set frame from byte array (for monitor reconstruction)
    //==========================================================================
    function void set_from_bytes(input bit [7:0] bytes[]);
        int idx;
        int payload_len;
        
        if (bytes.size() < 14) begin
            runt_detected = 1;
            return;
        end
        
        idx = 0;
        
        // Extract Destination MAC
        dst_mac = {bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]};
        idx = 6;
        
        // Extract Source MAC
        src_mac = {bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11]};
        idx = 12;
        
        // Extract EtherType
        ether_type = {bytes[12], bytes[13]};
        idx = 14;
        
        // Extract Payload (remaining bytes minus FCS if present)
        if (bytes.size() >= 18) begin  // At least 14 header + 4 FCS
            payload_len = bytes.size() - 14 - 4;
            if (payload_len > 0) begin
                payload = new[payload_len];
                for (int i = 0; i < payload_len; i++) begin
                    payload[i] = bytes[14 + i];
                end
            end
            // Extract FCS (last 4 bytes) - Ethernet sends FCS LSB first
            // bytes[size-4] = CRC[7:0]   (first transmitted)
            // bytes[size-3] = CRC[15:8]
            // bytes[size-2] = CRC[23:16]
            // bytes[size-1] = CRC[31:24] (last transmitted)
            fcs = {bytes[bytes.size()-1], bytes[bytes.size()-2], 
                   bytes[bytes.size()-3], bytes[bytes.size()-4]};
        end else begin
            payload_len = bytes.size() - 14;
            if (payload_len > 0) begin
                payload = new[payload_len];
                for (int i = 0; i < payload_len; i++) begin
                    payload[i] = bytes[14 + i];
                end
            end
        end
    endfunction

    //==========================================================================
    // Calculate CRC32 for the frame
    //==========================================================================
    function bit [31:0] calculate_crc();
        bit [7:0] frame_bytes[];
        bit [31:0] crc;
        bit [31:0] poly;
        int i, j;
        bit [7:0] data_byte;
        
        get_frame_bytes(frame_bytes);
        
        crc = 32'hFFFFFFFF;
        poly = 32'hEDB88320;  // Reflected polynomial
        
        for (i = 0; i < frame_bytes.size(); i++) begin
            // Reflect input byte
            data_byte = frame_bytes[i];
            crc = crc ^ {24'h0, data_byte};
            
            for (j = 0; j < 8; j++) begin
                if (crc[0])
                    crc = (crc >> 1) ^ poly;
                else
                    crc = crc >> 1;
            end
        end
        
        // Final XOR and return
        crc = ~crc;
        return crc;
    endfunction

    //==========================================================================
    // Convert to string for debug
    //==========================================================================
    function string convert2string();
        string s;
        s = $sformatf("GMII Frame:\n");
        s = {s, $sformatf("  Dest MAC: %012h\n", dst_mac)};
        s = {s, $sformatf("  Src MAC:  %012h\n", src_mac)};
        s = {s, $sformatf("  Type:     %04h\n", ether_type)};
        s = {s, $sformatf("  Payload:  %0d bytes\n", payload.size())};
        s = {s, $sformatf("  FCS:      %08h\n", fcs)};
        s = {s, $sformatf("  Errors:   CRC=%0b Runt=%0b IFG=%0b RxErr=%0b\n",
                          inject_crc_error, send_as_runt, 
                          inject_ifg_violation, inject_rx_error)};
        return s;
    endfunction

endclass : gmii_item
