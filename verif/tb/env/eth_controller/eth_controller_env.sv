// File: eth_controller_env.sv
class eth_controller_env extends uvm_env;
	`uvm_component_utils(eth_controller_env)
	eth_controller_config cfg;
	mac_env mac_env_inst;
	dma_env dma_env_inst;
	axi_lite_agent axi_lite_ag;
	eth_virtual_sequencer vseqr;
	eth_scoreboard scoreboard;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(eth_controller_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
		mac_env_inst = mac_env::type_id::create("mac_env_inst", this);
		dma_env_inst = dma_env::type_id::create("dma_env_inst", this);
		axi_lite_ag = axi_lite_agent::type_id::create("axi_lite_ag", this);
		vseqr = eth_virtual_sequencer::type_id::create("vseqr", this);
		scoreboard = eth_scoreboard::type_id::create("scoreboard", this);
	endfunction
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		mac_env_inst.scoreboard.connect(scoreboard.mac_ap);
		dma_env_inst.scoreboard.connect(scoreboard.dma_ap);
		axi_lite_ag.monitor.ap.connect(scoreboard.axi_lite_ap);
	endfunction
endclass : eth_controller_env
