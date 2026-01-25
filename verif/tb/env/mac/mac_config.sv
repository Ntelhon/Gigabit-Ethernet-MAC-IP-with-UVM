// File: mac_config.sv
class mac_config extends uvm_object;
	rand bit is_active;
	rand bit enable_crc_check;
	rand int unsigned max_pkt_size;
	function new(string name = "mac_config");
		super.new(name);
		is_active = 1;
		enable_crc_check = 1;
		max_pkt_size = 1518;
	endfunction
	`uvm_object_utils_begin(mac_config)
		`uvm_field_int(is_active, UVM_ALL_ON)
		`uvm_field_int(enable_crc_check, UVM_ALL_ON)
		`uvm_field_int(max_pkt_size, UVM_ALL_ON)
	`uvm_object_utils_end
endclass : mac_config
