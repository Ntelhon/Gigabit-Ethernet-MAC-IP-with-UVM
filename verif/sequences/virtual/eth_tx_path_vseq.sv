// File: tb/sequences/virtual/eth_tx_path_vseq.sv
class eth_tx_path_vseq extends eth_base_vseq;

  `uvm_object_utils(eth_tx_path_vseq)

  rand int num_packets;
  
  constraint c_num_packets {
    num_packets inside {[5:20]};
  }
  
  function new(string name = "eth_tx_path_vseq");
    super.new(name);
  endfunction

  task body();
    mac_reg_config_seq mac_cfg_seq;
    dma_reg_config_seq dma_cfg_seq;
    
    `uvm_info("ETH_TX", "Starting TX path test", UVM_LOW)
    
    // Configure MAC for TX
    mac_cfg_seq = mac_reg_config_seq::type_id::create("mac_cfg_seq");
    mac_cfg_seq.enable_tx = 1;
    mac_cfg_seq.enable_rx = 0;
    mac_cfg_seq.start(p_sequencer.axi_lite_sqr);
    
    // Configure DMA for TX
    dma_cfg_seq = dma_reg_config_seq::type_id::create("dma_cfg_seq");
    dma_cfg_seq.enable_tx_dma = 1;
    dma_cfg_seq.enable_rx_dma = 0;
    dma_cfg_seq.tx_desc_addr = 32'h1000_0000;
    dma_cfg_seq.start(p_sequencer.axi_lite_sqr);
    
    // Setup TX descriptors and packet data in memory
    for(int i = 0; i < num_packets; i++) begin
      setup_tx_packet(i);
    end
    
    // Trigger DMA (write to tail pointer register)
    write_reg(DMA_TX_HEAD_PTR_REG, num_packets);  // Example: descriptor count
    
    // Wait for packets to egress
    #20us;
    
    `uvm_info("ETH_TX", "TX path test complete", UVM_LOW)
  endtask

  task setup_tx_packet(int pkt_idx);
    byte unsigned desc_data[];
    byte unsigned pkt_data[];
    bit [31:0] desc_addr = 32'h1000_0000 + (pkt_idx * 8);
    bit [31:0] buffer_addr = 32'h3000_0000 + (pkt_idx * 2048);
    int pkt_size;
    
    // Generate random packet data
    pkt_size = $urandom_range(64, 256);
    pkt_data = new[pkt_size];
    foreach(pkt_data[i]) pkt_data[i] = $urandom();
    
    // Write packet to memory
    p_sequencer.mem.init_mem(buffer_addr, pkt_data);
    
    // Create descriptor
    desc_data = new[8];
    
    // Buffer address
    desc_data[0] = buffer_addr[7:0];
    desc_data[1] = buffer_addr[15:8];
    desc_data[2] = buffer_addr[23:16];
    desc_data[3] = buffer_addr[31:24];
    
    // Control: Own bit + length
    desc_data[4] = pkt_size[7:0];
    desc_data[5] = pkt_size[15:8];
    desc_data[6] = 8'h00;
    desc_data[7] = 8'h80;  // Own bit
    
    p_sequencer.mem.init_mem(desc_addr, desc_data);
    
    `uvm_info("ETH_TX", $sformatf("TX packet %0d setup: %0d bytes at 0x%0h", 
                                   pkt_idx, pkt_size, buffer_addr), UVM_MEDIUM)
  endtask

endclass : eth_tx_path_vseq
