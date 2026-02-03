// File: tb/sequences/lib/mac_control_seq.sv
class mac_control_seq extends uvm_sequence;

  `uvm_object_utils(mac_control_seq)
  
  // Configuration fields
  rand int        predicted_rx_count;
  rand int        predicted_tx_count;
  rand int        predicted_err_count;
  rand bit        predicted_crc_irq;
  rand bit        predicted_runt_irq;

  function new(string name = "mac_control_seq");
    super.new(name);
    predicted_rx_count = 0;
    predicted_tx_count = 0;
    predicted_err_count = 0;
    predicted_crc_irq = 0;
    predicted_runt_irq = 0;
  endfunction

  task body();
    axi_lite_read_seq  rd_seq;
    rd_seq = axi_lite_read_seq::type_id::create("rd_seq");

    // MAC RX Count
    rd_seq.addr = MAC_RX_CNT_REG;
    rd_seq.start(m_sequencer);
    if (predicted_rx_count == rd_seq.read_data)
      `uvm_info("MAC_CFG", $sformatf("Predicted RX count matched: %0d", rd_seq.read_data), UVM_LOW)
    else
      `uvm_warning("MAC_CFG", $sformatf("Predicted RX count mismatch! Expected: %0d, Actual: %0d", 
                                        predicted_rx_count, rd_seq.read_data))
                                        
    // MAC TX Count
    rd_seq.addr = MAC_TX_CNT_REG;
    rd_seq.start(m_sequencer);
    if (predicted_tx_count == rd_seq.read_data)
      `uvm_info("MAC_CFG", $sformatf("Predicted TX count matched: %0d", rd_seq.read_data), UVM_LOW)
    else
      `uvm_warning("MAC_CFG", $sformatf("Predicted TX count mismatch! Expected: %0d, Actual: %0d", 
                                        predicted_tx_count, rd_seq.read_data))

    // MAC RX Error Count
    rd_seq.addr = MAC_RX_ERR_REG;
    rd_seq.start(m_sequencer);
    if (predicted_err_count == rd_seq.read_data)
      `uvm_info("MAC_CFG", $sformatf("Predicted RX error count matched: %0d", rd_seq.read_data), UVM_LOW)
    else
      `uvm_warning("MAC_CFG", $sformatf("Predicted RX error count mismatch! Expected: %0d, Actual: %0d", 
                                        predicted_err_count, rd_seq.read_data))

    // MAC Interrupt Status
    rd_seq.addr = MAC_INT_STATUS_REG;
    rd_seq.start(m_sequencer);
    if(predicted_tx_count)
      if(rd_seq.read_data & MAC_INT_TX_COMPLETE_BITMASK)
        `uvm_info("MAC_CFG", "MAC TX Complete interrupt reported", UVM_LOW)
      else
        `uvm_error("MAC_CFG", "MAC TX Complete interrupt NOT reported when expected")

    if(predicted_rx_count)
      if(rd_seq.read_data & MAC_INT_RX_RECEIVED_BITMASK)
        `uvm_info("MAC_CFG", "MAC RX Received interrupt reported", UVM_LOW)
      else
        `uvm_error("MAC_CFG", "MAC RX Received interrupt NOT reported when expected")

    if (predicted_crc_irq)
      if(rd_seq.read_data & MAC_INT_RX_CRC_ERR_BITMASK)
        `uvm_info("MAC_CFG", "MAC RX CRC Error interrupt reported as expected", UVM_LOW)
    else
      `uvm_error("MAC_CFG", "MAC RX CRC Error interrupt NOT reported when expected")

    if (predicted_runt_irq)
      if(rd_seq.read_data & MAC_INT_RX_RUNT_BITMASK)
        `uvm_info("MAC_CFG", "MAC RX Runt Frame interrupt reported", UVM_LOW)
    else
      `uvm_error("MAC_CFG", "MAC RX Runt Frame interrupt NOT reported when expected")

  endtask

endclass : mac_control_seq
