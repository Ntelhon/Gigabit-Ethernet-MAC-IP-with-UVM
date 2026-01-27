// File: tb/sequences/lib/axi_lite_write_seq.sv
class axi_lite_write_seq extends axi_lite_base_seq;

  `uvm_object_utils(axi_lite_write_seq)

  rand bit [31:0] addr;
  rand bit [31:0] data;
  bit [31:0]      strb = 4'hF;  // All bytes enabled by default
  
  function new(string name = "axi_lite_write_seq");
    super.new(name);
  endfunction

  task body();
    axi_lite_item#(32,32) req;

    `uvm_info("AXI_LITE_WR_SEQ", $sformatf("Starting AXI Lite Write Sequence: addr=0x%0h, data=0x%0h", addr, data), UVM_LOW)
    
    req = axi_lite_item#(32,32)::type_id::create("req");
    start_item(req);
    req.trans_type = AXI_LITE_WRITE;
    req.addr = this.addr;
    req.data = this.data;
    req.strb = this.strb;
    finish_item(req);
    
    `uvm_info("AXI_LITE_WR", $sformatf("Write: addr=0x%0h, data=0x%0h", addr, data), UVM_MEDIUM)
  endtask

endclass : axi_lite_write_seq
