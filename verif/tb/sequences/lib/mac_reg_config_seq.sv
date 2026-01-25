// File: mac_reg_config_seq.sv
class mac_reg_config_seq extends uvm_sequence#(axi_lite_item);
	`uvm_object_utils(mac_reg_config_seq)
	rand bit [31:0] mac_addr;
	rand bit [31:0] mac_config;
	function new(string name = "mac_reg_config_seq");
		super.new(name);
	endfunction
	task body();
		axi_lite_item item;
		item = axi_lite_item::type_id::create("item");
		item.trans_type = AXI_LITE_WRITE;
		item.addr = mac_addr;
		item.wdata = mac_config;
		item.wstrb = 4'hF;
		start_item(item);
		finish_item(item);
	endtask
endclass : mac_reg_config_seq
