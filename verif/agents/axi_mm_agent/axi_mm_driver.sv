//==============================================================================
// AXI4 Memory Slave Driver
//==============================================================================

`ifndef AXI_MM_DRIVER_SV
`define AXI_MM_DRIVER_SV

class axi_mm_driver extends uvm_driver #(axi_mm_item);
    
    `uvm_component_utils(axi_mm_driver)
    
    //--------------------------------------------------------------------------
    // Virtual Interface
    //--------------------------------------------------------------------------
    virtual axi_mm_if vif;
    
    //--------------------------------------------------------------------------
    // Memory Model Handle
    //--------------------------------------------------------------------------
    axi_mm_mem_model mem;
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int min_addr_ready_delay = 0;
    int max_addr_ready_delay = 3;
    int min_data_ready_delay = 0;
    int max_data_ready_delay = 3;
    int min_resp_delay = 0;
    int max_resp_delay = 5;
    
    //--------------------------------------------------------------------------
    // Internal Queues for Outstanding Transactions
    //--------------------------------------------------------------------------
    typedef struct {
        axi_mm_item txn;
        int beats_received;
    } write_txn_t;
    
    axi_mm_item     rd_addr_queue[$];
    write_txn_t     wr_data_queue[$];
    axi_mm_item     wr_resp_queue[$];
    
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
        if (!uvm_config_db#(virtual axi_mm_if.slave)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not found")
        
        // Create or get memory model
        if (!uvm_config_db#(axi_mm_mem_model)::get(this, "", "mem", mem)) begin
            mem = axi_mm_mem_model::type_id::create("mem");
            uvm_config_db#(axi_mm_mem_model)::set(this, "", "mem", mem);
        end
    endfunction
    
    //--------------------------------------------------------------------------
    // Reset Phase
    //--------------------------------------------------------------------------
    task reset_phase(uvm_phase phase);
        phase.raise_objection(this);
        reset_signals();
        phase.drop_objection(this);
    endtask
    
    task reset_signals();
        // De-assert all ready signals
        vif.slave_cb.awready <= 1'b0;
        vif.slave_cb.wready  <= 1'b0;
        vif.slave_cb.arready <= 1'b0;
        
        // De-assert all valid signals  
        vif.slave_cb.bvalid  <= 1'b0;
        vif.slave_cb.rvalid  <= 1'b0;
        
        // Clear response data
        vif.slave_cb.bid     <= '0;
        vif.slave_cb.bresp   <= '0;
        vif.slave_cb.rid     <= '0;
        vif.slave_cb.rdata   <= '0;
        vif.slave_cb.rresp   <= '0;
        vif.slave_cb.rlast   <= '0;
        
        // Clear queues
        rd_addr_queue.delete();
        wr_data_queue.delete();
        wr_resp_queue.delete();
    endtask
    
    //--------------------------------------------------------------------------
    // Run Phase - Main Driver Loop
    //--------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        // Wait for reset de-assertion
        @(posedge vif.aresetn);
        @(vif.slave_cb);
        
        fork
            drive_aw_channel();
            drive_w_channel();
            drive_b_channel();
            drive_ar_channel();
            drive_r_channel();
        join_none
    endtask
    
    //--------------------------------------------------------------------------
    // AW Channel - Write Address
    //--------------------------------------------------------------------------
    task drive_aw_channel();
        axi_mm_item txn;
        write_txn_t wr_txn;
        int delay;
        
        forever begin
            @(vif.slave_cb);
            
            if (!vif.aresetn) begin
                vif.slave_cb.awready <= 1'b0;
                continue;
            end
            
            // Wait for valid
            if (vif.slave_cb.awvalid) begin
                // Random delay before ready
                delay = $urandom_range(min_addr_ready_delay, max_addr_ready_delay);
                repeat (delay) @(vif.slave_cb);
                
                // Assert ready
                vif.slave_cb.awready <= 1'b1;
                @(vif.slave_cb);
                
                // Capture transaction
                txn = axi_mm_item::type_id::create("aw_txn");
                txn.op    = axi_mm_item::AXI_WRITE;
                txn.addr  = vif.slave_cb.awaddr;
                txn.len   = vif.slave_cb.awlen;
                txn.size  = vif.slave_cb.awsize;
                txn.burst = vif.slave_cb.awburst;
                txn.id    = vif.slave_cb.awid;
                
                // Initialize data queues
                txn.data = {};
                txn.strb = {};
                
                // Add to write data queue
                wr_txn.txn = txn;
                wr_txn.beats_received = 0;
                wr_data_queue.push_back(wr_txn);
                
                `uvm_info("AXI_DRV", $sformatf("AW: addr=0x%h len=%0d id=%0d", 
                    txn.addr, txn.len, txn.id), UVM_HIGH)
                
                vif.slave_cb.awready <= 1'b0;
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // W Channel - Write Data
    //--------------------------------------------------------------------------
    task drive_w_channel();
        int delay;
        int idx;
        
        forever begin
            @(vif.slave_cb);
            
            if (!vif.aresetn) begin
                vif.slave_cb.wready <= 1'b0;
                continue;
            end
            
            // Wait for valid
            if (vif.slave_cb.wvalid && wr_data_queue.size() > 0) begin
                // Random delay before ready
                delay = $urandom_range(min_data_ready_delay, max_data_ready_delay);
                repeat (delay) @(vif.slave_cb);
                
                // Assert ready
                vif.slave_cb.wready <= 1'b1;
                @(vif.slave_cb);
                
                // Capture data beat (use first waiting transaction)
                idx = 0;
                wr_data_queue[idx].txn.data.push_back(vif.slave_cb.wdata);
                wr_data_queue[idx].txn.strb.push_back(vif.slave_cb.wstrb);
                wr_data_queue[idx].beats_received++;
                
                `uvm_info("AXI_DRV", $sformatf("W: data=0x%h strb=0x%h last=%0d", 
                    vif.slave_cb.wdata, vif.slave_cb.wstrb, vif.slave_cb.wlast), UVM_HIGH)
                
                // Check if transaction complete
                if (vif.slave_cb.wlast) begin
                    // Process write and queue response
                    wr_data_queue[idx].txn.resp = mem.process_write(wr_data_queue[idx].txn);
                    wr_resp_queue.push_back(wr_data_queue[idx].txn);
                    wr_data_queue.delete(idx);
                end
                
                vif.slave_cb.wready <= 1'b0;
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // B Channel - Write Response
    //--------------------------------------------------------------------------
    task drive_b_channel();
        axi_mm_item txn;
        int delay;
        
        forever begin
            @(vif.slave_cb);
            
            if (!vif.aresetn) begin
                vif.slave_cb.bvalid <= 1'b0;
                continue;
            end
            
            // Check for pending responses
            // Note: Read bvalid directly from interface, not through clocking block
            if (wr_resp_queue.size() > 0 && !vif.bvalid) begin
                txn = wr_resp_queue.pop_front();
                
                // Random delay before response
                delay = $urandom_range(min_resp_delay, max_resp_delay);
                repeat (delay) @(vif.slave_cb);
                
                // Drive response
                vif.slave_cb.bid   <= txn.id;
                vif.slave_cb.bresp <= txn.resp;
                vif.slave_cb.bvalid <= 1'b1;
                
                `uvm_info("AXI_DRV", $sformatf("B: id=%0d resp=%0d", 
                    txn.id, txn.resp), UVM_HIGH)
                
                // Wait for ready
                do @(vif.slave_cb); while (!vif.slave_cb.bready);
                
                vif.slave_cb.bvalid <= 1'b0;
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // AR Channel - Read Address
    //--------------------------------------------------------------------------
    task drive_ar_channel();
        axi_mm_item txn;
        int delay;
        
        forever begin
            @(vif.slave_cb);
            
            if (!vif.aresetn) begin
                vif.slave_cb.arready <= 1'b0;
                continue;
            end
            
            // Wait for valid
            if (vif.slave_cb.arvalid) begin
                // Random delay before ready
                delay = $urandom_range(min_addr_ready_delay, max_addr_ready_delay);
                repeat (delay) @(vif.slave_cb);
                
                // Assert ready
                vif.slave_cb.arready <= 1'b1;
                @(vif.slave_cb);
                
                // Capture transaction
                txn = axi_mm_item::type_id::create("ar_txn");
                txn.op    = axi_mm_item::AXI_READ;
                txn.addr  = vif.slave_cb.araddr;
                txn.len   = vif.slave_cb.arlen;
                txn.size  = vif.slave_cb.arsize;
                txn.burst = vif.slave_cb.arburst;
                txn.id    = vif.slave_cb.arid;
                
                // Process read from memory
                txn.resp = mem.process_read(txn);
                
                // Queue for R channel
                rd_addr_queue.push_back(txn);
                
                `uvm_info("AXI_DRV", $sformatf("AR: addr=0x%h len=%0d id=%0d", 
                    txn.addr, txn.len, txn.id), UVM_HIGH)
                
                vif.slave_cb.arready <= 1'b0;
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // R Channel - Read Data
    //--------------------------------------------------------------------------
    task drive_r_channel();
        axi_mm_item txn;
        int delay;
        int beat;
        
        forever begin
            @(vif.slave_cb);
            
            if (!vif.aresetn) begin
                vif.slave_cb.rvalid <= 1'b0;
                continue;
            end
            
            // Check for pending read responses
            // Note: Read rvalid directly from interface, not through clocking block
            if (rd_addr_queue.size() > 0 && !vif.rvalid) begin
                txn = rd_addr_queue.pop_front();
                
                // Send all beats
                for (beat = 0; beat <= txn.len; beat++) begin
                    // Random delay before data
                    delay = $urandom_range(min_resp_delay, max_resp_delay);
                    repeat (delay) @(vif.slave_cb);
                    
                    // Drive data
                    vif.slave_cb.rid   <= txn.id;
                    vif.slave_cb.rdata <= txn.data[beat];
                    vif.slave_cb.rresp <= txn.resp;
                    vif.slave_cb.rlast <= (beat == txn.len);
                    vif.slave_cb.rvalid <= 1'b1;
                    
                    `uvm_info("AXI_DRV", $sformatf("R: id=%0d data=0x%h last=%0d", 
                        txn.id, txn.data[beat], (beat == txn.len)), UVM_HIGH)
                    
                    // Wait for ready
                    do @(vif.slave_cb); while (!vif.slave_cb.rready);
                    
                    vif.slave_cb.rvalid <= 1'b0;
                end
            end
        end
    endtask
    
endclass : axi_mm_driver

`endif // AXI_MM_DRIVER_SV
