// File: dma_env.sv
class dma_env extends uvm_env;
	`uvm_component_utils(dma_env)
	dma_config cfg;
	axi4_agent axi4_ag;
	dma_scoreboard scoreboard;
	memory_model mem_model;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(dma_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
		axi4_ag = axi4_agent::type_id::create("axi4_ag", this);
		scoreboard = dma_scoreboard::type_id::create("scoreboard", this);
		mem_model = memory_model::type_id::create("mem_model", this);
	endfunction
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		axi4_ag.monitor.ap.connect(scoreboard.axi4_ap);
		mem_model.ap.connect(scoreboard.mem_ap);
	endfunction
endclass : dma_env
