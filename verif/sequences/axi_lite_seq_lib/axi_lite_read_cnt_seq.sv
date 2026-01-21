//==============================================================================
// Sequence: axi_lite_read_cnt_seq
// Description: AXI-Lite read transaction to read status registers
//==============================================================================

class axi_lite_read_cnt_seq extends uvm_sequence #(axi_lite_txn);

    `uvm_object_utils(axi_lite_read_cnt_seq)
    
    // Output
    bit [31:0] mac_tx_frame_cnt;
    bit [31:0] mac_rx_frame_cnt;
    bit [31:0] mac_rx_error_cnt;
    
    function new(string name = "axi_lite_read_cnt_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        axi_lite_txn txn, rsp;
        
        txn = axi_lite_txn::type_id::create("rd_txn");
        txn.op = axi_lite_txn::AXI_READ;

        // Read TX frame count
        txn.addr = ADDR_TX_CNT;
        start_item(txn);
        finish_item(txn);
        get_response(rsp);
        mac_tx_frame_cnt = rsp.rdata;

        // Read RX frame count
        txn.addr = ADDR_RX_CNT;
        start_item(txn);
        finish_item(txn);
        get_response(rsp);
        mac_rx_frame_cnt = rsp.rdata;

        // Read RX error count
        txn.addr = ADDR_RX_ERR;
        start_item(txn);
        finish_item(txn);
        get_response(rsp);
        mac_rx_error_cnt = rsp.rdata;

        `uvm_info("SEQ", $sformatf("Read MAC Counters - TX: %0d, RX: %0d, RX Errors: %0d",
                    mac_tx_frame_cnt, mac_rx_frame_cnt, mac_rx_error_cnt), UVM_LOW)
    endtask

endclass : axi_lite_read_cnt_seq
