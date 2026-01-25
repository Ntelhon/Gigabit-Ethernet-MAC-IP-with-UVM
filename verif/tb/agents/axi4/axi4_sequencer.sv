// File: axi4_sequencer.sv
class axi4_sequencer #(
	int ADDR_WIDTH = 32,
	int DATA_WIDTH = 64,
	int ID_WIDTH   = 4,
	int USER_WIDTH = 1
) extends uvm_sequencer#(axi4_item#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH));
	`uvm_component_param_utils(axi4_sequencer#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH))
	axi4_config cfg;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(axi4_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
	endfunction
endclass : axi4_sequencer
