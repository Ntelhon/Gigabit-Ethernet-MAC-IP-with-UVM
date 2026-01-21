//==============================================================================
// Class: axi_lite_driver
// Description: UVM Driver for AXI4-Lite master interface
//
// Purpose:
//   Drives AXI4-Lite read and write transactions to the DUT's slave interface.
//   Implements correct handshake behavior for all five AXI channels.
//
// Features:
//   - Blocking read/write operations
//   - Proper AXI handshake protocol
//   - Uses clocking blocks for timing accuracy
//   - No hardcoded delays
//
// Channels Driven:
//   - AW (Write Address): awaddr, awprot, awvalid
//   - W  (Write Data):    wdata, wstrb, wvalid
//   - B  (Write Response): bready
//   - AR (Read Address):  araddr, arprot, arvalid
//   - R  (Read Data):     rready
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_lite_driver extends uvm_driver #(axi_lite_txn);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(axi_lite_driver)

    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual axi_lite_if.master_drv vif;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_lite_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual axi_lite_if.master_drv)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not found for axi_lite_driver")
        end
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    task run_phase(uvm_phase phase);
        axi_lite_txn txn;
        
        // Initialize signals
        reset_signals();
        
        // Wait for reset release
        wait_for_reset();
        
        forever begin
            // Get next transaction from sequencer
            seq_item_port.get_next_item(txn);
            
            // Record start time
            txn.start_time = $time;
            
            // Drive transaction
            if (txn.op == axi_lite_txn::AXI_WRITE) begin
                drive_write(txn);
            end else begin
                drive_read(txn);
            end
            
            // Record end time
            txn.end_time = $time;
            txn.completed = 1;
            
            `uvm_info("AXI_DRV", txn.convert2string(), UVM_HIGH)
            
            // Signal completion and send response back to sequencer
            // For reads, this allows sequences to get the read data via get_response()
            seq_item_port.item_done(txn);
        end
    endtask

    //==========================================================================
    // Reset all driven signals
    //==========================================================================
    task reset_signals();
        @(vif.drv_cb);
        // Write address channel
        vif.drv_cb.awaddr  <= 32'h0;
        vif.drv_cb.awprot  <= 3'b0;
        vif.drv_cb.awvalid <= 1'b0;
        // Write data channel
        vif.drv_cb.wdata   <= 32'h0;
        vif.drv_cb.wstrb   <= 4'h0;
        vif.drv_cb.wvalid  <= 1'b0;
        // Write response channel
        vif.drv_cb.bready  <= 1'b0;
        // Read address channel
        vif.drv_cb.araddr  <= 32'h0;
        vif.drv_cb.arprot  <= 3'b0;
        vif.drv_cb.arvalid <= 1'b0;
        // Read data channel
        vif.drv_cb.rready  <= 1'b0;
    endtask

    //==========================================================================
    // Wait for reset release
    //==========================================================================
    task wait_for_reset();
        @(posedge vif.aresetn);
        @(vif.drv_cb);
    endtask

    //==========================================================================
    // Drive Write Transaction
    // Drives AW and W channels in parallel, then waits for B response
    //==========================================================================
    task drive_write(axi_lite_txn txn);
        bit aw_done = 0;
        bit w_done  = 0;
        
        // Drive address and data channels simultaneously
        fork
            // Write Address Channel
            begin
                @(vif.drv_cb);
                vif.drv_cb.awaddr  <= txn.addr;
                vif.drv_cb.awprot  <= txn.prot;
                vif.drv_cb.awvalid <= 1'b1;
                
                // Wait for AWREADY
                do begin
                    @(vif.drv_cb);
                end while (!vif.drv_cb.awready);
                
                // Deassert valid
                vif.drv_cb.awvalid <= 1'b0;
                aw_done = 1;
            end
            
            // Write Data Channel
            begin
                @(vif.drv_cb);
                vif.drv_cb.wdata  <= txn.wdata;
                vif.drv_cb.wstrb  <= txn.wstrb;
                vif.drv_cb.wvalid <= 1'b1;
                
                // Wait for WREADY
                do begin
                    @(vif.drv_cb);
                end while (!vif.drv_cb.wready);
                
                // Deassert valid
                vif.drv_cb.wvalid <= 1'b0;
                w_done = 1;
            end
        join
        
        // Wait for Write Response
        @(vif.drv_cb);
        vif.drv_cb.bready <= 1'b1;
        
        // Wait for BVALID
        do begin
            @(vif.drv_cb);
        end while (!vif.drv_cb.bvalid);
        
        // Capture response
        txn.resp = axi_lite_txn::axi_resp_e'(vif.drv_cb.bresp);
        txn.error = !txn.is_ok();
        
        // Deassert ready
        @(vif.drv_cb);
        vif.drv_cb.bready <= 1'b0;
        
    endtask

    //==========================================================================
    // Drive Read Transaction
    // Drives AR channel, then waits for R response
    //==========================================================================
    task drive_read(axi_lite_txn txn);
        
        // Drive Read Address Channel
        @(vif.drv_cb);
        vif.drv_cb.araddr  <= txn.addr;
        vif.drv_cb.arprot  <= txn.prot;
        vif.drv_cb.arvalid <= 1'b1;
        vif.drv_cb.rready  <= 1'b1;
        
        // Wait for ARREADY
        do begin
            @(vif.drv_cb);
        end while (!vif.drv_cb.arready);
        
        // Deassert address valid
        vif.drv_cb.arvalid <= 1'b0;
        
        // Wait for RVALID
        do begin
            @(vif.drv_cb);
        end while (!vif.drv_cb.rvalid);
        
        // Capture response
        txn.rdata = vif.drv_cb.rdata;
        txn.resp  = axi_lite_txn::axi_resp_e'(vif.drv_cb.rresp);
        txn.error = !txn.is_ok();
        
        // Deassert ready
        @(vif.drv_cb);
        vif.drv_cb.rready <= 1'b0;
        
    endtask

endclass : axi_lite_driver
