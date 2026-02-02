// File: tb/sequences/lib/dma_control_seq.sv
class dma_control_seq extends uvm_sequence;

  `uvm_object_utils(dma_control_seq)
  
  // Configuration fields
  rand int        predicted_rx_count;
  rand int        predicted_tx_count;

  function new(string name = "dma_control_seq");
    super.new(name);
    predicted_rx_count = 0;
    predicted_tx_count = 0;
  endfunction

  task body();
    axi_lite_read_seq  rd_seq;
    rd_seq = axi_lite_read_seq::type_id::create("rd_seq");

    // DMA RX Count
    rd_seq.addr = DMA_RX_PKT_CNT;
    rd_seq.start(m_sequencer);
    if (predicted_rx_count == rd_seq.read_data)
      `uvm_info("DMA_CTRL", $sformatf("Predicted RX count matched: %0d", rd_seq.read_data), UVM_LOW)
    else
      `uvm_warning("DMA_CTRL", $sformatf("Predicted RX count mismatch! Expected: %0d, Actual: %0d", 
                                        predicted_rx_count, rd_seq.read_data))
                                        
    // DMA TX Count
    rd_seq.addr = DMA_TX_PKT_CNT;
    rd_seq.start(m_sequencer);
    if (predicted_tx_count == rd_seq.read_data)
      `uvm_info("DMA_CTRL", $sformatf("Predicted TX count matched: %0d", rd_seq.read_data), UVM_LOW)
    else
      `uvm_warning("DMA_CTRL", $sformatf("Predicted TX count mismatch! Expected: %0d, Actual: %0d", 
                                        predicted_tx_count, rd_seq.read_data))

  endtask

endclass : dma_control_seq
