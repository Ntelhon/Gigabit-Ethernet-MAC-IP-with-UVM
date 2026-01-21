//==============================================================================
// MAC Base Sequence - Common utilities for MAC sequences
//==============================================================================

`ifndef MAC_BASE_SEQ_SV
`define MAC_BASE_SEQ_SV

class mac_base_seq extends eth_base_seq;
    
    `uvm_object_utils(mac_base_seq)
    
    //--------------------------------------------------------------------------
    // Sequencer Handles (set by test before starting sequence)
    //--------------------------------------------------------------------------
    uvm_sequencer #(axi_lite_txn) axi_lite_sqr;
    uvm_sequencer #(gmii_frame) gmii_tx_sqr;
    uvm_sequencer #(axi_stream_txn) axis_tx_sqr;
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    bit auto_config = 1;  // Auto-configure MAC before test
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "mac_base_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // MAC Configuration
    //--------------------------------------------------------------------------
    // NOTE: Register access (write_reg, read_reg, poll_reg) should be done
    // via eth_base_test helper methods or eth_base_seq, not here.
    //--------------------------------------------------------------------------
    
    task configure_mac(
        bit enable_tx = 1,
        bit enable_rx = 1,
        bit loopback = 0,
        bit promiscuous = 1
    );
        bit [31:0] ctrl_reg = 0;
        
        `uvm_info("MAC_SEQ", "Configuring MAC...", UVM_MEDIUM)
        
        // Build control register
        if (enable_tx)    ctrl_reg[0] = 1;
        if (enable_rx)    ctrl_reg[1] = 1;
        if (loopback)     ctrl_reg[2] = 1;
        if (promiscuous)  ctrl_reg[3] = 1;
        
        // Write MAC control register (assuming offset 0x0000)
        write_reg(32'h0000, ctrl_reg);
        
        // Small delay for configuration to take effect
        #100ns;
        
        `uvm_info("MAC_SEQ", $sformatf("MAC configured: TX=%0d RX=%0d LB=%0d PROMISC=%0d", 
                  enable_tx, enable_rx, loopback, promiscuous), UVM_MEDIUM)
    endtask
    
    task reset_mac();
        `uvm_info("MAC_SEQ", "Resetting MAC...", UVM_MEDIUM)
        write_reg(32'h0000, 32'h8000_0000);  // Assuming bit 31 is reset
        #100ns;
        write_reg(32'h0000, 32'h0000_0000);
        #100ns;
        `uvm_info("MAC_SEQ", "MAC reset complete", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // High-Level Helper Methods
    //--------------------------------------------------------------------------
    
    task set_mac_address(bit [47:0] mac_addr);
        // Write MAC address to registers (assuming address 0x10/0x14)
        write_reg(ADDR_MAC_LO, mac_addr[31:0]);
        write_reg(ADDR_MAC_HI, {16'h0, mac_addr[47:32]});
        `uvm_info("MAC_SEQ", $sformatf("Set MAC address: %012h", mac_addr), UVM_MEDIUM)
    endtask
    
    task enable_mac(bit tx_en = 1, bit rx_en = 1);
        bit [31:0] ctrl = 0;
        if (tx_en) ctrl[MAC_CTRL_TX_EN_BIT] = 1;
        if (rx_en) ctrl[MAC_CTRL_RX_EN_BIT] = 1;
        write_reg(ADDR_CONTROL, ctrl);
        `uvm_info("MAC_SEQ", $sformatf("MAC enabled (TX=%0d RX=%0d)", tx_en, rx_en), UVM_MEDIUM)
    endtask
    
    task clear_interrupts(bit [31:0] mask = 32'hFFFF_FFFF);
        write_reg(ADDR_INT_STATUS, mask);  // Clear specified interrupts
        `uvm_info("MAC_SEQ", $sformatf("Cleared MAC interrupts with mask 0x%08h", mask), UVM_HIGH)
    endtask
    
    task get_rx_frame_count(output int count);
        bit [31:0] status;
        read_reg(ADDR_STATUS, status);
        count = status[15:0];  // Assuming lower 16 bits are RX frame count
        `uvm_info("MAC_SEQ", $sformatf("RX frame count: %0d", count), UVM_HIGH)
    endtask
    
    task send_frame(gmii_frame frame);
        // This should be called on GMII sequencer, not here
        // For now, just log a message
        `uvm_warning("MAC_SEQ", "send_frame called on AXI-Lite sequencer - should use GMII sequencer")
    endtask
    
endclass

`endif // MAC_BASE_SEQ_SV
