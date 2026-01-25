// File: tb/env/eth_controller/axi_lite_agent/axi_lite_config.sv
class axi_lite_config extends uvm_object;

  // Agent configuration
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  
  // Interface parameters
  int addr_width = 32;
  int data_width = 32;
  
  // Address map (for wrapper decoding)
  bit [31:0] mac_base_addr = 32'h0000_0000;
  bit [31:0] mac_end_addr  = 32'h0000_02FF;
  bit [31:0] dma_base_addr = 32'h0000_0300;
  bit [31:0] dma_end_addr  = 32'h0000_0FFF;
  
  // Protocol checking
  bit enable_protocol_checks = 1;
  bit enable_coverage = 1;
  
  // Timing
  int max_response_delay = 10;

  `uvm_object_utils_begin(axi_lite_config)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
    `uvm_field_int(addr_width, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(data_width, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(mac_base_addr, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(dma_base_addr, UVM_DEFAULT | UVM_HEX)
  `uvm_object_utils_end

  function new(string name = "axi_lite_config");
    super.new(name);
  endfunction

  // Helper: Determine target (MAC or DMA)
  function bit is_mac_addr(bit [31:0] addr);
    return (addr >= mac_base_addr && addr <= mac_end_addr);
  endfunction

  function bit is_dma_addr(bit [31:0] addr);
    return (addr >= dma_base_addr && addr <= dma_end_addr);
  endfunction

endclass : axi_lite_config
