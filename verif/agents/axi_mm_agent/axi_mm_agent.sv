//==============================================================================
// AXI4 Memory Agent
//==============================================================================

`ifndef AXI_MM_AGENT_SV
`define AXI_MM_AGENT_SV

class axi_mm_agent extends uvm_agent;
    
    `uvm_component_utils(axi_mm_agent)
    
    //--------------------------------------------------------------------------
    // Agent Components
    //--------------------------------------------------------------------------
    axi_mm_driver   driver;
    axi_mm_monitor  monitor;
    axi_mm_mem_model mem;
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    bit is_active = UVM_ACTIVE;
    
    //--------------------------------------------------------------------------
    // Analysis Ports (forwarded from monitor)
    //--------------------------------------------------------------------------
    uvm_analysis_port #(axi_mm_item) write_ap;
    uvm_analysis_port #(axi_mm_item) read_ap;
    
    //--------------------------------------------------------------------------
    // Virtual Interface
    //--------------------------------------------------------------------------
    virtual axi_mm_if vif;
    
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
        
        // Get configuration
        if (!uvm_config_db#(int)::get(this, "", "is_active", is_active))
            is_active = UVM_ACTIVE;
        
        // Get virtual interface
        if (!uvm_config_db#(virtual axi_mm_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not found")
        
        // Create memory model (shared between driver and external users)
        mem = axi_mm_mem_model::type_id::create("mem", this);
        
        // Set memory model in config DB for driver
        uvm_config_db#(axi_mm_mem_model)::set(this, "driver", "mem", mem);
        
        // Always create monitor
        monitor = axi_mm_monitor::type_id::create("monitor", this);
        uvm_config_db#(virtual axi_mm_if.MONITOR)::set(this, "monitor", "vif", vif.MONITOR);
        
        // Create driver if active
        if (is_active == UVM_ACTIVE) begin
            driver = axi_mm_driver::type_id::create("driver", this);
            uvm_config_db#(virtual axi_mm_if.SLAVE)::set(this, "driver", "vif", vif.SLAVE);
        end
        
        // Create analysis ports
        write_ap = new("write_ap", this);
        read_ap  = new("read_ap", this);
    endfunction
    
    //--------------------------------------------------------------------------
    // Connect Phase
    //--------------------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect monitor analysis ports to agent ports
        monitor.write_ap.connect(write_ap);
        monitor.read_ap.connect(read_ap);
        
        // Connect driver to memory model
        if (is_active == UVM_ACTIVE) begin
            driver.mem = mem;
        end
    endfunction
    
    //--------------------------------------------------------------------------
    // Memory Access Functions (for direct memory access by tests)
    //--------------------------------------------------------------------------
    
    // Write a block of data to memory
    function void write_memory(bit [63:0] addr, bit [7:0] data[$]);
        foreach (data[i]) begin
            mem.write_byte(addr + i, data[i]);
        end
    endfunction
    
    // Read a block of data from memory
    function void read_memory(bit [63:0] addr, int size, ref bit [7:0] data[$]);
        data.delete();
        for (int i = 0; i < size; i++) begin
            data.push_back(mem.read_byte(addr + i));
        end
    endfunction
    
    // Clear memory
    function void clear_memory();
        mem.clear();
    endfunction
    
    // Print memory region
    function void print_memory(bit [63:0] addr, int size);
        mem.print_region(addr, size);
    endfunction
    
    // Set error injection region
    function void set_error_region(bit [63:0] start_addr, bit [63:0] end_addr);
        mem.set_error_region(start_addr, end_addr);
    endfunction
    
    // Clear error injection
    function void clear_error_region();
        mem.clear_error_region();
    endfunction
    
endclass : axi_mm_agent

`endif // AXI_MM_AGENT_SV
