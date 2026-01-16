//==============================================================================
// Class: axi_lite_monitor
// Description: UVM Monitor for AXI4-Lite transactions
//
// Purpose:
//   Passively observes all AXI4-Lite transactions on the bus.
//   Reconstructs complete transactions and sends them to the scoreboard
//   via analysis port.
//
// Monitored Signals:
//   - All five AXI4-Lite channels (AW, W, B, AR, R)
//
// Features:
//   - Non-intrusive monitoring
//   - Transaction reconstruction
//   - Analysis port for scoreboard integration
//   - Supports concurrent read/write monitoring
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_lite_monitor extends uvm_monitor;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(axi_lite_monitor)

    //==========================================================================
    // Analysis Port
    //==========================================================================
    uvm_analysis_port #(axi_lite_txn) txn_port;

    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual axi_lite_if.mon vif;

    //==========================================================================
    // Internal Queues for Transaction Reconstruction
    //==========================================================================
    
    // Pending write address transactions
    bit [31:0] pending_awaddr[$];
    bit [2:0]  pending_awprot[$];
    time       pending_aw_time[$];
    
    // Pending write data transactions
    bit [31:0] pending_wdata[$];
    bit [3:0]  pending_wstrb[$];
    
    // Pending read address transactions
    bit [31:0] pending_araddr[$];
    bit [2:0]  pending_arprot[$];
    time       pending_ar_time[$];

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_lite_monitor", uvm_component parent = null);
        super.new(name, parent);
        txn_port = new("txn_port", this);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual axi_lite_if.mon)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not found for axi_lite_monitor")
        end
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    task run_phase(uvm_phase phase);
        
        // Wait for reset release
        @(posedge vif.aresetn);
        @(vif.mon_cb);
        
        // Monitor all channels concurrently
        fork
            monitor_aw_channel();
            monitor_w_channel();
            monitor_b_channel();
            monitor_ar_channel();
            monitor_r_channel();
        join
        
    endtask

    //==========================================================================
    // Monitor Write Address Channel
    //==========================================================================
    task monitor_aw_channel();
        forever begin
            @(vif.mon_cb);
            
            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                pending_awaddr.push_back(vif.mon_cb.awaddr);
                pending_awprot.push_back(vif.mon_cb.awprot);
                pending_aw_time.push_back($time);
                
                `uvm_info("AXI_MON", $sformatf("AW: addr=0x%08h", vif.mon_cb.awaddr), UVM_HIGH)
            end
        end
    endtask

    //==========================================================================
    // Monitor Write Data Channel
    //==========================================================================
    task monitor_w_channel();
        forever begin
            @(vif.mon_cb);
            
            if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
                pending_wdata.push_back(vif.mon_cb.wdata);
                pending_wstrb.push_back(vif.mon_cb.wstrb);
                
                `uvm_info("AXI_MON", $sformatf("W: data=0x%08h strb=0x%01h", 
                          vif.mon_cb.wdata, vif.mon_cb.wstrb), UVM_HIGH)
            end
        end
    endtask

    //==========================================================================
    // Monitor Write Response Channel
    //==========================================================================
    task monitor_b_channel();
        axi_lite_txn txn;
        
        forever begin
            @(vif.mon_cb);
            
            if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
                // Create write transaction
                txn = axi_lite_txn::type_id::create("mon_write_txn");
                txn.op = axi_lite_txn::AXI_WRITE;
                
                // Get address from pending queue
                if (pending_awaddr.size() > 0) begin
                    txn.addr = pending_awaddr.pop_front();
                    txn.prot = pending_awprot.pop_front();
                    txn.start_time = pending_aw_time.pop_front();
                end else begin
                    `uvm_warning("AXI_MON", "B response without pending AW")
                end
                
                // Get data from pending queue
                if (pending_wdata.size() > 0) begin
                    txn.wdata = pending_wdata.pop_front();
                    txn.wstrb = pending_wstrb.pop_front();
                end else begin
                    `uvm_warning("AXI_MON", "B response without pending W")
                end
                
                // Capture response
                txn.resp = axi_lite_txn::axi_resp_e'(vif.mon_cb.bresp);
                txn.end_time = $time;
                txn.completed = 1;
                txn.error = !txn.is_ok();
                
                `uvm_info("AXI_MON", $sformatf("WRITE complete: %s", txn.convert2string()), UVM_MEDIUM)
                
                // Send to analysis port
                txn_port.write(txn);
            end
        end
    endtask

    //==========================================================================
    // Monitor Read Address Channel
    //==========================================================================
    task monitor_ar_channel();
        forever begin
            @(vif.mon_cb);
            
            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                pending_araddr.push_back(vif.mon_cb.araddr);
                pending_arprot.push_back(vif.mon_cb.arprot);
                pending_ar_time.push_back($time);
                
                `uvm_info("AXI_MON", $sformatf("AR: addr=0x%08h", vif.mon_cb.araddr), UVM_HIGH)
            end
        end
    endtask

    //==========================================================================
    // Monitor Read Data Channel
    //==========================================================================
    task monitor_r_channel();
        axi_lite_txn txn;
        
        forever begin
            @(vif.mon_cb);
            
            if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
                // Create read transaction
                txn = axi_lite_txn::type_id::create("mon_read_txn");
                txn.op = axi_lite_txn::AXI_READ;
                
                // Get address from pending queue
                if (pending_araddr.size() > 0) begin
                    txn.addr = pending_araddr.pop_front();
                    txn.prot = pending_arprot.pop_front();
                    txn.start_time = pending_ar_time.pop_front();
                end else begin
                    `uvm_warning("AXI_MON", "R response without pending AR")
                end
                
                // Capture response
                txn.rdata = vif.mon_cb.rdata;
                txn.resp  = axi_lite_txn::axi_resp_e'(vif.mon_cb.rresp);
                txn.end_time = $time;
                txn.completed = 1;
                txn.error = !txn.is_ok();
                
                `uvm_info("AXI_MON", $sformatf("READ complete: %s", txn.convert2string()), UVM_MEDIUM)
                
                // Send to analysis port
                txn_port.write(txn);
            end
        end
    endtask

endclass : axi_lite_monitor
