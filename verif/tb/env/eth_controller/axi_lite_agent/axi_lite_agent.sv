// File: axi_lite_agent.sv
class axi_lite_agent extends uvm_agent;
	`uvm_component_utils(axi_lite_agent)
	axi_lite_config cfg;
	axi_lite_driver driver;
	axi_lite_monitor monitor;
	axi_lite_sequencer sequencer;
	virtual axi_lite_if vif;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(axi_lite_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
		if(cfg.is_active == UVM_ACTIVE) begin
			sequencer = axi_lite_sequencer::type_id::create("sequencer", this);
			driver    = axi_lite_driver::type_id::create("driver", this);
			driver.vif = vif;
			driver.cfg = cfg;
			driver.sequencer = sequencer;
		end
		monitor = axi_lite_monitor::type_id::create("monitor", this);
		monitor.vif = vif;
		monitor.cfg = cfg;
	endfunction
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		if(cfg.is_active == UVM_ACTIVE)
			driver.seq_item_port.connect(sequencer.seq_item_export);
	endfunction
endclass : axi_lite_agent
