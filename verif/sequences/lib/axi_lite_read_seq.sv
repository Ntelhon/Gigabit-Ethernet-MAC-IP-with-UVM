// File: tb/sequences/lib/axi_lite_read_seq.sv
class axi_lite_read_seq extends axi_lite_base_seq;

  `uvm_object_utils(axi_lite_read_seq)

  rand bit [31:0] addr;
  bit [31:0]      read_data;  // Output
  
  function new(string name = "axi_lite_read_seq");
    super.new(name);
  endfunction

  task body();
    axi_lite_item#(32,32) req;
    
    req = axi_lite_item#(32,32)::type_id::create("req");
    start_item(req);
    req.trans_type = AXI_LITE_READ;
    req.addr = this.addr;
    finish_item(req);
    get_response(rsp);
    
    read_data = rsp.read_data;
    `uvm_info("AXI_LITE_RD", $sformatf("Read: addr=0x%0h, data=0x%0h", addr, read_data), UVM_MEDIUM)
  endtask

endclass : axi_lite_read_seq
