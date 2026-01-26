// File: tb/agents/axi4/axi4_config.sv
class axi4_config extends uvm_object;

  // Agent configuration
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  axi4_agent_type_e       agent_type = AXI4_MASTER;
  
  // Interface parameters
  int addr_width = 32;
  int data_width = 64;
  int id_width   = 4;
  int user_width = 1;
  
  // Protocol checking
  bit enable_protocol_checks = 1;
  bit enable_coverage = 1;
  
  // Slave response configuration (for slave agents)
  int min_response_delay = 0;
  int max_response_delay = 5;
  
  // Outstanding transaction limits
  int max_outstanding_reads  = 8;
  int max_outstanding_writes = 8;

  `uvm_object_utils_begin(axi4_config)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
    `uvm_field_enum(axi4_agent_type_e, agent_type, UVM_DEFAULT)
    `uvm_field_int(addr_width, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(data_width, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(enable_protocol_checks, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "axi4_config");
    super.new(name);
  endfunction

endclass : axi4_config
