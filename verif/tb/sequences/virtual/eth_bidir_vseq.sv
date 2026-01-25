// File: eth_bidir_vseq.sv
class eth_bidir_vseq extends eth_base_vseq;
	`uvm_object_utils(eth_bidir_vseq)
	function new(string name = "eth_bidir_vseq");
		super.new(name);
	endfunction
	task body();
		// Bidirectional virtual sequence body
	endtask
endclass : eth_bidir_vseq
