//==============================================================================
// Class: axi4_mem_monitor
// Description: AXI4 memory monitor
//
// Monitors AXI4 transactions and sends them to analysis port
//==============================================================================

class axi4_mem_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_mem_monitor)

    virtual axi4_mem_if vif;
    uvm_analysis_port #(axi4_mem_txn) ap;

    function new(string name = "axi4_mem_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual axi4_mem_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", "Virtual interface not found")
        end
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_write();
            monitor_read();
        join_none
    endtask

    // Monitor write transactions
    task monitor_write();
        axi4_mem_txn txn;
        bit [63:0] addr;
        bit [3:0] id;
        bit [7:0] len;
        int beat;

        forever begin
            @(posedge vif.clk);
            
            // Detect write address
            if (vif.awvalid && vif.awready) begin
                txn = axi4_mem_txn::type_id::create("txn");
                txn.op_type = axi4_mem_txn::AXI4_WRITE;
                txn.addr = vif.awaddr;
                txn.id = vif.awid;
                txn.len = vif.awlen;
                txn.size = vif.awsize;
                txn.burst = vif.awburst;
                
                txn.data = new[txn.len + 1];
                txn.strb = new[txn.len + 1];
                beat = 0;
                
                // Collect write data
                while (beat <= txn.len) begin
                    @(posedge vif.clk);
                    if (vif.wvalid && vif.wready) begin
                        txn.data[beat] = vif.wdata;
                        txn.strb[beat] = vif.wstrb;
                        beat++;
                    end
                end
                
                // Wait for write response
                while (!(vif.bvalid && vif.bready)) begin
                    @(posedge vif.clk);
                end
                txn.resp = vif.bresp;
                
                // Send to analysis port
                ap.write(txn);
                `uvm_info("AXI4_MON", $sformatf("Write: addr=0x%0h len=%0d", 
                          txn.addr, txn.len), UVM_HIGH)
            end
        end
    endtask

    // Monitor read transactions
    task monitor_read();
        axi4_mem_txn txn;
        int beat;

        forever begin
            @(posedge vif.clk);
            
            // Detect read address
            if (vif.arvalid && vif.arready) begin
                txn = axi4_mem_txn::type_id::create("txn");
                txn.op_type = axi4_mem_txn::AXI4_READ;
                txn.addr = vif.araddr;
                txn.id = vif.arid;
                txn.len = vif.arlen;
                txn.size = vif.arsize;
                txn.burst = vif.arburst;
                
                txn.data = new[txn.len + 1];
                beat = 0;
                
                // Collect read data
                while (beat <= txn.len) begin
                    @(posedge vif.clk);
                    if (vif.rvalid && vif.rready) begin
                        txn.data[beat] = vif.rdata;
                        if (vif.rlast) txn.resp = vif.rresp;
                        beat++;
                    end
                end
                
                // Send to analysis port
                ap.write(txn);
                `uvm_info("AXI4_MON", $sformatf("Read: addr=0x%0h len=%0d", 
                          txn.addr, txn.len), UVM_HIGH)
            end
        end
    endtask

endclass : axi4_mem_monitor
