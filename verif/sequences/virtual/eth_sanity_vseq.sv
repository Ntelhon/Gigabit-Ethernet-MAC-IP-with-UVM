// File: tb/sequences/virtual/eth_sanity_vseq.sv
class eth_sanity_vseq extends eth_base_vseq;

  `uvm_object_utils(eth_sanity_vseq)

  function new(string name = "eth_sanity_vseq");
    super.new(name);
  endfunction

  task body();
    bit [AXI_LITE_DATA_WIDTH-1:0] read_data;
    mac_reg_config_seq mac_cfg_seq;
    dma_reg_config_seq dma_cfg_seq;
    
    `uvm_info("ETH_SANITY", "Starting sanity test", UVM_LOW)
    
    // Configure MAC
    mac_cfg_seq = mac_reg_config_seq::type_id::create("mac_cfg_seq");
    mac_cfg_seq.start(p_sequencer.axi_lite_sqr);
    
    // Configure DMA
    dma_cfg_seq = dma_reg_config_seq::type_id::create("dma_cfg_seq");
    dma_cfg_seq.start(p_sequencer.axi_lite_sqr);

    // Read back MAC control register
    read_reg(MAC_CONTROL_REG, read_data);
    `uvm_info("ETH_SANITY", $sformatf("MAC CTRL readback: 0x%0h", read_data), UVM_LOW)
    
    // Read back DMA control register
    read_reg(DMA_TX_CTRL_REG, read_data);
    `uvm_info("ETH_SANITY", $sformatf("DMA-TX CTRL readback: 0x%0h", read_data), UVM_LOW)

    // Read back DMA control register
    read_reg(DMA_RX_CTRL_REG, read_data);
    `uvm_info("ETH_SANITY", $sformatf("DMA-RX CTRL readback: 0x%0h", read_data), UVM_LOW)

    `uvm_info("ETH_SANITY", "Sanity test complete", UVM_LOW)
  endtask

endclass : eth_sanity_vseq
