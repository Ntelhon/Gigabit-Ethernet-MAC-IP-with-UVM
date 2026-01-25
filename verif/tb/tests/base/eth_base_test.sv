// File: eth_base_test.sv
class eth_base_test extends uvm_test;
	`uvm_component_utils(eth_base_test)
	eth_controller_env env;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		env = eth_controller_env::type_id::create("env", this);
	endfunction
endclass : eth_base_test
