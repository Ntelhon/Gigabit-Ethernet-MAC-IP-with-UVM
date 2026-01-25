// File: eth_scoreboard.sv
class eth_scoreboard extends uvm_scoreboard;
	`uvm_component_utils(eth_scoreboard)
	uvm_analysis_imp_mac #(mac_scoreboard, eth_scoreboard) mac_ap;
	uvm_analysis_imp_dma #(dma_scoreboard, eth_scoreboard) dma_ap;
	uvm_analysis_imp_axi_lite #(axi_lite_item, eth_scoreboard) axi_lite_ap;
	function new(string name, uvm_component parent);
		super.new(name, parent);
		mac_ap = new("mac_ap", this);
		dma_ap = new("dma_ap", this);
		axi_lite_ap = new("axi_lite_ap", this);
	endfunction
	function void write_mac(mac_scoreboard t);
		// Scoreboard logic for MAC
		// TODO: Implement MAC-level checks
	endfunction
	function void write_dma(dma_scoreboard t);
		// Scoreboard logic for DMA
		// TODO: Implement DMA-level checks
	endfunction
	function void write_axi_lite(axi_lite_item t);
		// Scoreboard logic for AXI-Lite
		// TODO: Implement AXI-Lite-level checks
	endfunction
endclass : eth_scoreboard
