// File: axi_lite_write_seq.sv
class axi_lite_write_seq extends axi_lite_base_seq;
	`uvm_object_utils(axi_lite_write_seq)
	rand bit [31:0] addr;
	rand bit [31:0] wdata;
	rand bit [3:0]  wstrb;
	function new(string name = "axi_lite_write_seq");
		super.new(name);
	endfunction
	task body();
		axi_lite_item item;
		item = axi_lite_item::type_id::create("item");
		item.trans_type = AXI_LITE_WRITE;
		item.addr = addr;
		item.wdata = wdata;
		item.wstrb = wstrb;
		start_item(item);
		finish_item(item);
	endtask
endclass : axi_lite_write_seq
