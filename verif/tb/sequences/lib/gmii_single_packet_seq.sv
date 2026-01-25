// File: gmii_single_packet_seq.sv
class gmii_single_packet_seq extends uvm_sequence#(gmii_item);
	`uvm_object_utils(gmii_single_packet_seq)
	rand bit [7:0] pkt_data[];
	rand int unsigned pkt_len;
	function new(string name = "gmii_single_packet_seq");
		super.new(name);
	endfunction
	task body();
		gmii_item item;
		item = gmii_item::type_id::create("item");
		item.txd = pkt_data;
		item.tx_en = new[pkt_len];
		item.tx_er = new[pkt_len];
		foreach(item.tx_en[i]) item.tx_en[i] = 1;
		foreach(item.tx_er[i]) item.tx_er[i] = 0;
		item.pkt_len = pkt_len;
		start_item(item);
		finish_item(item);
	endtask
endclass : gmii_single_packet_seq
