// File: memory_model.sv
class memory_model extends uvm_component;
	`uvm_component_utils(memory_model)
	uvm_analysis_port #(memory_model_item) ap;
	function new(string name, uvm_component parent);
		super.new(name, parent);
		ap = new("ap", this);
	endfunction
	// TODO: Implement memory model logic
endclass : memory_model
