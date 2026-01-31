// File: tb/sequences/lib/axi_lite_write_seq.sv
class axi_lite_write_seq extends axi_lite_base_seq;

  `uvm_object_utils(axi_lite_write_seq)

  rand bit [AXI_LITE_ADDR_WIDTH-1:0] addr;
  rand bit [AXI_LITE_DATA_WIDTH-1:0] data;
  bit [AXI_LITE_DATA_WIDTH/8-1:0]    strb = {AXI_LITE_DATA_WIDTH/8{1'b1}};  // All bytes enabled by default

  function new(string name = "axi_lite_write_seq");
    super.new(name);
  endfunction

  task body();
    axi_lite_item#(`AXI_LITE_PARAMS) req;

    req = axi_lite_item#(`AXI_LITE_PARAMS)::type_id::create("req");
    start_item(req);
    req.trans_type = AXI_LITE_WRITE;
    req.addr = this.addr;
    req.addr_delay = 1;
    req.data_delay = 2;
    req.data = this.data;
    req.strb = this.strb;
    finish_item(req);
    
    `uvm_info("AXI_LITE_WR", $sformatf("Write: addr=0x%0h, data=0x%0h", addr, data), UVM_MEDIUM)
  endtask

endclass : axi_lite_write_seq
