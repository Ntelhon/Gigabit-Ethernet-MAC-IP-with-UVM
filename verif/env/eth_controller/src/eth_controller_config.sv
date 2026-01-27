// File: tb/env/eth_controller/eth_controller_config.sv
class eth_controller_config extends uvm_object;

  // Sub-environment configs
  mac_config      mac_cfg;
  dma_config      dma_cfg;
  axi_lite_config axi_lite_cfg;
  
  // Environment control
  bit enable_mac = 1;
  bit enable_dma = 1;
  bit enable_system_scoreboard = 1;
  bit enable_coverage = 1;
  
  // Address map (wrapper-level)
  bit [31:0] mac_reg_base = 32'h0000_0000;
  bit [31:0] mac_reg_end  = 32'h0000_01FF;
  bit [31:0] dma_reg_base = 32'h0000_0200;
  bit [31:0] dma_reg_end  = 32'h0000_03FF;

  `uvm_object_utils_begin(eth_controller_config)
    `uvm_field_object(mac_cfg, UVM_DEFAULT)
    `uvm_field_object(dma_cfg, UVM_DEFAULT)
    `uvm_field_object(axi_lite_cfg, UVM_DEFAULT)
    `uvm_field_int(enable_mac, UVM_DEFAULT)
    `uvm_field_int(enable_dma, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "eth_controller_config");
    super.new(name);
    
    mac_cfg = mac_config::type_id::create("mac_cfg");
    dma_cfg = dma_config::type_id::create("dma_cfg");
    
    axi_lite_cfg = axi_lite_config::type_id::create("axi_lite_cfg");
    axi_lite_cfg.mac_base_addr = mac_reg_base;
    axi_lite_cfg.mac_end_addr  = mac_reg_end;
    axi_lite_cfg.dma_base_addr = dma_reg_base;
    axi_lite_cfg.dma_end_addr  = dma_reg_end;
  endfunction

endclass : eth_controller_config
