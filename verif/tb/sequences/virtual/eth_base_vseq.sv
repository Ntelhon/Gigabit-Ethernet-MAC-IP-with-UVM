// File: eth_base_vseq.sv
class eth_base_vseq extends uvm_sequence;
	`uvm_object_utils(eth_base_vseq)
	eth_virtual_sequencer vseqr;
	function new(string name = "eth_base_vseq");
		super.new(name);
	endfunction
	task body();
		// Base virtual sequence body
	endtask
endclass : eth_base_vseq
