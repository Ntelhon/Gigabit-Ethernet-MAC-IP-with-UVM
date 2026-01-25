// File: axi4_monitor.sv
class axi4_monitor #(
	int ADDR_WIDTH = 32,
	int DATA_WIDTH = 64,
	int ID_WIDTH   = 4,
	int USER_WIDTH = 1
) extends uvm_monitor;
	`uvm_component_param_utils(axi4_monitor#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH))
	typedef axi4_item#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH) item_t;
	virtual axi4_if#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH) vif;
	axi4_config cfg;
	uvm_analysis_port #(item_t) ap;
	function new(string name, uvm_component parent);
		super.new(name, parent);
		ap = new("ap", this);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(axi4_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
	endfunction
	task run_phase(uvm_phase phase);
		fork
			monitor_write();
			monitor_read();
		join_none
	endtask
	task monitor_write();
		item_t item;
		bit [ADDR_WIDTH-1:0] addr;
		bit [7:0] len;
		bit [ID_WIDTH-1:0] id;
		forever begin
			do @(vif.monitor_cb);
			while(!(vif.monitor_cb.awvalid && vif.monitor_cb.awready));
			item = item_t::type_id::create("item");
			item.trans_type = AXI4_WRITE;
			item.id    = vif.monitor_cb.awid;
			item.addr  = vif.monitor_cb.awaddr;
			item.len   = vif.monitor_cb.awlen;
			item.size  = vif.monitor_cb.awsize;
			item.burst = vif.monitor_cb.awburst;
			item.data = new[item.len + 1];
			item.strb = new[item.len + 1];
			for(int i = 0; i <= item.len; i++) begin
				do @(vif.monitor_cb);
				while(!(vif.monitor_cb.wvalid && vif.monitor_cb.wready));
				item.data[i] = vif.monitor_cb.wdata;
				item.strb[i] = vif.monitor_cb.wstrb;
			end
			do @(vif.monitor_cb);
			while(!(vif.monitor_cb.bvalid && vif.monitor_cb.bready));
			item.resp = new[1];
			item.resp[0] = vif.monitor_cb.bresp;
			ap.write(item);
		end
	endtask
	task monitor_read();
		item_t item;
		forever begin
			do @(vif.monitor_cb);
			while(!(vif.monitor_cb.arvalid && vif.monitor_cb.arready));
			item = item_t::type_id::create("item");
			item.trans_type = AXI4_READ;
			item.id    = vif.monitor_cb.arid;
			item.addr  = vif.monitor_cb.araddr;
			item.len   = vif.monitor_cb.arlen;
			item.size  = vif.monitor_cb.arsize;
			item.burst = vif.monitor_cb.arburst;
			item.data = new[item.len + 1];
			item.resp = new[item.len + 1];
			for(int i = 0; i <= item.len; i++) begin
				do @(vif.monitor_cb);
				while(!(vif.monitor_cb.rvalid && vif.monitor_cb.rready));
				item.data[i] = vif.monitor_cb.rdata;
				item.resp[i] = vif.monitor_cb.rresp;
			end
			ap.write(item);
		end
	endtask
endclass : axi4_monitor
