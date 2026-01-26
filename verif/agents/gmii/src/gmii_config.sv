// File: tb/agents/gmii/gmii_config.sv
class gmii_config extends uvm_object;

  // Agent configuration
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  gmii_direction_e        direction = GMII_TX;
  
  // Speed configuration
  typedef enum {SPEED_10M, SPEED_100M, SPEED_1G} speed_e;
  speed_e link_speed = SPEED_1G;
  
  // Protocol checking
  bit enable_protocol_checks = 1;
  bit enable_coverage = 1;
  bit check_crc = 1;
  bit check_ifg = 1;
  
  // Error injection probability
  int crc_error_percentage = 0;   // 0-100

  `uvm_object_utils_begin(gmii_config)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
    `uvm_field_enum(gmii_direction_e, direction, UVM_DEFAULT)
    `uvm_field_enum(speed_e, link_speed, UVM_DEFAULT)
    `uvm_field_int(enable_protocol_checks, UVM_DEFAULT)
    `uvm_field_int(check_crc, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "gmii_config");
    super.new(name);
  endfunction

endclass : gmii_config
