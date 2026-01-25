// File: mac_sanity_test.sv
class mac_sanity_test extends eth_base_test;
	`uvm_component_utils(mac_sanity_test)
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	task run_phase(uvm_phase phase);
		mac_reg_config_seq seq;
		seq = mac_reg_config_seq::type_id::create("seq");
		seq.start(env.mac_env_inst.gmii_ag.sequencer);
	endtask
endclass : mac_sanity_test
