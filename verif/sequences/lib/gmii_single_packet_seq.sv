// File: tb/sequences/lib/gmii_single_packet_seq.sv
class gmii_single_packet_seq extends uvm_sequence#(gmii_item);

  `uvm_object_utils(gmii_single_packet_seq)

  rand byte unsigned dst_mac[6];
  rand byte unsigned src_mac[6];
  rand bit [15:0]    ethertype;
  rand byte unsigned payload[];
  rand int unsigned  payload_size;
  
  constraint c_payload_size {
    payload_size inside {[64:256]};
  }
  
  function new(string name = "gmii_single_packet_seq");
    super.new(name);
    ethertype = 16'h0800;  // IPv4
  endfunction

  task body();
    gmii_item pkt;
    
    pkt = gmii_item::type_id::create("pkt");
    start_item(pkt);
    
    assert(pkt.randomize() with {
      payload.size() == payload_size;
      foreach(dst_mac[i]) pkt.dst_mac[i] == dst_mac[i];
      foreach(src_mac[i]) pkt.src_mac[i] == src_mac[i];
      pkt.ethertype == ethertype;
    });
    
    finish_item(pkt);

    // Get Response (if any)
    get_response(pkt);

    `uvm_info("GMII_PKT", $sformatf("Sent packet: %0d bytes", pkt.payload.size()), UVM_MEDIUM)
  endtask

endclass : gmii_single_packet_seq
