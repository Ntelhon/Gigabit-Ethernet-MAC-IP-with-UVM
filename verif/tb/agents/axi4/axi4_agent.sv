// File: axi4_agent.sv
class axi4_agent #(
	int ADDR_WIDTH = 32,
	int DATA_WIDTH = 64,
	int ID_WIDTH   = 4,
	int USER_WIDTH = 1
) extends uvm_agent;
	`uvm_component_param_utils(axi4_agent#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH))
	axi4_config cfg;
	axi4_driver#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH) driver;
	axi4_monitor#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH) monitor;
	axi4_sequencer#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH) sequencer;
	virtual axi4_if#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH) vif;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(axi4_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
		if(cfg.is_active == UVM_ACTIVE) begin
			sequencer = axi4_sequencer#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH)::type_id::create("sequencer", this);
			driver    = axi4_driver#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH)::type_id::create("driver", this);
			driver.vif = vif;
			driver.cfg = cfg;
			driver.sequencer = sequencer;
		end
		monitor = axi4_monitor#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH)::type_id::create("monitor", this);
		monitor.vif = vif;
		monitor.cfg = cfg;
	endfunction
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		if(cfg.is_active == UVM_ACTIVE)
			driver.seq_item_port.connect(sequencer.seq_item_export);
	endfunction
endclass : axi4_agent
