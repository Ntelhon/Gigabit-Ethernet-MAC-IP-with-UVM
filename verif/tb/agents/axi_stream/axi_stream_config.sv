// File: axi_stream_config.sv
class axi_stream_config extends uvm_object;
	uvm_active_passive_enum is_active = UVM_ACTIVE;
	int data_width = 32;
	int user_width = 1;
	int dest_width = 1;
	int id_width   = 1;
	bit enable_protocol_checks = 1;
	bit enable_coverage = 1;
	int max_ready_delay = 10;
	`uvm_object_utils_begin(axi_stream_config)
		`uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
		`uvm_field_int(data_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(enable_protocol_checks, UVM_DEFAULT)
		`uvm_field_int(enable_coverage, UVM_DEFAULT)
	`uvm_object_utils_end
	function new(string name = "axi_stream_config");
		super.new(name);
	endfunction
endclass : axi_stream_config
