// File: tb/sequences/virtual/eth_rx_path_vseq.sv
class eth_rx_path_vseq extends eth_base_vseq;

  `uvm_object_utils(eth_rx_path_vseq)

  rand int num_packets;
  
  constraint c_num_packets {
    num_packets inside {[5:20]};
  }
  
  function new(string name = "eth_rx_path_vseq");
    super.new(name);
  endfunction

  task body();
    mac_reg_config_seq mac_cfg_seq;
    dma_reg_config_seq dma_cfg_seq;
    gmii_burst_seq     gmii_burst;
    mac_control_seq    mac_ctrl_seq;
    dma_control_seq    dma_ctrl_seq;
    axi_lite_read_seq  axi_read_seq;
    
    `uvm_info("ETH_RX", "Starting RX path test", UVM_LOW)
    
    // Configure MAC for RX
    mac_cfg_seq = mac_reg_config_seq::type_id::create("mac_cfg_seq");
    mac_cfg_seq.enable_rx = 1;
    mac_cfg_seq.enable_tx = 0;
    mac_cfg_seq.start(p_sequencer.axi_lite_sqr);
    
    // Configure DMA for RX
    dma_cfg_seq = dma_reg_config_seq::type_id::create("dma_cfg_seq");
    dma_cfg_seq.enable_rx_dma = 1;
    dma_cfg_seq.enable_tx_dma = 0;
    dma_cfg_seq.rx_desc_addr = 32'h2000_0000;
    dma_cfg_seq.start(p_sequencer.axi_lite_sqr);
    
    // Setup RX descriptors in memory
    setup_rx_descriptors();
    
    // Send packets from PHY to MAC
    gmii_burst = gmii_burst_seq::type_id::create("gmii_burst");
    gmii_burst.num_packets = this.num_packets;
    gmii_burst.packet_size_min = 64;
    gmii_burst.packet_size_max = 512;
    gmii_burst.start(p_sequencer.gmii_phy_sqr);
    
    #100us;  // Wait for packets to be processed

    // Read MAC status registers (optional, for verification)
    mac_ctrl_seq = mac_control_seq::type_id::create("mac_ctrl_seq");
    mac_ctrl_seq.predicted_rx_count = this.num_packets;
    mac_ctrl_seq.predicted_tx_count = 0;
    mac_ctrl_seq.predicted_err_count = 0;
    mac_ctrl_seq.predicted_crc_irq = 0;
    mac_ctrl_seq.predicted_runt_irq = 0;
    mac_ctrl_seq.start(p_sequencer.axi_lite_sqr);
    
    // Read DMA status registers (optional, for verification)
    dma_ctrl_seq = dma_control_seq::type_id::create("dma_ctrl_seq");
    dma_ctrl_seq.predicted_rx_count = this.num_packets;
    dma_ctrl_seq.predicted_tx_count = 0;
    dma_ctrl_seq.start(p_sequencer.axi_lite_sqr);

    // Wait for DMA to process all packets
    // for (int i = 0; i < num_packets; i++) begin
    //   p_sequencer.mem.dma_write_event.wait_on();
    // end
    
    `uvm_info("ETH_RX", "RX path test complete", UVM_LOW)
  endtask

  task setup_rx_descriptors();
    byte unsigned desc_data[];
    bit [31:0] desc_addr = 32'h2000_0000;
    bit [31:0] buffer_addr = 32'h3000_0000;
    
    // Simple descriptor format (example):
    // [31:0]   buffer_address
    // [63:32]  control (length, own bit, etc.)
    
    for(int i = 0; i < 8; i++) begin
      desc_data = new[8];
      
      // Buffer address (little-endian)
      desc_data[0] = buffer_addr[7:0];
      desc_data[1] = buffer_addr[15:8];
      desc_data[2] = buffer_addr[23:16];
      desc_data[3] = buffer_addr[31:24];
      
      // Control: Own bit + max buffer size (2048 bytes)
      desc_data[4] = 8'h00;
      desc_data[5] = 8'h08;  // 2048 bytes
      desc_data[6] = 8'h00;
      desc_data[7] = 8'h80;  // Own bit set
      
      p_sequencer.mem.init_mem(desc_addr, desc_data);
      
      desc_addr += 8;
      buffer_addr += 2048;
    end
    
    `uvm_info("ETH_RX", "RX descriptors initialized", UVM_MEDIUM)
  endtask

endclass : eth_rx_path_vseq
