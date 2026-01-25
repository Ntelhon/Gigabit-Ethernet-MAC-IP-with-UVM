// File: eth_controller_config.sv
class eth_controller_config extends uvm_object;
	rand bit is_active;
	rand bit enable_mac;
	rand bit enable_dma;
	rand bit enable_axi_lite;
	function new(string name = "eth_controller_config");
		super.new(name);
		is_active = 1;
		enable_mac = 1;
		enable_dma = 1;
		enable_axi_lite = 1;
	endfunction
	`uvm_object_utils_begin(eth_controller_config)
		`uvm_field_int(is_active, UVM_ALL_ON)
		`uvm_field_int(enable_mac, UVM_ALL_ON)
		`uvm_field_int(enable_dma, UVM_ALL_ON)
		`uvm_field_int(enable_axi_lite, UVM_ALL_ON)
	`uvm_object_utils_end
endclass : eth_controller_config
