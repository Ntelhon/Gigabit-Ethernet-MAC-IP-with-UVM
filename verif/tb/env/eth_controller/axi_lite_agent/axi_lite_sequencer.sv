// File: axi_lite_sequencer.sv
class axi_lite_sequencer extends uvm_sequencer#(axi_lite_item);
	`uvm_component_utils(axi_lite_sequencer)
	axi_lite_config cfg;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(axi_lite_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
	endfunction
endclass : axi_lite_sequencer
