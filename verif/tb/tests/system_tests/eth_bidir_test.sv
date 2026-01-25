// File: eth_bidir_test.sv
class eth_bidir_test extends eth_base_test;
	`uvm_component_utils(eth_bidir_test)
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	task run_phase(uvm_phase phase);
		eth_bidir_vseq vseq;
		vseq = eth_bidir_vseq::type_id::create("vseq");
		vseq.vseqr = env.vseqr;
		vseq.start(env.vseqr);
	endtask
endclass : eth_bidir_test
