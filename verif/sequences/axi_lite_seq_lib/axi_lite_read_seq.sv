//==============================================================================
// Sequence: axi_lite_read_seq
// Description: Single AXI-Lite read transaction
//==============================================================================

class axi_lite_read_seq extends uvm_sequence #(axi_lite_txn);

    `uvm_object_utils(axi_lite_read_seq)
    
    // Configuration
    rand bit [31:0] addr;
    
    // Output
    bit [31:0] data;
    
    function new(string name = "axi_lite_read_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        axi_lite_txn txn, rsp;
        
        txn = axi_lite_txn::type_id::create("rd_txn");
        txn.op = axi_lite_txn::AXI_READ;
        txn.addr = addr;
        
        start_item(txn);
        finish_item(txn);
        
        // Get the response from the driver (contains the read data)
        get_response(rsp);
        
        // Extract read data from response
        data = rsp.rdata;
        
        //`uvm_info("AXI_LITE_RD_SEQ", $sformatf("Read: addr=0x%08h data=0x%08h", addr, data), UVM_HIGH)
    endtask

endclass : axi_lite_read_seq
