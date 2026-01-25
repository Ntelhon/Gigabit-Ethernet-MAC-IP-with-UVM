// File: gmii_monitor.sv
class gmii_monitor extends uvm_monitor;
	`uvm_component_utils(gmii_monitor)
	virtual gmii_if vif;
	gmii_config cfg;
	uvm_analysis_port #(gmii_item) ap;
	function new(string name, uvm_component parent);
		super.new(name, parent);
		ap = new("ap", this);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(gmii_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
	endfunction
	task run_phase(uvm_phase phase);
		gmii_item item;
		forever begin
			item = gmii_item::type_id::create("item");
			collect_rx(item);
			ap.write(item);
		end
	endtask
	task collect_rx(gmii_item item);
		int i = 0;
		item.pkt_len = 0;
		do begin
			@(vif.rx_monitor_cb);
			item.rxd.push_back(vif.rx_monitor_cb.rxd);
			item.rx_dv.push_back(vif.rx_monitor_cb.rx_dv);
			item.rx_er.push_back(vif.rx_monitor_cb.rx_er);
			i++;
		end while(vif.rx_monitor_cb.rx_dv);
		item.pkt_len = i;
	endtask
endclass : gmii_monitor
