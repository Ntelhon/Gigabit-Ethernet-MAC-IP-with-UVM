// File: eth_virtual_sequencer.sv
class eth_virtual_sequencer extends uvm_sequencer;
	`uvm_component_utils(eth_virtual_sequencer)
	mac_sequencer mac_seqr;
	dma_sequencer dma_seqr;
	axi_lite_sequencer axi_lite_seqr;
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
endclass : eth_virtual_sequencer
