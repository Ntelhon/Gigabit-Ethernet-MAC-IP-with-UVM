// File: axi_lite_read_seq.sv
class axi_lite_read_seq extends axi_lite_base_seq;
	`uvm_object_utils(axi_lite_read_seq)
	rand bit [31:0] addr;
	function new(string name = "axi_lite_read_seq");
		super.new(name);
	endfunction
	task body();
		axi_lite_item item;
		item = axi_lite_item::type_id::create("item");
		item.trans_type = AXI_LITE_READ;
		item.addr = addr;
		start_item(item);
		finish_item(item);
	endtask
endclass : axi_lite_read_seq
