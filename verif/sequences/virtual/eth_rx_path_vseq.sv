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
    dma_cfg_seq.rx_tail_ptr = 32'd16;  // Start with 16 ready descriptors for RX
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
    // [31:0]  - Buffer address low
    // [63:32] - Buffer address high (if ADDR_WIDTH > 32)
    // [79:64] - Buffer length (max bytes to receive)
    // [95:80] - Actual length (written by DMA)
    // [127:96]- Status/Control bits

    // Status/Control Bits:
    // [0]    - OWN (0=CPU owns, 1=DMA owns)
    // [1]    - DONE (set by DMA when complete)
    // [2]    - ERR (error occurred)
    // [3]    - LAST (last descriptor of packet)
    // [4]    - FIRST (first descriptor of packet)
    // [5]    - CRC_EN (TX only: append CRC)
    // [31:6] - Reserved
    
    for(int i = 0; i < 16; i++) begin
      desc_data = new[16];
      
      // Buffer address (little-endian)
      desc_data[0] = buffer_addr[7:0];
      desc_data[1] = buffer_addr[15:8];
      desc_data[2] = buffer_addr[23:16];
      desc_data[3] = buffer_addr[31:24];
      desc_data[4] = 8'h00;   // Buffer address high (not used in this example)
      desc_data[5] = 8'h00;   // Buffer address high (not used in this example)
      desc_data[6] = 8'h00;   // Buffer address high (not used in this example)
      desc_data[7] = 8'h00;   // Buffer address high (not used in this example)

      // Max Buffer length (2048 bytes)
      desc_data[8] = 8'h00;
      desc_data[9] = 8'h08;   // 2048 bytes

      // Actual length (initially 0, set by DMA)
      desc_data[10] = 8'h00;
      desc_data[11] = 8'h00;

      // Status/Control bits
      desc_data[12] = 8'h01;   // Own bit set
      desc_data[13] = 8'h00;   // Reserved
      desc_data[14] = 8'h00;   // Reserved
      desc_data[15] = 8'h00;   // Reserved
      
      p_sequencer.mem.init_mem(desc_addr, desc_data);
      
      desc_addr += 16;        // Move to next descriptor (16 bytes each)
      buffer_addr += 2048;    // Move to next buffer address
    end
    
    `uvm_info("ETH_RX", "RX descriptors initialized", UVM_MEDIUM)
  endtask

endclass : eth_rx_path_vseq
