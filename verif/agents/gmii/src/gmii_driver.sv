// File: tb/agents/gmii/gmii_driver.sv
class gmii_driver extends uvm_driver #(gmii_item);

  `uvm_component_utils(gmii_driver)

  virtual gmii_if vif;
  gmii_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(gmii_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")
    
    if(!uvm_config_db#(virtual gmii_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not set for gmii_driver")
  endfunction

  task run_phase(uvm_phase phase);
    reset_signals();
    
    forever begin
      seq_item_port.get_next_item(req);
      
      if(cfg.direction == GMII_TX)
        drive_tx_frame(req);
      else
        drive_rx_frame(req);
      
      seq_item_port.item_done();
    end
  endtask

  task reset_signals();
    if(cfg.direction == GMII_TX) begin
      @(vif.tx_driver_cb);
      vif.tx_driver_cb.tx_en <= 1'b0;
      vif.tx_driver_cb.tx_er <= 1'b0;
      vif.tx_driver_cb.txd   <= 8'h00;
    end else begin
      @(vif.rx_driver_cb);
      vif.rx_driver_cb.rx_dv <= 1'b0;
      vif.rx_driver_cb.rx_er <= 1'b0;
      vif.rx_driver_cb.rxd   <= 8'h00;
    end
  endtask

  task drive_tx_frame(gmii_item item);
    byte unsigned frame[];
    item.get_frame_bytes(frame);
    
    // Inter-frame gap
    repeat(item.ifg_cycles) @(vif.tx_driver_cb);
    
    // Drive frame
    foreach(frame[i]) begin
      vif.tx_driver_cb.tx_en <= 1'b1;
      vif.tx_driver_cb.tx_er <= (item.inject_underrun && (i == frame.size()-1)) ? 1'b1 : 1'b0;
      vif.tx_driver_cb.txd   <= frame[i];
      @(vif.tx_driver_cb);
    end
    
    // End of frame
    vif.tx_driver_cb.tx_en <= 1'b0;
    vif.tx_driver_cb.tx_er <= 1'b0;
  endtask

  task drive_rx_frame(gmii_item item);
    byte unsigned frame[];
    item.get_frame_bytes(frame);
    
    // Inter-frame gap
    repeat(item.ifg_cycles) @(vif.rx_driver_cb);
    
    // Drive frame
    foreach(frame[i]) begin
      vif.rx_driver_cb.rx_dv <= 1'b1;
      vif.rx_driver_cb.rx_er <= 1'b0;
      vif.rx_driver_cb.rxd   <= frame[i];
      @(vif.rx_driver_cb);
    end
    
    // End of frame
    vif.rx_driver_cb.rx_dv <= 1'b0;
  endtask

endclass : gmii_driver
