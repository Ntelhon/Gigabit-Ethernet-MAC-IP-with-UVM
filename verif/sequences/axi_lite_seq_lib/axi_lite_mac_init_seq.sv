//==============================================================================
// Sequence: axi_lite_mac_init_seq
// Description: Single AXI-Lite write transaction
//==============================================================================

class axi_lite_mac_init_seq extends uvm_sequence #(axi_lite_txn);

    `uvm_object_utils(axi_lite_mac_init_seq)

    // Configuration
    bit [47:0] mac_addr = 48'h001122334455;
    bit tx_enable = 1;
    bit rx_enable = 1;

    function new(string name = "axi_lite_mac_init_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        axi_lite_txn txn, rsp;
        axi_lite_write_seq write_seq;

        // Set MAC address (low)
        write_seq = axi_lite_write_seq::type_id::create("write_seq");
        write_seq.addr = ADDR_MAC_LO;
        write_seq.data = mac_addr[31:0];
        write_seq.start(this.get_sequencer());

        // Set MAC address (high)
        write_seq = axi_lite_write_seq::type_id::create("wr_mac_hi");
        write_seq.addr = ADDR_MAC_HI;
        write_seq.data = {16'h0, mac_addr[47:32]};
        write_seq.start(this.get_sequencer());

        // Enable MAC TX and RX
        write_seq = axi_lite_write_seq::type_id::create("wr_ctrl");
        write_seq.addr = ADDR_CONTROL;
        write_seq.data = 32'h0000_0003;  // TX_EN | RX_EN
        write_seq.start(this.get_sequencer());

        `uvm_info("AXI_LITE_MAC_INIT_SEQ", $sformatf("MAC initialized: ADDR=0x%012h TX_EN=%0d RX_EN=%0d", 
            mac_addr, tx_enable, rx_enable), UVM_HIGH);

    endtask

endclass : axi_lite_mac_init_seq
