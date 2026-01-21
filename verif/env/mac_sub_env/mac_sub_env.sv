//==============================================================================
// Class: mac_sub_env
// Description: MAC layer sub-environment
//
// Purpose:
//   MAC-specific verification environment containing GMII and AXI-Stream
//   agents, scoreboard, and virtual sequencer.
//   Note: AXI-Lite agent is shared and managed by parent eth_env.
//
// Components:
//   - gmii_agt:     GMII agent (PHY interface)
//   - axis_agt:     AXI-Stream agent (TX/RX data path)
//   - scb:          MAC scoreboard (frame checking, CRC validation)
//   - v_sqr:        MAC virtual sequencer (includes axi_lite_sqr from parent)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim, Xcelium
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_sub_env extends uvm_env;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_sub_env)

    //==========================================================================
    // Agent Handles
    //==========================================================================
    
    // GMII agent - PHY interface (GMII TX/RX)
    gmii_agent gmii_agt;
    
    // AXI-Stream agent - data path interface
    axi_stream_agent axis_agt;
    
    // MAC scoreboard - frame checking
    mac_scoreboard scb;
    
    // MAC virtual sequencer
    mac_virtual_sequencer v_sqr;

    //==========================================================================
    // Configuration
    //==========================================================================
    bit enable_scoreboard = 1;
    uvm_active_passive_enum gmii_mode = UVM_ACTIVE;
    uvm_active_passive_enum axi_mode = UVM_ACTIVE;
    uvm_active_passive_enum axis_mode = UVM_ACTIVE;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_sub_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("MAC_ENV", "Building MAC Sub-Environment", UVM_LOW)
        
        // Get configuration from database
        if (!uvm_config_db#(bit)::get(this, "", "enable_scoreboard", enable_scoreboard))
            `uvm_info("MAC_ENV", "Using default enable_scoreboard=1", UVM_MEDIUM)
        
        // Create agents
        gmii_agt = gmii_agent::type_id::create("gmii_agt", this);
        axis_agt = axi_stream_agent::type_id::create("axis_agt", this);
        
        // Set agent modes via config_db
        uvm_config_db#(uvm_active_passive_enum)::set(this, "gmii_agt", "is_active", gmii_mode);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "axis_agt", "is_active", axis_mode);
        
        // Create scoreboard
        if (enable_scoreboard) begin
            scb = mac_scoreboard::type_id::create("scb", this);
        end
        
        // Create virtual sequencer
        v_sqr = mac_virtual_sequencer::type_id::create("v_sqr", this);
        
    endfunction

    //==========================================================================
    // Connect Phase
    //==========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        `uvm_info("MAC_ENV", "Connecting MAC Sub-Environment", UVM_LOW)
        
        // Connect virtual sequencer
        if (gmii_agt.sequencer != null)
            v_sqr.gmii_sqr = gmii_agt.sequencer;
        
        // Note: axi_lite_sqr is connected by parent eth_env
        
        if (axis_agt.sequencer != null)
            v_sqr.axis_sqr = axis_agt.sequencer;
        
        if (axis_agt.sequencer != null)
            v_sqr.axis_sqr = axis_agt.sequencer;
        
        // Connect scoreboard
        if (enable_scoreboard && scb != null) begin
            // Connect GMII monitor outputs to scoreboard
            gmii_agt.tx_frame_port.connect(scb.tx_frame_export);
            gmii_agt.rx_frame_port.connect(scb.rx_frame_export);
            
            `uvm_info("MAC_ENV", "Connected scoreboard analysis ports", UVM_MEDIUM)
        end
        
    endfunction

    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info("MAC_ENV", "=== MAC Sub-Environment Topology ===", UVM_LOW)
        `uvm_info("MAC_ENV", $sformatf("  GMII Agent:       %s", gmii_mode.name()), UVM_LOW)
        `uvm_info("MAC_ENV", $sformatf("  AXI-Lite Agent:   %s", axi_mode.name()), UVM_LOW)
        `uvm_info("MAC_ENV", $sformatf("  AXI-Stream Agent: %s", axis_mode.name()), UVM_LOW)
        `uvm_info("MAC_ENV", $sformatf("  Scoreboard:       %s", enable_scoreboard ? "ENABLED" : "DISABLED"), UVM_LOW)
        
    endfunction

endclass : mac_sub_env
