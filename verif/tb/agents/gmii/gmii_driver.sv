// File: gmii_driver.sv
class gmii_driver extends uvm_driver#(gmii_item);
	`uvm_component_utils(gmii_driver)
	virtual gmii_if vif;
	gmii_config cfg;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(gmii_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
	endfunction
	task run_phase(uvm_phase phase);
		gmii_item item;
		forever begin
			seq_item_port.get_next_item(item);
			drive_tx(item);
			seq_item_port.item_done();
		end
	endtask
	task drive_tx(gmii_item item);
		for(int i = 0; i < item.pkt_len; i++) begin
			@(vif.tx_driver_cb);
			vif.tx_driver_cb.txd   <= item.txd[i];
			vif.tx_driver_cb.tx_en <= item.tx_en[i];
			vif.tx_driver_cb.tx_er <= item.tx_er[i];
		end
		// Deassert after packet
		@(vif.tx_driver_cb);
		vif.tx_driver_cb.tx_en <= 0;
		vif.tx_driver_cb.tx_er <= 0;
	endtask
endclass : gmii_driver
