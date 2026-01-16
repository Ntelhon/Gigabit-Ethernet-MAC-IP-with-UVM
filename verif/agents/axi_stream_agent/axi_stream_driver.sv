//==============================================================================
// Class: axi_stream_driver
// Description: UVM Driver for AXI-Stream TX interface
//
// Purpose:
//   Drives Ethernet frames onto the AXI-Stream TX interface (master mode).
//   Converts axi_stream_txn objects into AXI-Stream protocol transactions.
//
// Features:
//   - Proper AXI-Stream handshaking (tvalid/tready)
//   - Frame boundary handling (tlast)
//   - SOF indication via tuser
//   - Configurable inter-frame gap
//   - Backpressure handling
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_stream_driver extends uvm_driver #(axi_stream_txn);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(axi_stream_driver)

    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual axi_stream_if vif;
    
    //==========================================================================
    // Configuration
    //==========================================================================
    
    // Operating mode: 1 = master (TX), 0 = slave (RX ready control)
    bit is_master = 1;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_stream_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual axi_stream_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not found for axi_stream_driver")
        end
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    task run_phase(uvm_phase phase);
        axi_stream_txn txn;
        
        // Initialize interface
        if (is_master) begin
            vif.tvalid <= 1'b0;
            vif.tdata  <= 8'h00;
            vif.tlast  <= 1'b0;
            vif.tuser  <= 1'b0;
        end else begin
            vif.tready <= 1'b0;
        end
        
        // Wait for reset
        @(posedge vif.aclk);
        while (!vif.aresetn) @(posedge vif.aclk);
        repeat (2) @(posedge vif.aclk);
        
        `uvm_info("AXIS_DRV", $sformatf("Driver started in %s mode", 
                  is_master ? "MASTER" : "SLAVE"), UVM_MEDIUM)
        
        // Main driver loop
        forever begin
            seq_item_port.get_next_item(txn);
            
            if (is_master) begin
                drive_frame(txn);
            end else begin
                handle_rx_ready(txn);
            end
            
            seq_item_port.item_done();
        end
    endtask

    //==========================================================================
    // Drive Frame (Master Mode - TX)
    //==========================================================================
    task drive_frame(axi_stream_txn txn);
        int byte_count;
        
        txn.start_time = $time;
        
        `uvm_info("AXIS_DRV", $sformatf("Driving frame: %0d bytes", txn.data.size()), UVM_MEDIUM)
        
        // Debug: Print first 20 bytes of frame
        for (int dbg = 0; dbg < 20 && dbg < txn.data.size(); dbg++) begin
            `uvm_info("AXIS_DRV", $sformatf("  Frame[%0d] = 0x%02h", dbg, txn.data[dbg]), UVM_HIGH)
        end
        
        // Drive each byte
        for (int i = 0; i < txn.data.size(); i++) begin
            // Drive data signals
            vif.tdata  <= txn.data[i];
            vif.tvalid <= 1'b1;
            vif.tuser  <= (i == 0) ? 1'b1 : 1'b0;  // SOF on first byte
            
            // tlast on last byte (unless inject_no_tlast)
            if (i == txn.data.size() - 1 && !txn.inject_no_tlast) begin
                vif.tlast <= 1'b1;
            end else begin
                vif.tlast <= 1'b0;
            end
            
            // Wait for clock and handshake
            @(posedge vif.aclk);
            
            // Wait for tready
            while (!vif.tready) begin
                @(posedge vif.aclk);
            end
            // Handshake complete for this byte
        end
        
        // Deassert valid immediately (without extra clock wait)
        vif.tvalid <= 1'b0;
        vif.tlast  <= 1'b0;
        vif.tuser  <= 1'b0;
        
        // Inter-frame gap - wait for first IFG cycle
        @(posedge vif.aclk);
        repeat (txn.ifg_cycles - 1) @(posedge vif.aclk);
        
        txn.end_time = $time;
        txn.transfer_complete = 1;
        
        `uvm_info("AXIS_DRV", $sformatf("Frame complete: %0d bytes in %0t", 
                  txn.data.size(), txn.end_time - txn.start_time), UVM_HIGH)
    endtask

    //==========================================================================
    // Handle RX Ready (Slave Mode)
    //==========================================================================
    task handle_rx_ready(axi_stream_txn txn);
        // For slave mode, just assert ready
        // Backpressure injection could be added here
        
        if (txn.inject_backpressure) begin
            // Deassert ready for some cycles
            vif.tready <= 1'b0;
            repeat (txn.backpressure_cycles) @(posedge vif.aclk);
        end
        
        // Assert ready
        vif.tready <= 1'b1;
        @(posedge vif.aclk);
    endtask

endclass : axi_stream_driver
