// File: axi_lite_config.sv
class axi_lite_config extends uvm_object;
	rand bit is_active;
	rand int unsigned max_reg_addr;
	function new(string name = "axi_lite_config");
		super.new(name);
		is_active = 1;
		max_reg_addr = 32'hFFFF;
	endfunction
	`uvm_object_utils_begin(axi_lite_config)
		`uvm_field_int(is_active, UVM_ALL_ON)
		`uvm_field_int(max_reg_addr, UVM_ALL_ON)
	`uvm_object_utils_end
endclass : axi_lite_config
