// File: tb/env/mac/mac_config.sv
class mac_config extends uvm_object;

  // Sub-agent configurations
  axi_stream_config tx_stream_cfg;
  axi_stream_config rx_stream_cfg;
  gmii_config       gmii_tx_cfg;
  gmii_config       gmii_rx_cfg;
  
  // Environment control
  bit enable_scoreboard = 1;
  bit enable_coverage   = 1;
  
  // MAC-specific settings
  bit [47:0] mac_address = 48'h001122334455;
  bit        promiscuous_mode = 0;
  bit        loopback_mode = 0;

  `uvm_object_utils_begin(mac_config)
    `uvm_field_object(tx_stream_cfg, UVM_DEFAULT)
    `uvm_field_object(rx_stream_cfg, UVM_DEFAULT)
    `uvm_field_object(gmii_tx_cfg, UVM_DEFAULT)
    `uvm_field_object(gmii_rx_cfg, UVM_DEFAULT)
    `uvm_field_int(enable_scoreboard, UVM_DEFAULT)
    `uvm_field_int(mac_address, UVM_DEFAULT | UVM_HEX)
  `uvm_object_utils_end

  function new(string name = "mac_config");
    super.new(name);
    
    // Create sub-configs with defaults
    tx_stream_cfg = axi_stream_config::type_id::create("tx_stream_cfg");
    tx_stream_cfg.is_active = UVM_PASSIVE;  // Monitor only (driven by DMA)
    
    rx_stream_cfg = axi_stream_config::type_id::create("rx_stream_cfg");
    rx_stream_cfg.is_active = UVM_PASSIVE;  // Monitor only (driven by MAC)
    
    gmii_tx_cfg = gmii_config::type_id::create("gmii_tx_cfg");
    gmii_tx_cfg.direction = GMII_TX;
    gmii_tx_cfg.is_active = UVM_PASSIVE;  // Monitor only (driven by MAC)
    
    gmii_rx_cfg = gmii_config::type_id::create("gmii_rx_cfg");
    gmii_rx_cfg.direction = GMII_RX;
    gmii_rx_cfg.is_active = UVM_ACTIVE;  // Drive packets into MAC
  endfunction

endclass : mac_config
