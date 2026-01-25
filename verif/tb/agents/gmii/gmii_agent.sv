// File: gmii_agent.sv
class gmii_agent extends uvm_agent;
	`uvm_component_utils(gmii_agent)
	gmii_config cfg;
	gmii_driver driver;
	gmii_monitor monitor;
	gmii_sequencer sequencer;
	virtual gmii_if vif;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(gmii_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
		if(cfg.is_active == UVM_ACTIVE) begin
			sequencer = gmii_sequencer::type_id::create("sequencer", this);
			driver    = gmii_driver::type_id::create("driver", this);
			driver.vif = vif;
			driver.cfg = cfg;
			driver.sequencer = sequencer;
		end
		monitor = gmii_monitor::type_id::create("monitor", this);
		monitor.vif = vif;
		monitor.cfg = cfg;
	endfunction
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		if(cfg.is_active == UVM_ACTIVE)
			driver.seq_item_port.connect(sequencer.seq_item_export);
	endfunction
endclass : gmii_agent
