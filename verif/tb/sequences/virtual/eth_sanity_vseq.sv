// File: eth_sanity_vseq.sv
class eth_sanity_vseq extends eth_base_vseq;
	`uvm_object_utils(eth_sanity_vseq)
	function new(string name = "eth_sanity_vseq");
		super.new(name);
	endfunction
	task body();
		// Sanity virtual sequence body
	endtask
endclass : eth_sanity_vseq
