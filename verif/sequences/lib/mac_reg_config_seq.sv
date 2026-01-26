// File: tb/sequences/lib/mac_reg_config_seq.sv
class mac_reg_config_seq extends uvm_sequence;

  `uvm_object_utils(mac_reg_config_seq)

  // MAC register addresses (example - adjust based on actual RTL)
  parameter bit [31:0] MAC_CTRL_REG   = 32'h0000_0000;
  parameter bit [31:0] MAC_ADDR_L_REG = 32'h0000_0010;
  parameter bit [31:0] MAC_ADDR_H_REG = 32'h0000_0014;
  
  // Configuration fields
  rand bit        enable_tx;
  rand bit        enable_rx;
  rand bit        promiscuous;
  rand bit [47:0] mac_address;
  
  function new(string name = "mac_reg_config_seq");
    super.new(name);
    enable_tx = 1;
    enable_rx = 1;
    promiscuous = 0;
    mac_address = 48'h001122334455;
  endfunction

  task body();
    axi_lite_write_seq wr_seq;
    
    // Configure MAC control register
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = MAC_CTRL_REG;
    wr_seq.data = {29'h0, promiscuous, enable_rx, enable_tx};
    wr_seq.start(null);  // Uses parent sequencer
    
    // Configure MAC address low
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = MAC_ADDR_L_REG;
    wr_seq.data = mac_address[31:0];
    wr_seq.start(null);
    
    // Configure MAC address high
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = MAC_ADDR_H_REG;
    wr_seq.data = {16'h0, mac_address[47:32]};
    wr_seq.start(null);
    
    `uvm_info("MAC_CFG", $sformatf("MAC configured: TX=%0b, RX=%0b, Addr=%0h", 
                                    enable_tx, enable_rx, mac_address), UVM_LOW)
  endtask

endclass : mac_reg_config_seq
