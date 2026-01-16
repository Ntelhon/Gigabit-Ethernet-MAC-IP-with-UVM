//==============================================================================
// Class: axi_stream_agent
// Description: UVM Agent for AXI-Stream interface
//
// Purpose:
//   Complete UVM agent containing driver, monitor, and sequencer for
//   AXI-Stream TX/RX interfaces.
//
// Features:
//   - Configurable as active (driver + monitor) or passive (monitor only)
//   - Supports both TX (master) and RX (slave) modes
//   - Analysis ports for TX and RX monitoring
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_stream_agent extends uvm_agent;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(axi_stream_agent)

    //==========================================================================
    // Components
    //==========================================================================
    axi_stream_driver    driver;
    axi_stream_monitor   monitor;
    axi_stream_sequencer sequencer;

    //==========================================================================
    // Configuration
    //==========================================================================
    
    // Agent activity (UVM_ACTIVE or UVM_PASSIVE)
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    
    // Operating mode: 1 = master (TX), 0 = slave (RX)
    bit is_master = 1;
    
    // Enable monitoring for each direction
    bit monitor_tx = 1;
    bit monitor_rx = 1;

    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual axi_stream_if vif;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_stream_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get configuration
        if (!uvm_config_db#(uvm_active_passive_enum)::get(this, "", "is_active", is_active)) begin
            `uvm_info("AXIS_AGT", "is_active not set, defaulting to UVM_ACTIVE", UVM_MEDIUM)
        end
        
        if (!uvm_config_db#(bit)::get(this, "", "is_master", is_master)) begin
            `uvm_info("AXIS_AGT", "is_master not set, defaulting to 1 (TX master)", UVM_MEDIUM)
        end
        
        // Get virtual interface
        if (!uvm_config_db#(virtual axi_stream_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not found for axi_stream_agent")
        end
        
        // Always create monitor
        monitor = axi_stream_monitor::type_id::create("monitor", this);
        monitor.monitor_tx = monitor_tx;
        monitor.monitor_rx = monitor_rx;
        
        // Set virtual interface for monitor
        uvm_config_db#(virtual axi_stream_if)::set(this, "monitor", "vif", vif);
        
        // Create driver and sequencer if active
        if (is_active == UVM_ACTIVE) begin
            driver = axi_stream_driver::type_id::create("driver", this);
            driver.is_master = is_master;
            sequencer = axi_stream_sequencer::type_id::create("sequencer", this);
            
            // Set virtual interface for driver
            uvm_config_db#(virtual axi_stream_if)::set(this, "driver", "vif", vif);
        end
        
        `uvm_info("AXIS_AGT", $sformatf("Agent built: %s, %s mode", 
                  is_active == UVM_ACTIVE ? "ACTIVE" : "PASSIVE",
                  is_master ? "MASTER" : "SLAVE"), UVM_MEDIUM)
    endfunction

    //==========================================================================
    // Connect Phase
    //==========================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect driver to sequencer if active
        if (is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : axi_stream_agent
