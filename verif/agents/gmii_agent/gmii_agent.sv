//==============================================================================
// Class: gmii_agent
// Description: UVM Agent for GMII interface
//
// Purpose:
//   Complete UVM agent that encapsulates driver, monitor, and sequencer
//   for the GMII interface. Acts as a behavioral PHY model for verifying
//   the Gigabit Ethernet MAC.
//
// Components:
//   - gmii_driver:    Drives RX data to the MAC (PHY -> MAC)
//   - gmii_monitor:   Monitors TX data from the MAC (MAC -> PHY)
//   - gmii_sequencer: Manages frame transactions
//
// Modes:
//   - UVM_ACTIVE:  Driver, Monitor, and Sequencer active
//   - UVM_PASSIVE: Monitor only (for observation)
//
// Analysis Ports:
//   - tx_frame_port: Broadcasts captured TX frames to scoreboard
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_agent extends uvm_agent;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(gmii_agent)

    //==========================================================================
    // Agent Components
    //==========================================================================
    gmii_driver     driver;
    gmii_monitor    monitor;
    gmii_sequencer  sequencer;

    //==========================================================================
    // Analysis Port (passthrough from monitor)
    //==========================================================================
    uvm_analysis_port #(gmii_frame) tx_frame_port;   // Frames TX'd by MAC (from monitor)
    uvm_analysis_port #(gmii_frame) rx_frame_port;   // Frames RX'd by MAC (from driver)

    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual gmii_if vif;

    //==========================================================================
    // Configuration
    //==========================================================================
    
    // Agent active/passive mode (from uvm_agent)
    // uvm_active_passive_enum is_active = UVM_ACTIVE;
    
    // Enable coverage collection
    bit enable_coverage = 1;
    
    // Enable checking in monitor
    bit enable_checks = 1;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "gmii_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface from config database
        if (!uvm_config_db#(virtual gmii_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not found for gmii_agent")
        end
        
        // Create analysis ports
        tx_frame_port = new("tx_frame_port", this);
        rx_frame_port = new("rx_frame_port", this);
        
        // Always create monitor
        monitor = gmii_monitor::type_id::create("monitor", this);
        
        // Create driver and sequencer only in active mode
        if (is_active == UVM_ACTIVE) begin
            driver    = gmii_driver::type_id::create("driver", this);
            sequencer = gmii_sequencer::type_id::create("sequencer", this);
        end
        
        // Configure monitor
        monitor.check_crc = enable_checks;
        
        // Set virtual interface for sub-components
        uvm_config_db#(virtual gmii_if.tx_monitor)::set(this, "monitor", "vif", vif);
        
        if (is_active == UVM_ACTIVE) begin
            uvm_config_db#(virtual gmii_if.rx_driver)::set(this, "driver", "vif", vif);
        end
        
    endfunction

    //==========================================================================
    // Connect Phase
    //==========================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect monitor's analysis port to agent's TX analysis port
        // (frames transmitted BY the MAC)
        monitor.frame_port.connect(tx_frame_port);
        
        // Connect driver to sequencer in active mode
        if (is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
            
            // Connect driver's analysis port to agent's RX analysis port
            // (frames sent TO the MAC)
            driver.frame_port.connect(rx_frame_port);
        end
        
    endfunction

    //==========================================================================
    // Report Phase
    //==========================================================================
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("GMII_AGENT", $sformatf("Agent mode: %s", 
                  is_active == UVM_ACTIVE ? "ACTIVE" : "PASSIVE"), UVM_LOW)
    endfunction

endclass : gmii_agent


//==============================================================================
// Class: gmii_agent_config
// Description: Configuration object for GMII agent
//
// Purpose:
//   Encapsulates all configuration parameters for the GMII agent.
//   Can be passed via uvm_config_db.
//==============================================================================

class gmii_agent_config extends uvm_object;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_object_utils(gmii_agent_config)

    //==========================================================================
    // Configuration Fields
    //==========================================================================
    
    // Active or passive mode
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    
    // Enable coverage collection
    bit enable_coverage = 1;
    
    // Enable functional checks
    bit enable_checks = 1;
    
    // Enable automatic padding in driver
    bit enable_padding = 1;
    
    // Default inter-frame gap (bytes)
    int unsigned default_ifg = 12;
    
    // Minimum frame size
    int unsigned min_frame_size = 64;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "gmii_agent_config");
        super.new(name);
    endfunction

endclass : gmii_agent_config
