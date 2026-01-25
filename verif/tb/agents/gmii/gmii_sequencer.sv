// File: gmii_sequencer.sv
class gmii_sequencer extends uvm_sequencer#(gmii_item);
	`uvm_component_utils(gmii_sequencer)
	gmii_config cfg;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(gmii_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
	endfunction
endclass : gmii_sequencer
