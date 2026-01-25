// File: mac_scoreboard.sv
class mac_scoreboard extends uvm_scoreboard;
	`uvm_component_utils(mac_scoreboard)
	uvm_analysis_imp_gmii #(gmii_item, mac_scoreboard) gmii_ap;
	uvm_analysis_imp_axi_stream #(axi_stream_item, mac_scoreboard) axi_stream_ap;
	function new(string name, uvm_component parent);
		super.new(name, parent);
		gmii_ap = new("gmii_ap", this);
		axi_stream_ap = new("axi_stream_ap", this);
	endfunction
	function void write_gmii(gmii_item t);
		// Scoreboard logic for GMII
		// TODO: Implement packet comparison, CRC check, etc.
	endfunction
	function void write_axi_stream(axi_stream_item t);
		// Scoreboard logic for AXI-Stream
		// TODO: Implement packet comparison, data integrity check, etc.
	endfunction
endclass : mac_scoreboard
