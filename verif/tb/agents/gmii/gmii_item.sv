// File: gmii_item.sv
class gmii_item extends uvm_sequence_item;
	rand bit [7:0] txd[];
	rand bit       tx_en[];
	rand bit       tx_er[];
	rand bit [7:0] rxd[];
	rand bit       rx_dv[];
	rand bit       rx_er[];
	bit [31:0]     pkt_id;
	bit [31:0]     pkt_len;
	function new(string name = "gmii_item");
		super.new(name);
	endfunction
	`uvm_object_utils_begin(gmii_item)
		`uvm_field_array_int(txd, UVM_ALL_ON)
		`uvm_field_array_int(tx_en, UVM_ALL_ON)
		`uvm_field_array_int(tx_er, UVM_ALL_ON)
		`uvm_field_array_int(rxd, UVM_ALL_ON)
		`uvm_field_array_int(rx_dv, UVM_ALL_ON)
		`uvm_field_array_int(rx_er, UVM_ALL_ON)
		`uvm_field_int(pkt_id, UVM_ALL_ON)
		`uvm_field_int(pkt_len, UVM_ALL_ON)
	`uvm_object_utils_end
endclass : gmii_item
