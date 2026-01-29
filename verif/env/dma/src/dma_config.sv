// File: tb/env/dma/dma_config.sv
class dma_config extends uvm_object;

  // Sub-agent configurations
  axi4_config           axi4_mem_cfg;
  axi_stream_config     axis_tx_cfg;  // DMA → MAC
  axi_stream_config     axis_rx_cfg;  // MAC → DMA
  
  // Environment control
  bit enable_scoreboard = 1;
  bit enable_coverage   = 1;
  
  // DMA-specific settings
  bit [31:0] tx_desc_base_addr = 32'h1000_0000;
  bit [31:0] rx_desc_base_addr = 32'h2000_0000;
  bit [31:0] buffer_base_addr  = 32'h3000_0000;
  int        num_tx_descriptors = 8;
  int        num_rx_descriptors = 8;

  `uvm_object_utils_begin(dma_config)
    `uvm_field_object(axi4_mem_cfg, UVM_DEFAULT)
    `uvm_field_object(axis_tx_cfg, UVM_DEFAULT)
    `uvm_field_object(axis_rx_cfg, UVM_DEFAULT)
    `uvm_field_int(enable_scoreboard, UVM_DEFAULT)
    `uvm_field_int(tx_desc_base_addr, UVM_DEFAULT | UVM_HEX)
  `uvm_object_utils_end

  function new(string name = "dma_config");
    super.new(name);
    
    axi4_mem_cfg = axi4_config::type_id::create("axi4_mem_cfg");
    axi4_mem_cfg.agent_type = AXI4_SLAVE;  // Slave agent for memory
    axi4_mem_cfg.is_active = UVM_ACTIVE;   // Driver active to respond to DMA requests
    
    axis_tx_cfg = axi_stream_config::type_id::create("axis_tx_cfg");
    axis_tx_cfg.is_active = UVM_PASSIVE;  // DMA drives, we monitor
    
    axis_rx_cfg = axi_stream_config::type_id::create("axis_rx_cfg");
    axis_rx_cfg.is_active = UVM_PASSIVE;  // MAC drives, we monitor
  endfunction

endclass : dma_config
