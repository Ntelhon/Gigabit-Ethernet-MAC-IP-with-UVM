// File: dma_reg_config_seq.sv
class dma_reg_config_seq extends uvm_sequence#(axi_lite_item);
	`uvm_object_utils(dma_reg_config_seq)
	rand bit [31:0] dma_addr;
	rand bit [31:0] dma_config;
	function new(string name = "dma_reg_config_seq");
		super.new(name);
	endfunction
	task body();
		axi_lite_item item;
		item = axi_lite_item::type_id::create("item");
		item.trans_type = AXI_LITE_WRITE;
		item.addr = dma_addr;
		item.wdata = dma_config;
		item.wstrb = 4'hF;
		start_item(item);
		finish_item(item);
	endtask
endclass : dma_reg_config_seq
