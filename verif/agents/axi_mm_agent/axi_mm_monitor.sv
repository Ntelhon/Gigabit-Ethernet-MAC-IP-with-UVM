//==============================================================================
// AXI4 Memory Monitor
//==============================================================================

`ifndef AXI_MM_MONITOR_SV
`define AXI_MM_MONITOR_SV

class axi_mm_monitor extends uvm_monitor;
    
    `uvm_component_utils(axi_mm_monitor)
    
    //--------------------------------------------------------------------------
    // Virtual Interface
    //--------------------------------------------------------------------------
    virtual axi_mm_if vif;
    
    //--------------------------------------------------------------------------
    // Analysis Ports
    //--------------------------------------------------------------------------
    uvm_analysis_port #(axi_mm_item) write_ap;
    uvm_analysis_port #(axi_mm_item) read_ap;
    
    //--------------------------------------------------------------------------
    // Internal Tracking
    //--------------------------------------------------------------------------
    axi_mm_item aw_pending[bit [AXI_ID_WIDTH-1:0]][$];  // Write addr by ID
    axi_mm_item ar_pending[bit [AXI_ID_WIDTH-1:0]][$];  // Read addr by ID
    
    //--------------------------------------------------------------------------
    // Statistics
    //--------------------------------------------------------------------------
    int write_count;
    int read_count;
    int write_beats;
    int read_beats;
    int write_errors;
    int read_errors;
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    //--------------------------------------------------------------------------
    // Build Phase
    //--------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        write_ap = new("write_ap", this);
        read_ap  = new("read_ap", this);
        
        if (!uvm_config_db#(virtual axi_mm_if.monitor)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction
    
    //--------------------------------------------------------------------------
    // Reset Phase
    //--------------------------------------------------------------------------
    task reset_phase(uvm_phase phase);
        phase.raise_objection(this);
        reset_stats();
        phase.drop_objection(this);
    endtask
    
    function void reset_stats();
        write_count  = 0;
        read_count   = 0;
        write_beats  = 0;
        read_beats   = 0;
        write_errors = 0;
        read_errors  = 0;
        
        // Clear pending queues
        aw_pending.delete();
        ar_pending.delete();
    endfunction
    
    //--------------------------------------------------------------------------
    // Run Phase - Main Monitor Loop
    //--------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        @(posedge vif.aresetn);
        @(vif.mon_cb);
        
        fork
            monitor_aw_channel();
            monitor_w_channel();
            monitor_b_channel();
            monitor_ar_channel();
            monitor_r_channel();
        join_none
    endtask
    
    //--------------------------------------------------------------------------
    // AW Channel Monitor
    //--------------------------------------------------------------------------
    task monitor_aw_channel();
        axi_mm_item txn;
        
        forever begin
            @(vif.mon_cb);
            
            if (!vif.aresetn) begin
                aw_pending.delete();
                continue;
            end
            
            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                txn = axi_mm_item::type_id::create("aw_mon_txn");
                txn.op    = axi_mm_item::AXI_WRITE;
                txn.addr  = vif.mon_cb.awaddr;
                txn.len   = vif.mon_cb.awlen;
                txn.size  = vif.mon_cb.awsize;
                txn.burst = vif.mon_cb.awburst;
                txn.id    = vif.mon_cb.awid;
                txn.data  = {};
                txn.strb  = {};
                
                aw_pending[txn.id].push_back(txn);
                
                `uvm_info("AXI_MON", $sformatf("AW: addr=0x%h len=%0d id=%0d", 
                    txn.addr, txn.len, txn.id), UVM_HIGH)
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // W Channel Monitor
    //--------------------------------------------------------------------------
    task monitor_w_channel();
        bit [AXI_ID_WIDTH-1:0] current_id = 0;
        bit found;
        
        forever begin
            @(vif.mon_cb);
            
            if (!vif.aresetn) continue;
            
            if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
                // Find matching AW transaction (in-order within same ID)
                found = 0;
                foreach (aw_pending[id]) begin
                    if (aw_pending[id].size() > 0) begin
                        current_id = id;
                        found = 1;
                        break;
                    end
                end
                
                if (found && aw_pending[current_id].size() > 0) begin
                    aw_pending[current_id][0].data.push_back(vif.mon_cb.wdata);
                    aw_pending[current_id][0].strb.push_back(vif.mon_cb.wstrb);
                    write_beats++;
                    
                    `uvm_info("AXI_MON", $sformatf("W: data=0x%h strb=0x%h last=%0d", 
                        vif.mon_cb.wdata, vif.mon_cb.wstrb, vif.mon_cb.wlast), UVM_HIGH)
                end
                else begin
                    `uvm_warning("AXI_MON", "W data without matching AW")
                end
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // B Channel Monitor
    //--------------------------------------------------------------------------
    task monitor_b_channel();
        axi_mm_item txn;
        bit [AXI_ID_WIDTH-1:0] resp_id;
        
        forever begin
            @(vif.mon_cb);
            
            if (!vif.aresetn) continue;
            
            if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
                resp_id = vif.mon_cb.bid;
                
                if (aw_pending[resp_id].size() > 0) begin
                    txn = aw_pending[resp_id].pop_front();
                    txn.resp = vif.mon_cb.bresp;
                    
                    write_count++;
                    if (txn.resp != 2'b00) write_errors++;
                    
                    `uvm_info("AXI_MON", $sformatf("B: id=%0d resp=%0d", 
                        resp_id, txn.resp), UVM_HIGH)
                    
                    // Broadcast complete write transaction
                    write_ap.write(txn);
                end
                else begin
                    `uvm_warning("AXI_MON", $sformatf("B response without matching AW: id=%0d", resp_id))
                end
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // AR Channel Monitor
    //--------------------------------------------------------------------------
    task monitor_ar_channel();
        axi_mm_item txn;
        
        forever begin
            @(vif.mon_cb);
            
            if (!vif.aresetn) begin
                ar_pending.delete();
                continue;
            end
            
            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                txn = axi_mm_item::type_id::create("ar_mon_txn");
                txn.op    = axi_mm_item::AXI_READ;
                txn.addr  = vif.mon_cb.araddr;
                txn.len   = vif.mon_cb.arlen;
                txn.size  = vif.mon_cb.arsize;
                txn.burst = vif.mon_cb.arburst;
                txn.id    = vif.mon_cb.arid;
                txn.data  = {};
                
                ar_pending[txn.id].push_back(txn);
                
                `uvm_info("AXI_MON", $sformatf("AR: addr=0x%h len=%0d id=%0d", 
                    txn.addr, txn.len, txn.id), UVM_HIGH)
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // R Channel Monitor
    //--------------------------------------------------------------------------
    task monitor_r_channel();
        axi_mm_item txn;
        bit [AXI_ID_WIDTH-1:0] resp_id;
        
        forever begin
            @(vif.mon_cb);
            
            if (!vif.aresetn) continue;
            
            if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
                resp_id = vif.mon_cb.rid;
                
                if (ar_pending[resp_id].size() > 0) begin
                    ar_pending[resp_id][0].data.push_back(vif.mon_cb.rdata);
                    read_beats++;
                    
                    `uvm_info("AXI_MON", $sformatf("R: id=%0d data=0x%h last=%0d", 
                        resp_id, vif.mon_cb.rdata, vif.mon_cb.rlast), UVM_HIGH)
                    
                    // Check for last beat
                    if (vif.mon_cb.rlast) begin
                        txn = ar_pending[resp_id].pop_front();
                        txn.resp = vif.mon_cb.rresp;
                        
                        read_count++;
                        if (txn.resp != 2'b00) read_errors++;
                        
                        // Broadcast complete read transaction
                        read_ap.write(txn);
                    end
                end
                else begin
                    `uvm_warning("AXI_MON", $sformatf("R data without matching AR: id=%0d", resp_id))
                end
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Report Phase
    //--------------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        `uvm_info("AXI_MON", $sformatf(
            "\n===== AXI-MM Monitor Statistics =====\n" +
            "  Write Transactions: %0d\n" +
            "  Write Data Beats:   %0d\n" +
            "  Write Errors:       %0d\n" +
            "  Read Transactions:  %0d\n" +
            "  Read Data Beats:    %0d\n" +
            "  Read Errors:        %0d\n" +
            "=====================================",
            write_count, write_beats, write_errors,
            read_count, read_beats, read_errors), UVM_MEDIUM)
    endfunction
    
endclass : axi_mm_monitor

`endif // AXI_MM_MONITOR_SV
