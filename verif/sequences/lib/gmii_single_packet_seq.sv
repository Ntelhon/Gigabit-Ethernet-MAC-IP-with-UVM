// File: tb/sequences/lib/gmii_single_packet_seq.sv
class gmii_single_packet_seq extends uvm_sequence#(gmii_item);

  `uvm_object_utils(gmii_single_packet_seq)

  bit [47:0]        dst_mac = 48'h001122334455;  // Send to MAC's own address
  rand bit [47:0]   src_mac;  // Different source address
  bit [15:0]        ethertype = 16'h0800;  // IPv4
  rand int unsigned payload_size;
  
  function new(string name = "gmii_single_packet_seq");
    super.new(name);
  endfunction

  task body();
    gmii_item pkt;
    
    pkt = gmii_item::type_id::create("pkt");
    pkt.dst_mac = dst_mac;
    pkt.src_mac = src_mac;
    pkt.ether_type = ethertype;

    // Create payload (frame_size - 14 header - 4 FCS)
    pkt.payload = new[payload_size];
    for (int i = 0; i < pkt.payload.size(); i++) begin
        pkt.payload[i] = i[7:0];
    end

    pkt.has_fcs = 1;  // Include FCS for RX frames
    pkt.inject_fcs_error = 0;

    // Create and send frame TO the MAC (RX direction)
    start_item(pkt);
    finish_item(pkt);

    // Get Response (if any)
    get_response(pkt);

    `uvm_info("GMII_PKT", $sformatf("Sent packet: %0d bytes", pkt.payload.size()), UVM_MEDIUM)
  endtask

endclass : gmii_single_packet_seq
