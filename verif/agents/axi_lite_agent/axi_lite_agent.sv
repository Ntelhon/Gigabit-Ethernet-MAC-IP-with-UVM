//==============================================================================
// Class: axi_lite_agent
// Description: UVM Agent for AXI4-Lite master interface
//
// Purpose:
//   Complete UVM agent for driving and monitoring AXI4-Lite transactions.
//   Used for programming control/status registers of the Ethernet MAC IP.
//
// Components:
//   - axi_lite_driver:    Drives read/write transactions
//   - axi_lite_monitor:   Monitors all bus activity
//   - axi_lite_sequencer: Manages transaction flow
//
// Modes:
//   - UVM_ACTIVE:  Driver, Monitor, and Sequencer active
//   - UVM_PASSIVE: Monitor only
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_lite_agent extends uvm_agent;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(axi_lite_agent)

    //==========================================================================
    // Agent Components
    //==========================================================================
    axi_lite_driver     driver;
    axi_lite_monitor    monitor;
    axi_lite_sequencer  sequencer;

    //==========================================================================
    // Analysis Port (passthrough from monitor)
    //==========================================================================
    uvm_analysis_port #(axi_lite_txn) txn_port;

    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual axi_lite_if vif;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_lite_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface
        if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not found for axi_lite_agent")
        end
        
        // Create analysis port
        txn_port = new("txn_port", this);
        
        // Always create monitor
        monitor = axi_lite_monitor::type_id::create("monitor", this);
        
        // Create driver and sequencer only in active mode
        if (is_active == UVM_ACTIVE) begin
            driver    = axi_lite_driver::type_id::create("driver", this);
            sequencer = axi_lite_sequencer::type_id::create("sequencer", this);
        end
        
        // Set virtual interfaces for sub-components
        uvm_config_db#(virtual axi_lite_if.mon)::set(this, "monitor", "vif", vif);
        
        if (is_active == UVM_ACTIVE) begin
            uvm_config_db#(virtual axi_lite_if.master_drv)::set(this, "driver", "vif", vif);
        end
        
    endfunction

    //==========================================================================
    // Connect Phase
    //==========================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect monitor's analysis port to agent's analysis port
        monitor.txn_port.connect(txn_port);
        
        // Connect driver to sequencer in active mode
        if (is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
        
    endfunction

    //==========================================================================
    // Report Phase
    //==========================================================================
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("AXI_AGENT", $sformatf("Agent mode: %s", 
                  is_active == UVM_ACTIVE ? "ACTIVE" : "PASSIVE"), UVM_LOW)
    endfunction

endclass : axi_lite_agent


//==============================================================================
// Class: axi_lite_agent_config
// Description: Configuration object for AXI-Lite agent
//==============================================================================

class axi_lite_agent_config extends uvm_object;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_object_utils(axi_lite_agent_config)

    //==========================================================================
    // Configuration Fields
    //==========================================================================
    
    // Active or passive mode
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    
    // Address width (default 32)
    int unsigned addr_width = 32;
    
    // Data width (default 32)
    int unsigned data_width = 32;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_lite_agent_config");
        super.new(name);
    endfunction

endclass : axi_lite_agent_config
