// File: dma_config.sv
class dma_config extends uvm_object;
	rand bit is_active;
	rand int unsigned max_transfer_size;
	rand bit enable_irq;
	function new(string name = "dma_config");
		super.new(name);
		is_active = 1;
		max_transfer_size = 4096;
		enable_irq = 1;
	endfunction
	`uvm_object_utils_begin(dma_config)
		`uvm_field_int(is_active, UVM_ALL_ON)
		`uvm_field_int(max_transfer_size, UVM_ALL_ON)
		`uvm_field_int(enable_irq, UVM_ALL_ON)
	`uvm_object_utils_end
endclass : dma_config
