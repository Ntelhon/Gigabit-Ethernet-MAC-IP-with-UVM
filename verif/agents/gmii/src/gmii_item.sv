// File: tb/agents/gmii/gmii_item.sv
class gmii_item extends uvm_sequence_item;

  // Ethernet frame components
  rand byte unsigned preamble[];       // 7 bytes of 0x55
  rand byte unsigned sfd;              // Start Frame Delimiter (0xD5)
  rand byte unsigned dst_mac[6];       // Destination MAC
  rand byte unsigned src_mac[6];       // Source MAC
  rand bit [15:0]    ethertype;        // Or length for 802.3
  rand byte unsigned payload[];        // Data
  rand bit [31:0]    fcs;              // Frame Check Sequence (CRC32)
  
  // Optional VLAN tag
  rand bit           has_vlan;
  rand bit [15:0]    vlan_tci;         // Tag Control Information
  
  // Inter-frame gap
  rand int unsigned  ifg_cycles;       // Inter-Frame Gap (default 96 bit times = 12 bytes)
  
  // Error injection
  rand bit           inject_crc_error;
  rand bit           inject_underrun;

  // Constraints
  constraint c_preamble {
    preamble.size() == 7;
    foreach(preamble[i]) preamble[i] == 8'h55;
  }
  
  constraint c_sfd {
    sfd == 8'hD5;
  }
  
  constraint c_payload_size {
    if(!has_vlan)
      payload.size() inside {[46:1500]};  // Min 46 bytes, Max 1500 (MTU)
    else
      payload.size() inside {[42:1496]};  // Account for 4-byte VLAN tag
  }
  
  constraint c_ifg {
    ifg_cycles inside {[12:20]};  // 12 bytes minimum (96 bit times)
  }
  
  constraint c_vlan_probability {
    has_vlan dist {0 := 80, 1 := 20};  // 20% VLAN-tagged
  }

  `uvm_object_utils_begin(gmii_item)
    `uvm_field_array_int(preamble, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(sfd, UVM_DEFAULT | UVM_HEX)
    `uvm_field_sarray_int(dst_mac, UVM_DEFAULT | UVM_HEX)
    `uvm_field_sarray_int(src_mac, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(ethertype, UVM_DEFAULT | UVM_HEX)
    `uvm_field_array_int(payload, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(fcs, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(has_vlan, UVM_DEFAULT)
    `uvm_field_int(vlan_tci, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(ifg_cycles, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(inject_crc_error, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "gmii_item");
    super.new(name);
  endfunction

  // Helper: Calculate CRC32
  function bit [31:0] calculate_crc32();
    byte unsigned frame_data[];
    bit [31:0] crc;
    int idx = 0;
    
    // Build frame without FCS
    frame_data = new[6 + 6 + 2 + (has_vlan ? 4 : 0) + payload.size()];
    
    foreach(dst_mac[i]) frame_data[idx++] = dst_mac[i];
    foreach(src_mac[i]) frame_data[idx++] = src_mac[i];
    
    if(has_vlan) begin
      frame_data[idx++] = 8'h81;
      frame_data[idx++] = 8'h00;
      frame_data[idx++] = vlan_tci[15:8];
      frame_data[idx++] = vlan_tci[7:0];
    end
    
    frame_data[idx++] = ethertype[15:8];
    frame_data[idx++] = ethertype[7:0];
    
    foreach(payload[i]) frame_data[idx++] = payload[i];
    
    // CRC32 calculation (Ethernet polynomial: 0x04C11DB7)
    crc = 32'hFFFFFFFF;
    foreach(frame_data[i]) begin
      crc = crc ^ {24'h0, frame_data[i]};
      for(int j = 0; j < 8; j++) begin
        if(crc[0])
          crc = (crc >> 1) ^ 32'hEDB88320;  // Reversed polynomial
        else
          crc = crc >> 1;
      end
    end
    
    return ~crc;  // Final inversion
  endfunction

  // Post-randomize: Auto-calculate FCS
  function void post_randomize();
    if(!inject_crc_error)
      fcs = calculate_crc32();
    else
      fcs = $urandom();  // Corrupt FCS
  endfunction

  // Helper: Get full frame as byte array
  function void get_frame_bytes(ref byte unsigned frame[]);
    int idx = 0;
    frame = new[preamble.size() + 1 + 6 + 6 + 2 + (has_vlan ? 4 : 0) + payload.size() + 4];
    
    foreach(preamble[i]) frame[idx++] = preamble[i];
    frame[idx++] = sfd;
    foreach(dst_mac[i]) frame[idx++] = dst_mac[i];
    foreach(src_mac[i]) frame[idx++] = src_mac[i];
    
    if(has_vlan) begin
      frame[idx++] = 8'h81;
      frame[idx++] = 8'h00;
      frame[idx++] = vlan_tci[15:8];
      frame[idx++] = vlan_tci[7:0];
    end
    
    frame[idx++] = ethertype[15:8];
    frame[idx++] = ethertype[7:0];
    foreach(payload[i]) frame[idx++] = payload[i];
    frame[idx++] = fcs[7:0];
    frame[idx++] = fcs[15:8];
    frame[idx++] = fcs[23:16];
    frame[idx++] = fcs[31:24];
  endfunction

endclass : gmii_item
