// File: tb/sequences/lib/dma_reg_config_seq.sv
class dma_reg_config_seq extends uvm_sequence;

  `uvm_object_utils(dma_reg_config_seq)
  
  // Configuration fields
  rand bit        enable_tx_dma;
  rand bit        enable_rx_dma;
  rand bit [31:0] tx_desc_addr;
  rand bit [31:0] tx_tail_ptr;
  rand bit [31:0] rx_desc_addr;
  rand bit [31:0] rx_tail_ptr;

  function new(string name = "dma_reg_config_seq");
    super.new(name);
    enable_tx_dma = 1;
    enable_rx_dma = 1;
    tx_desc_addr = 32'h1000_0000;
    tx_tail_ptr = 32'd0;  // Start with 0 ready descriptors for TX
    rx_desc_addr = 32'h2000_0000;
    rx_tail_ptr = 32'd0;  // Start with 0 ready descriptors for RX
  endfunction

  task body();
    axi_lite_write_seq wr_seq;
    
    // Set TX descriptor pointer
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = DMA_TX_DESC_LO_REG;
    wr_seq.data = tx_desc_addr;
    wr_seq.start(m_sequencer);  // Uses parent sequencer
    
    // Enable TX DMA
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = DMA_TX_CTRL_REG;
    wr_seq.data = {31'h0, enable_tx_dma};
    wr_seq.start(m_sequencer);
    
    // Set RX descriptor pointer
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = DMA_RX_DESC_LO_REG;
    wr_seq.data = rx_desc_addr;
    wr_seq.start(m_sequencer);

    // Set RX Tail pointer to indicate available buffers (kickstart RX DMA)
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = DMA_RX_TAIL_PTR_REG;
    wr_seq.data = rx_tail_ptr;
    wr_seq.start(m_sequencer);
    
    // Enable RX DMA
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = DMA_RX_CTRL_REG;
    wr_seq.data = {31'h0, enable_rx_dma};
    wr_seq.start(m_sequencer);
    
    `uvm_info("DMA_CFG", $sformatf("DMA configured: TX_EN=%0b, RX_EN=%0b, TX_DESC=0x%0h, RX_DESC=0x%0h", 
                                    enable_tx_dma, enable_rx_dma, tx_desc_addr, rx_desc_addr), UVM_LOW)
  endtask

endclass : dma_reg_config_seq
