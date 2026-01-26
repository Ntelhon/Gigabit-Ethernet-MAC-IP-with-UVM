// File: tb/sequences/lib/dma_reg_config_seq.sv
class dma_reg_config_seq extends uvm_sequence;

  `uvm_object_utils(dma_reg_config_seq)

  // DMA register addresses (example - adjust based on actual RTL)
  parameter bit [31:0] DMA_CTRL_REG       = 32'h0000_0300;
  parameter bit [31:0] DMA_TX_DESC_PTR    = 32'h0000_0310;
  parameter bit [31:0] DMA_RX_DESC_PTR    = 32'h0000_0320;
  
  // Configuration fields
  rand bit        enable_tx_dma;
  rand bit        enable_rx_dma;
  rand bit [31:0] tx_desc_addr;
  rand bit [31:0] rx_desc_addr;
  
  function new(string name = "dma_reg_config_seq");
    super.new(name);
    enable_tx_dma = 1;
    enable_rx_dma = 1;
    tx_desc_addr = 32'h1000_0000;
    rx_desc_addr = 32'h2000_0000;
  endfunction

  task body();
    axi_lite_write_seq wr_seq;
    
    // Set TX descriptor pointer
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = DMA_TX_DESC_PTR;
    wr_seq.data = tx_desc_addr;
    wr_seq.start(null);
    
    // Set RX descriptor pointer
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = DMA_RX_DESC_PTR;
    wr_seq.data = rx_desc_addr;
    wr_seq.start(null);
    
    // Enable DMA
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = DMA_CTRL_REG;
    wr_seq.data = {30'h0, enable_rx_dma, enable_tx_dma};
    wr_seq.start(null);
    
    `uvm_info("DMA_CFG", $sformatf("DMA configured: TX_EN=%0b, RX_EN=%0b, TX_DESC=0x%0h, RX_DESC=0x%0h", 
                                    enable_tx_dma, enable_rx_dma, tx_desc_addr, rx_desc_addr), UVM_LOW)
  endtask

endclass : dma_reg_config_seq
