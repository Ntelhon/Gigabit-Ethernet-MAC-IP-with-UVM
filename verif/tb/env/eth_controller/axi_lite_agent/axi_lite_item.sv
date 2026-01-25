// File: axi_lite_item.sv
typedef enum {AXI_LITE_WRITE, AXI_LITE_READ} axi_lite_trans_type_e;
class axi_lite_item extends uvm_sequence_item;
	rand axi_lite_trans_type_e trans_type;
	rand bit [31:0] addr;
	rand bit [31:0] wdata;
	rand bit [3:0]  wstrb;
	rand bit [31:0] rdata;
	rand bit [1:0]  resp;
	function new(string name = "axi_lite_item");
		super.new(name);
	endfunction
	`uvm_object_utils_begin(axi_lite_item)
		`uvm_field_enum(axi_lite_trans_type_e, trans_type, UVM_ALL_ON)
		`uvm_field_int(addr, UVM_ALL_ON)
		`uvm_field_int(wdata, UVM_ALL_ON)
		`uvm_field_int(wstrb, UVM_ALL_ON)
		`uvm_field_int(rdata, UVM_ALL_ON)
		`uvm_field_int(resp, UVM_ALL_ON)
	`uvm_object_utils_end
endclass : axi_lite_item
