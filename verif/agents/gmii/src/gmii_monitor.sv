// File: tb/agents/gmii/gmii_monitor.sv
class gmii_monitor extends uvm_monitor;

  `uvm_component_utils(gmii_monitor)

  virtual gmii_if vif;
  gmii_config cfg;
  
  uvm_analysis_port #(gmii_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(gmii_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")
  endfunction

  task run_phase(uvm_phase phase);
    if(cfg.direction == GMII_TX)
      monitor_tx();
    else
      monitor_rx();
  endtask

  task monitor_tx();
    gmii_item item;
    byte unsigned frame_bytes[$];
    
    forever begin
      // Wait for tx_en
      do @(vif.tx_monitor_cb);
      while(vif.tx_monitor_cb.tx_en !== 1'b1);
      
      // Collect frame bytes
      frame_bytes.delete();
      while(vif.tx_monitor_cb.tx_en === 1'b1) begin
        frame_bytes.push_back(vif.tx_monitor_cb.txd);
        @(vif.tx_monitor_cb);
      end
      
      // Parse frame
      item = parse_frame(frame_bytes);
      if(item != null)
        ap.write(item);
    end
  endtask

  task monitor_rx();
    gmii_item item;
    byte unsigned frame_bytes[$];
    
    forever begin
      // Wait for rx_dv
      do @(vif.rx_monitor_cb);
      while(vif.rx_monitor_cb.rx_dv !== 1'b1);
      
      // Collect frame bytes
      frame_bytes.delete();
      while(vif.rx_monitor_cb.rx_dv === 1'b1) begin
        frame_bytes.push_back(vif.rx_monitor_cb.rxd);
        @(vif.rx_monitor_cb);
      end
      
      // Parse frame
      item = parse_frame(frame_bytes);
      if(item != null)
        ap.write(item);
    end
  endtask

  function gmii_item parse_frame(byte unsigned frame_bytes[$]);
    gmii_item item;
    int idx = 0;
    
    if(frame_bytes.size() < 64) begin  // Minimum frame size
      `uvm_warning("GMII_MON", $sformatf("Frame too short: %0d bytes", frame_bytes.size()))
      return null;
    end
    
    item = gmii_item::type_id::create("item");
    
    // Skip preamble (7 bytes of 0x55)
    while(idx < frame_bytes.size() && frame_bytes[idx] == 8'h55) idx++;
    
    // SFD (0xD5)
    if(frame_bytes[idx] != 8'hD5) begin
      `uvm_warning("GMII_MON", "Invalid SFD")
      return null;
    end
    idx++;
    
    // Destination MAC
    for(int i = 0; i < 6; i++) item.dst_mac[i] = frame_bytes[idx++];
    
    // Source MAC
    for(int i = 0; i < 6; i++) item.src_mac[i] = frame_bytes[idx++];
    
    // EtherType/Length
    item.ethertype = {frame_bytes[idx], frame_bytes[idx+1]};
    idx += 2;
    
    // Check for VLAN tag
    if(item.ethertype == 16'h8100) begin
      item.has_vlan = 1;
      item.vlan_tci = {frame_bytes[idx], frame_bytes[idx+1]};
      idx += 2;
      item.ethertype = {frame_bytes[idx], frame_bytes[idx+1]};
      idx += 2;
    end
    
    // Payload (everything except last 4 bytes which are FCS)
    item.payload = new[frame_bytes.size() - idx - 4];
    for(int i = 0; i < item.payload.size(); i++)
      item.payload[i] = frame_bytes[idx++];
    
    // FCS
    item.fcs = {frame_bytes[idx+3], frame_bytes[idx+2], frame_bytes[idx+1], frame_bytes[idx]};
    
    return item;
  endfunction

endclass : gmii_monitor
