// File: tb/env/eth_controller/axi_lite_agent/axi_lite_item.sv
class axi_lite_item #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 32
) extends uvm_sequence_item;
  
  rand axi_lite_trans_type_e        trans_type;
  rand bit [ADDR_WIDTH-1:0]         addr;
  rand bit [DATA_WIDTH-1:0]         data;
  rand bit [(DATA_WIDTH/8)-1:0]     strb;
  rand bit [2:0]                    prot;
  
  // Response
  bit [1:0]                         resp;  // OKAY, EXOKAY, SLVERR, DECERR
  bit [DATA_WIDTH-1:0]              read_data;  // For read transactions
  
  // Timing
  rand int unsigned                 addr_delay;
  rand int unsigned                 data_delay;

  // Constraints
  constraint c_timing {
    addr_delay inside {[0:3]};
    data_delay inside {[0:3]};
  }
  
  constraint c_addr_aligned {
    addr[1:0] == 2'b00;  // Word-aligned
  }
  
  constraint c_strb_valid {
    strb != '0;  // At least one byte enabled
  }

  `uvm_object_param_utils_begin(axi_lite_item#(ADDR_WIDTH, DATA_WIDTH))
    `uvm_field_enum(axi_lite_trans_type_e, trans_type, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(data, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(strb, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(prot, UVM_DEFAULT)
    `uvm_field_int(resp, UVM_DEFAULT)
    `uvm_field_int(read_data, UVM_DEFAULT | UVM_HEX)
  `uvm_object_utils_end

  function new(string name = "axi_lite_item");
    super.new(name);
  endfunction

endclass : axi_lite_item
