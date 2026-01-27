// File: tb/sequences/lib/axi_lite_read_seq.sv
class axi_lite_read_seq extends axi_lite_base_seq;

  `uvm_object_utils(axi_lite_read_seq)

  rand bit [AXI_LITE_ADDR_WIDTH-1:0] addr;
  bit      [AXI_LITE_DATA_WIDTH-1:0] read_data;  // Output

  function new(string name = "axi_lite_read_seq");
    super.new(name);
  endfunction

  task body();
    axi_lite_item#(AXI_LITE_ADDR_WIDTH,AXI_LITE_DATA_WIDTH) req;

    req = axi_lite_item#(AXI_LITE_ADDR_WIDTH,AXI_LITE_DATA_WIDTH)::type_id::create("req");
    start_item(req);
    req.trans_type = AXI_LITE_READ;
    req.addr = this.addr;
    finish_item(req);
    get_response(rsp);
    
    if(rsp.resp != 2'b00) begin
      `uvm_error("AXI_LITE_RD", $sformatf("Read transaction failed: addr=0x%0h, resp=0x%0h", addr, rsp.resp))
    end
    
    read_data = rsp.read_data;
    `uvm_info("AXI_LITE_RD", $sformatf("Read: addr=0x%0h, data=0x%0h", addr, read_data), UVM_MEDIUM)
  endtask

endclass : axi_lite_read_seq
