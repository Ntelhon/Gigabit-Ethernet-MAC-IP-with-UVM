// File: eth_tx_path_test.sv
class eth_tx_path_test extends eth_base_test;
	`uvm_component_utils(eth_tx_path_test)
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	task run_phase(uvm_phase phase);
		eth_tx_path_vseq vseq;
		vseq = eth_tx_path_vseq::type_id::create("vseq");
		vseq.vseqr = env.vseqr;
		vseq.start(env.vseqr);
	endtask
endclass : eth_tx_path_test
