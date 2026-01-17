//==============================================================================
// Class: axi4_mem_driver
// Description: AXI4 memory slave driver (responds to DUT's AXI4 master)
//
// This driver acts as a memory slave, responding to read/write requests
//==============================================================================

class axi4_mem_driver extends uvm_driver #(axi4_mem_txn);
    `uvm_component_utils(axi4_mem_driver)

    virtual axi4_mem_if vif;

    // Internal memory model
    bit [7:0] mem [bit[63:0]];    // Associative array for sparse memory

    function new(string name = "axi4_mem_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_mem_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", "Virtual interface not found")
        end
    endfunction

    task run_phase(uvm_phase phase);
        fork
            drive_write();
            drive_read();
        join_none
    endtask

    // Handle write transactions
    task drive_write();
        bit [63:0] addr;
        bit [63:0] data;
        bit [7:0] strb;
        bit [3:0] id;
        int beat;

        forever begin
            @(posedge vif.clk);
            
            // Write address channel
            if (vif.awvalid && vif.awready) begin
                addr = vif.awaddr;
                id = vif.awid;
                beat = 0;
            end

            // Write data channel
            if (vif.wvalid && vif.wready) begin
                data = vif.wdata;
                strb = vif.wstrb;
                
                // Write to memory model
                for (int i = 0; i < 8; i++) begin
                    if (strb[i]) begin
                        mem[addr + beat*8 + i] = data[i*8 +: 8];
                    end
                end
                
                beat++;
                
                // Send write response on last beat
                if (vif.wlast) begin
                    @(posedge vif.clk);
                    vif.bvalid <= 1'b1;
                    vif.bid <= id;
                    vif.bresp <= 2'b00; // OKAY
                    wait(vif.bready);
                    @(posedge vif.clk);
                    vif.bvalid <= 1'b0;
                end
            end
        end
    endtask

    // Handle read transactions
    task drive_read();
        bit [63:0] addr;
        bit [63:0] data;
        bit [3:0] id;
        bit [7:0] len;
        int beat;

        forever begin
            @(posedge vif.clk);
            
            // Read address channel
            if (vif.arvalid && vif.arready) begin
                addr = vif.araddr;
                id = vif.arid;
                len = vif.arlen;
                
                // Send read data
                for (beat = 0; beat <= len; beat++) begin
                    @(posedge vif.clk);
                    
                    // Read from memory model
                    data = 64'h0;
                    for (int i = 0; i < 8; i++) begin
                        if (mem.exists(addr + beat*8 + i)) begin
                            data[i*8 +: 8] = mem[addr + beat*8 + i];
                        end
                    end
                    
                    vif.rvalid <= 1'b1;
                    vif.rid <= id;
                    vif.rdata <= data;
                    vif.rresp <= 2'b00; // OKAY
                    vif.rlast <= (beat == len);
                    
                    wait(vif.rready);
                    @(posedge vif.clk);
                    vif.rvalid <= 1'b0;
                end
            end
        end
    endtask

    // Initialize outputs
    task reset_phase(uvm_phase phase);
        vif.awready <= 1'b1;  // Always ready for address
        vif.wready  <= 1'b1;  // Always ready for data
        vif.bvalid  <= 1'b0;
        vif.arready <= 1'b1;  // Always ready for read address
        vif.rvalid  <= 1'b0;
    endtask

    // Helper function to preload memory
    function void load_mem(bit [63:0] addr, bit [7:0] data_queue[$]);
        foreach (data_queue[i]) begin
            mem[addr + i] = data_queue[i];
        end
    endfunction

    // Helper function to read memory
    function bit [7:0] read_mem(bit [63:0] addr);
        if (mem.exists(addr)) begin
            return mem[addr];
        end else begin
            return 8'h00;
        end
    endfunction

endclass : axi4_mem_driver
