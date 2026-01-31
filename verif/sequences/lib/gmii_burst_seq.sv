// File: tb/sequences/lib/gmii_burst_seq.sv
class gmii_burst_seq extends uvm_sequence#(gmii_item);

  `uvm_object_utils(gmii_burst_seq)

  rand int num_packets;
  rand int packet_size_min;
  rand int packet_size_max;
  
  constraint c_burst {
    num_packets inside {[2:50]};
    packet_size_min inside {[64:128]};
    packet_size_max inside {[129:512]};
    packet_size_min < packet_size_max;
  }
  
  function new(string name = "gmii_burst_seq");
    super.new(name);
  endfunction

  task body();
    gmii_single_packet_seq pkt_seq;
    
    repeat(num_packets) begin
      pkt_seq = gmii_single_packet_seq::type_id::create("pkt_seq");
      assert(pkt_seq.randomize() with {
        payload_size inside {[packet_size_min:packet_size_max]};
      });
      pkt_seq.start(m_sequencer);
    end
    
    `uvm_info("GMII_BURST", $sformatf("Sent %0d packets", num_packets), UVM_LOW)
  endtask

endclass : gmii_burst_seq
