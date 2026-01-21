//==============================================================================
// Sequence: axi_lite_pool_seq
// Description: Single AXI-Lite pool transaction
//==============================================================================

class axi_lite_pool_seq extends uvm_sequence #(axi_lite_txn);

    `uvm_object_utils(axi_lite_pool_seq)
    
    // Configuration
    rand bit [31:0] addr;
    
    bit [31:0] mask;
    bit [31:0] expected;
    int timeout_cycles = 1000;

    // Output
    bit [31:0] data;
    
    function new(string name = "axi_lite_pool_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        axi_lite_txn txn, rsp;
        int count = 0;
        
        forever begin

            txn = axi_lite_txn::type_id::create("rd_txn");
            txn.op = axi_lite_txn::AXI_READ;
            txn.addr = addr;
            start_item(txn);
            finish_item(txn);
            get_response(rsp);
            data = rsp.rdata;

            if ((data & mask) == (expected & mask)) begin
                `uvm_info("POOL_SEQ", $sformatf("Poll success: addr=0x%08h data=0x%08h (expected mask 0x%08h)", addr, data, expected & mask), UVM_MEDIUM)
                return;
            end
            
            count++;
            if (count >= timeout_cycles) begin
                `uvm_error("POOL_SEQ", $sformatf("Poll timeout: addr=0x%08h data=0x%08h expected=0x%08h mask=0x%08h", addr, data, expected, mask))
                return;
            end
            
            #10ns;  // Small delay between polls
        end
    endtask

endclass : axi_lite_pool_seq
