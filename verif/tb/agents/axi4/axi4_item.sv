// File: axi4_item.sv
class axi4_item #(
	int ADDR_WIDTH = 32,
	int DATA_WIDTH = 64,
	int ID_WIDTH   = 4,
	int USER_WIDTH = 1
) extends uvm_sequence_item;
	typedef enum {AXI4_WRITE, AXI4_READ} axi4_trans_type_e;
	rand axi4_trans_type_e trans_type;
	rand bit [ID_WIDTH-1:0]    id;
	rand bit [ADDR_WIDTH-1:0]  addr;
	rand bit [7:0]             len;
	rand bit [2:0]             size;
	rand bit [1:0]             burst;
	rand bit                   lock;
	rand bit [3:0]             cache;
	rand bit [2:0]             prot;
	rand bit [3:0]             qos;
	rand bit [3:0]             region;
	rand bit [USER_WIDTH-1:0]  user;
	rand bit [DATA_WIDTH-1:0]     data[];
	rand bit [(DATA_WIDTH/8)-1:0] strb[];
	bit [1:0] resp[];
	rand int unsigned addr_delay;
	rand int unsigned data_delay[];
	constraint c_valid_burst {
		burst inside {0, 1, 2};
	}
	constraint c_size_match {
		size == $clog2(DATA_WIDTH/8);
	}
	constraint c_len_reasonable {
		len inside {[0:15]};
	}
	constraint c_data_size {
		data.size() == len + 1;
		strb.size() == len + 1;
		data_delay.size() == len + 1;
	}
	constraint c_addr_aligned {
		addr[1:0] == 2'b00;
	}
	constraint c_timing {
		addr_delay inside {[0:5]};
		foreach(data_delay[i]) {
			data_delay[i] inside {[0:3]};
		}
	}
	`uvm_object_param_utils_begin(axi4_item#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH))
		`uvm_field_enum(axi4_trans_type_e, trans_type, UVM_DEFAULT)
		`uvm_field_int(id, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(addr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(len, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(size, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(burst, UVM_DEFAULT)
		`uvm_field_array_int(data, UVM_DEFAULT | UVM_HEX)
		`uvm_field_array_int(strb, UVM_DEFAULT | UVM_HEX)
		`uvm_field_array_int(resp, UVM_DEFAULT)
	`uvm_object_utils_end
	function new(string name = "axi4_item");
		super.new(name);
	endfunction
	function int get_total_bytes();
		return (len + 1) * (2 ** size);
	endfunction
endclass : axi4_item
