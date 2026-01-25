// File: axi_lite_monitor.sv
class axi_lite_monitor extends uvm_monitor;
	`uvm_component_utils(axi_lite_monitor)
	virtual axi_lite_if vif;
	axi_lite_config cfg;
	uvm_analysis_port #(axi_lite_item) ap;
	function new(string name, uvm_component parent);
		super.new(name, parent);
		ap = new("ap", this);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(axi_lite_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
	endfunction
	task run_phase(uvm_phase phase);
		forever begin
			axi_lite_item item = axi_lite_item::type_id::create("item");
			collect_trans(item);
			ap.write(item);
		end
	endtask
	task collect_trans(axi_lite_item item);
		// Collect write
		if(vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
			item.trans_type = AXI_LITE_WRITE;
			item.addr = vif.monitor_cb.awaddr;
			item.wdata = vif.monitor_cb.wdata;
			item.wstrb = vif.monitor_cb.wstrb;
			do @(vif.monitor_cb);
			while(!(vif.monitor_cb.bvalid && vif.monitor_cb.bready));
			item.resp = vif.monitor_cb.bresp;
		end
		// Collect read
		if(vif.monitor_cb.arvalid && vif.monitor_cb.arready) begin
			item.trans_type = AXI_LITE_READ;
			item.addr = vif.monitor_cb.araddr;
			do @(vif.monitor_cb);
			while(!(vif.monitor_cb.rvalid && vif.monitor_cb.rready));
			item.rdata = vif.monitor_cb.rdata;
			item.resp  = vif.monitor_cb.rresp;
		end
	endtask
endclass : axi_lite_monitor
