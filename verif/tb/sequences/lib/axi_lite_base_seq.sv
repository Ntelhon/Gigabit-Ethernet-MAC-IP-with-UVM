// File: axi_lite_base_seq.sv
class axi_lite_base_seq extends uvm_sequence#(axi_lite_item);
	`uvm_object_utils(axi_lite_base_seq)
	function new(string name = "axi_lite_base_seq");
		super.new(name);
	endfunction
	task body();
		// Base sequence body for AXI-Lite
	endtask
endclass : axi_lite_base_seq
