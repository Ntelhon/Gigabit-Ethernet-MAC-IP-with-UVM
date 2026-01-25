// File: gmii_burst_seq.sv
class gmii_burst_seq extends uvm_sequence#(gmii_item);
	`uvm_object_utils(gmii_burst_seq)
	rand bit [7:0] burst_data[][];
	rand int unsigned burst_len[];
	function new(string name = "gmii_burst_seq");
		super.new(name);
	endfunction
	task body();
		gmii_item item;
		for(int pkt = 0; pkt < burst_data.size(); pkt++) begin
			item = gmii_item::type_id::create($sformatf("item_%0d", pkt));
			item.txd = burst_data[pkt];
			item.tx_en = new[burst_len[pkt]];
			item.tx_er = new[burst_len[pkt]];
			foreach(item.tx_en[i]) item.tx_en[i] = 1;
			foreach(item.tx_er[i]) item.tx_er[i] = 0;
			item.pkt_len = burst_len[pkt];
			start_item(item);
			finish_item(item);
		end
	endtask
endclass : gmii_burst_seq
