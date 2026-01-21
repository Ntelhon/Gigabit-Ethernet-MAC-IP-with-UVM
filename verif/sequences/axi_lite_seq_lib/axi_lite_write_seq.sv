//==============================================================================
// Sequence: axi_lite_write_seq
// Description: Single AXI-Lite write transaction
//==============================================================================

class axi_lite_write_seq extends uvm_sequence #(axi_lite_txn);

    `uvm_object_utils(axi_lite_write_seq)
    
    // Configuration
    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit [3:0]  strb;
    
    function new(string name = "axi_lite_write_seq");
        super.new(name);
        strb = 4'hF;  // Default: all bytes
    endfunction
    
    virtual task body();
        axi_lite_txn txn, rsp;
        
        txn = axi_lite_txn::type_id::create("wr_txn");
        txn.op = axi_lite_txn::AXI_WRITE;
        txn.addr = addr;
        txn.wdata = data;
        txn.wstrb = strb;
        
        start_item(txn);
        finish_item(txn);
        
        // Get the response from the driver (for write response checking)
        get_response(rsp);
        
        //`uvm_info("AXI_LITE_WR_SEQ", $sformatf("Write: addr=0x%08h data=0x%08h", addr, data), UVM_HIGH)
    endtask

endclass : axi_lite_write_seq
