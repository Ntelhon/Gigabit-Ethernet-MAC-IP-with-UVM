//==============================================================================
// Class: mac_virtual_sequencer
// Description: Virtual sequencer for coordinating MAC verification
//
// Purpose:
//   Provides a central coordination point for running sequences across
//   multiple agents (GMII and AXI-Lite). Enables complex test scenarios
//   that require synchronized register programming and frame transmission.
//
// Responsibilities:
//   - Coordinate register programming via AXI-Lite
//   - Coordinate frame transmission via GMII
//   - Enable error injection scenarios
//   - No protocol logic (pure coordination)
//
// Sub-Sequencers:
//   - axi_sqr:  AXI-Lite sequencer for register access
//   - gmii_sqr: GMII sequencer for frame transmission
//
// Usage:
//   Virtual sequences access sub-sequencers via handles:
//     `p_sequencer.axi_sqr.start(...)
//     `p_sequencer.gmii_sqr.start(...)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_virtual_sequencer extends uvm_sequencer;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_virtual_sequencer)

    //==========================================================================
    // Sub-Sequencer Handles
    //==========================================================================
    
    // AXI-Lite sequencer for register access
    axi_lite_sequencer axi_sqr;
    
    // GMII sequencer for frame transmission (RX to MAC)
    gmii_sequencer gmii_sqr;
    
    // AXI-Stream sequencer for TX/RX data path
    axi_stream_sequencer axis_sqr;

    //==========================================================================
    // Configuration Handles
    //==========================================================================
    
    // MAC configuration (optional)
    // mac_env_config cfg;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Note: Sub-sequencer handles are set by the environment
        // during connect_phase, not created here
        
    endfunction

endclass : mac_virtual_sequencer


//==============================================================================
// Class: mac_virtual_sequence_base
// Description: Base class for virtual sequences
//
// Purpose:
//   Provides common functionality for virtual sequences that coordinate
//   across multiple agents.
//
// Features:
//   - Access to sub-sequencers via p_sequencer
//   - Common utility tasks for register access
//   - Common utility tasks for frame operations
//
//==============================================================================

class mac_virtual_sequence_base extends uvm_sequence;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_object_utils(mac_virtual_sequence_base)
    
    //==========================================================================
    // Declare p_sequencer for sub-sequencer access
    //==========================================================================
    `uvm_declare_p_sequencer(mac_virtual_sequencer)

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_virtual_sequence_base");
        super.new(name);
    endfunction

    //==========================================================================
    // Register Write Helper
    //==========================================================================
    task write_reg(bit [31:0] addr, bit [31:0] data);
        axi_lite_txn txn;
        
        txn = axi_lite_txn::type_id::create("wr_txn");
        txn.op    = axi_lite_txn::AXI_WRITE;
        txn.addr  = addr;
        txn.wdata = data;
        txn.wstrb = 4'hF;
        
        start_item(txn, -1, p_sequencer.axi_sqr);
        finish_item(txn);
        
        if (!txn.is_ok()) begin
            `uvm_error("VSEQ", $sformatf("Register write failed: addr=0x%08h", addr))
        end
    endtask

    //==========================================================================
    // Register Read Helper
    //==========================================================================
    task read_reg(bit [31:0] addr, output bit [31:0] data);
        axi_lite_txn txn;
        
        txn = axi_lite_txn::type_id::create("rd_txn");
        txn.op   = axi_lite_txn::AXI_READ;
        txn.addr = addr;
        
        start_item(txn, -1, p_sequencer.axi_sqr);
        finish_item(txn);
        
        data = txn.rdata;
        
        if (!txn.is_ok()) begin
            `uvm_error("VSEQ", $sformatf("Register read failed: addr=0x%08h", addr))
        end
    endtask

    //==========================================================================
    // Send Frame Helper
    //==========================================================================
    task send_frame(gmii_frame frame);
        start_item(frame, -1, p_sequencer.gmii_sqr);
        finish_item(frame);
    endtask

    //==========================================================================
    // MAC Register Addresses
    //==========================================================================
    localparam ADDR_MAC_LO      = 32'h00;
    localparam ADDR_MAC_HI      = 32'h04;
    localparam ADDR_CONTROL     = 32'h08;
    localparam ADDR_STATUS      = 32'h0C;
    localparam ADDR_INT_STATUS  = 32'h10;
    localparam ADDR_INT_MASK    = 32'h14;
    localparam ADDR_TX_FRAME    = 32'h18;
    localparam ADDR_RX_FRAME    = 32'h1C;
    localparam ADDR_RX_ERR      = 32'h20;
    localparam ADDR_VERSION     = 32'h24;

    //==========================================================================
    // Set MAC Address
    //==========================================================================
    task set_mac_address(bit [47:0] mac_addr);
        write_reg(ADDR_MAC_LO, mac_addr[31:0]);
        write_reg(ADDR_MAC_HI, {16'h0, mac_addr[47:32]});
        `uvm_info("VSEQ", $sformatf("MAC address set to %012h", mac_addr), UVM_MEDIUM)
    endtask

    //==========================================================================
    // Enable TX/RX
    //==========================================================================
    task enable_mac(bit tx_en, bit rx_en);
        bit [31:0] ctrl = {30'b0, rx_en, tx_en};
        write_reg(ADDR_CONTROL, ctrl);
        `uvm_info("VSEQ", $sformatf("MAC enabled: TX=%0b RX=%0b", tx_en, rx_en), UVM_MEDIUM)
    endtask

    //==========================================================================
    // Get TX Frame Count
    //==========================================================================
    task get_tx_frame_count(output bit [31:0] count);
        read_reg(ADDR_TX_FRAME, count);
    endtask

    //==========================================================================
    // Get RX Frame Count
    //==========================================================================
    task get_rx_frame_count(output bit [31:0] count);
        read_reg(ADDR_RX_FRAME, count);
    endtask

    //==========================================================================
    // Clear Interrupts
    //==========================================================================
    task clear_interrupts(bit [3:0] int_mask);
        write_reg(ADDR_INT_STATUS, {28'h0, int_mask});
    endtask

endclass : mac_virtual_sequence_base
