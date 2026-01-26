// File: tb/sequences/virtual/eth_bidir_vseq.sv
class eth_bidir_vseq extends eth_base_vseq;

  `uvm_object_utils(eth_bidir_vseq)

  rand int num_tx_packets;
  rand int num_rx_packets;
  
  constraint c_packets {
    num_tx_packets inside {[10:30]};
    num_rx_packets inside {[10:30]};
  }
  
  function new(string name = "eth_bidir_vseq");
    super.new(name);
  endfunction

  task body();
    eth_tx_path_vseq tx_seq;
    eth_rx_path_vseq rx_seq;
    
    `uvm_info("ETH_BIDIR", "Starting bidirectional traffic test", UVM_LOW)
    
    // Run TX and RX sequences in parallel
    fork
      begin
        tx_seq = eth_tx_path_vseq::type_id::create("tx_seq");
        tx_seq.num_packets = this.num_tx_packets;
        tx_seq.start(m_sequencer);
      end
      
      begin
        // Delay RX slightly to avoid descriptor conflicts
        #1us;
        rx_seq = eth_rx_path_vseq::type_id::create("rx_seq");
        rx_seq.num_packets = this.num_rx_packets;
        rx_seq.start(m_sequencer);
      end
    join
    
    `uvm_info("ETH_BIDIR", "Bidirectional traffic test complete", UVM_LOW)
  endtask

endclass : eth_bidir_vseq
