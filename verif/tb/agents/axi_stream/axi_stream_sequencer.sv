// File: axi_stream_sequencer.sv
class axi_stream_sequencer #(
	int DATA_WIDTH = 32,
	int USER_WIDTH = 1,
	int DEST_WIDTH = 1,
	int ID_WIDTH   = 1
) extends uvm_sequencer #(axi_stream_item#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH));
	`uvm_component_param_utils(axi_stream_sequencer#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH))
	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction
endclass : axi_stream_sequencer
