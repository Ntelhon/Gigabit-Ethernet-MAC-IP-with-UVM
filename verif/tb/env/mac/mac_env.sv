// File: mac_env.sv
class mac_env extends uvm_env;
	`uvm_component_utils(mac_env)
	mac_config cfg;
	gmii_agent gmii_ag;
	axi_stream_agent axi_stream_ag;
	mac_scoreboard scoreboard;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(mac_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
		gmii_ag = gmii_agent::type_id::create("gmii_ag", this);
		axi_stream_ag = axi_stream_agent::type_id::create("axi_stream_ag", this);
		scoreboard = mac_scoreboard::type_id::create("scoreboard", this);
	endfunction
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		gmii_ag.monitor.ap.connect(scoreboard.gmii_ap);
		axi_stream_ag.monitor.ap.connect(scoreboard.axi_stream_ap);
	endfunction
endclass : mac_env
