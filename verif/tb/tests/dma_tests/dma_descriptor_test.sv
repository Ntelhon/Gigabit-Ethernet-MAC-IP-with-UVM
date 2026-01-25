// File: dma_descriptor_test.sv
class dma_descriptor_test extends eth_base_test;
	`uvm_component_utils(dma_descriptor_test)
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	task run_phase(uvm_phase phase);
		dma_reg_config_seq seq;
		seq = dma_reg_config_seq::type_id::create("seq");
		seq.start(env.dma_env_inst.axi4_ag.sequencer);
	endtask
endclass : dma_descriptor_test
