// File: axi_lite_driver.sv
class axi_lite_driver extends uvm_driver#(axi_lite_item);
	`uvm_component_utils(axi_lite_driver)
	virtual axi_lite_if vif;
	axi_lite_config cfg;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(axi_lite_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("NOCFG", "Config object not found")
	endfunction
	task run_phase(uvm_phase phase);
		axi_lite_item item;
		forever begin
			seq_item_port.get_next_item(item);
			if(item.trans_type == AXI_LITE_WRITE)
				drive_write(item);
			else
				drive_read(item);
			seq_item_port.item_done();
		end
	endtask
	task drive_write(axi_lite_item item);
		@(vif.master_driver_cb);
		vif.master_driver_cb.awaddr  <= item.addr;
		vif.master_driver_cb.awvalid <= 1;
		do @(vif.master_driver_cb);
		while(!vif.master_driver_cb.awready);
		vif.master_driver_cb.awvalid <= 0;
		@(vif.master_driver_cb);
		vif.master_driver_cb.wdata   <= item.wdata;
		vif.master_driver_cb.wstrb   <= item.wstrb;
		vif.master_driver_cb.wvalid  <= 1;
		do @(vif.master_driver_cb);
		while(!vif.master_driver_cb.wready);
		vif.master_driver_cb.wvalid  <= 0;
		@(vif.master_driver_cb);
		vif.master_driver_cb.bready  <= 1;
		do @(vif.master_driver_cb);
		while(!vif.master_driver_cb.bvalid);
		item.resp = vif.master_driver_cb.bresp;
		vif.master_driver_cb.bready  <= 0;
	endtask
	task drive_read(axi_lite_item item);
		@(vif.master_driver_cb);
		vif.master_driver_cb.araddr  <= item.addr;
		vif.master_driver_cb.arvalid <= 1;
		do @(vif.master_driver_cb);
		while(!vif.master_driver_cb.arready);
		vif.master_driver_cb.arvalid <= 0;
		@(vif.master_driver_cb);
		vif.master_driver_cb.rready  <= 1;
		do @(vif.master_driver_cb);
		while(!vif.master_driver_cb.rvalid);
		item.rdata = vif.master_driver_cb.rdata;
		item.resp  = vif.master_driver_cb.rresp;
		vif.master_driver_cb.rready  <= 0;
	endtask
endclass : axi_lite_driver
