//==============================================================================
// Class: mac_env
// Description: UVM environment for Gigabit Ethernet MAC IP verification
//
// Purpose:
//   Top-level verification environment that instantiates and connects all
//   UVM components for comprehensive MAC testing.
//
// Components:
//   - gmii_agt:     GMII agent (active) - drives RX, monitors TX
//   - axi_lite_agt: AXI-Lite agent (active) - register access
//   - scb:          Ethernet scoreboard - frame checking
//   - v_sqr:        Virtual sequencer - test coordination
//
// Connections:
//   - GMII monitor → Scoreboard TX analysis port (MAC output)
//   - GMII agent → Scoreboard RX analysis port (MAC input)
//   - AXI-Lite monitor → (optional) coverage/checking
//
// Configuration:
//   - All interfaces via uvm_config_db
//   - Agent modes via uvm_config_db
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class mac_env extends uvm_env;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(mac_env)

    //==========================================================================
    // Environment Components
    //==========================================================================
    
    // GMII Agent - Drives frames to MAC RX, monitors MAC TX
    gmii_agent gmii_agt;
    
    // AXI-Lite Agent - Register read/write access
    axi_lite_agent axi_lite_agt;
    
    // AXI-Stream Agent - TX/RX data path
    axi_stream_agent axis_agt;
    
    // Ethernet Scoreboard - Frame and CRC checking
    eth_scoreboard scb;
    
    // Virtual Sequencer - Test coordination
    mac_virtual_sequencer v_sqr;

    //==========================================================================
    // Configuration Flags
    //==========================================================================
    
    // Enable scoreboard (default: enabled)
    bit enable_scoreboard = 1;
    
    // GMII agent mode (default: active)
    uvm_active_passive_enum gmii_mode = UVM_ACTIVE;
    
    // AXI-Lite agent mode (default: active)
    uvm_active_passive_enum axi_mode = UVM_ACTIVE;
    
    // AXI-Stream agent mode (default: active)
    uvm_active_passive_enum axis_mode = UVM_ACTIVE;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mac_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        //----------------------------------------------------------------------
        // Get Configuration from uvm_config_db
        //----------------------------------------------------------------------
        void'(uvm_config_db#(bit)::get(this, "", "enable_scoreboard", enable_scoreboard));
        void'(uvm_config_db#(uvm_active_passive_enum)::get(this, "", "gmii_mode", gmii_mode));
        void'(uvm_config_db#(uvm_active_passive_enum)::get(this, "", "axi_mode", axi_mode));
        void'(uvm_config_db#(uvm_active_passive_enum)::get(this, "", "axis_mode", axis_mode));
        
        //----------------------------------------------------------------------
        // Set Agent Configurations
        //----------------------------------------------------------------------
        uvm_config_db#(uvm_active_passive_enum)::set(this, "gmii_agt", "is_active", gmii_mode);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "axi_lite_agt", "is_active", axi_mode);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "axis_agt", "is_active", axis_mode);
        
        //----------------------------------------------------------------------
        // Create GMII Agent
        //----------------------------------------------------------------------
        gmii_agt = gmii_agent::type_id::create("gmii_agt", this);
        `uvm_info("BUILD", "GMII agent created", UVM_MEDIUM)
        
        //----------------------------------------------------------------------
        // Create AXI-Lite Agent
        //----------------------------------------------------------------------
        axi_lite_agt = axi_lite_agent::type_id::create("axi_lite_agt", this);
        `uvm_info("BUILD", "AXI-Lite agent created", UVM_MEDIUM)
        
        //----------------------------------------------------------------------
        // Create AXI-Stream Agent
        //----------------------------------------------------------------------
        axis_agt = axi_stream_agent::type_id::create("axis_agt", this);
        `uvm_info("BUILD", "AXI-Stream agent created", UVM_MEDIUM)
        
        //----------------------------------------------------------------------
        // Create Scoreboard (if enabled)
        //----------------------------------------------------------------------
        if (enable_scoreboard) begin
            scb = eth_scoreboard::type_id::create("scb", this);
            `uvm_info("BUILD", "Ethernet scoreboard created", UVM_MEDIUM)
        end
        
        //----------------------------------------------------------------------
        // Create Virtual Sequencer
        //----------------------------------------------------------------------
        v_sqr = mac_virtual_sequencer::type_id::create("v_sqr", this);
        `uvm_info("BUILD", "Virtual sequencer created", UVM_MEDIUM)
        
    endfunction

    //==========================================================================
    // Connect Phase
    //==========================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        //----------------------------------------------------------------------
        // Connect Sub-Sequencers to Virtual Sequencer
        //----------------------------------------------------------------------
        if (gmii_mode == UVM_ACTIVE) begin
            v_sqr.gmii_sqr = gmii_agt.sequencer;
            `uvm_info("CONNECT", "GMII sequencer connected to virtual sequencer", UVM_MEDIUM)
        end
        
        if (axi_mode == UVM_ACTIVE) begin
            v_sqr.axi_sqr = axi_lite_agt.sequencer;
            `uvm_info("CONNECT", "AXI-Lite sequencer connected to virtual sequencer", UVM_MEDIUM)
        end
        
        if (axis_mode == UVM_ACTIVE) begin
            v_sqr.axis_sqr = axis_agt.sequencer;
            `uvm_info("CONNECT", "AXI-Stream sequencer connected to virtual sequencer", UVM_MEDIUM)
        end
        
        //----------------------------------------------------------------------
        // Connect Monitors to Scoreboard
        //----------------------------------------------------------------------
        if (enable_scoreboard) begin
            // GMII TX monitor → Scoreboard tx_frame_export
            // This captures what the MAC transmits (frames FROM MAC)
            gmii_agt.tx_frame_port.connect(scb.tx_frame_export);
            `uvm_info("CONNECT", "GMII TX monitor connected to scoreboard TX export", UVM_MEDIUM)
            
            // GMII driver → Scoreboard rx_frame_export  
            // This captures what is sent TO the MAC (frames TO MAC)
            if (gmii_mode == UVM_ACTIVE) begin
                gmii_agt.rx_frame_port.connect(scb.rx_frame_export);
                `uvm_info("CONNECT", "GMII driver connected to scoreboard RX export", UVM_MEDIUM)
            end
        end
        
    endfunction

    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        // Print environment topology
        `uvm_info("ENV", "MAC Environment Topology:", UVM_LOW)
        `uvm_info("ENV", $sformatf("  - GMII Agent:       mode=%s", gmii_mode.name()), UVM_LOW)
        `uvm_info("ENV", $sformatf("  - AXI-Lite Agent:   mode=%s", axi_mode.name()), UVM_LOW)
        `uvm_info("ENV", $sformatf("  - AXI-Stream Agent: mode=%s", axis_mode.name()), UVM_LOW)
        `uvm_info("ENV", $sformatf("  - Scoreboard:       %s", enable_scoreboard ? "enabled" : "disabled"), UVM_LOW)
        `uvm_info("ENV", "  - Virtual Sequencer: created", UVM_LOW)
        
    endfunction

    //==========================================================================
    // Report Phase
    //==========================================================================
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("ENV", "=== MAC Environment Final Report ===", UVM_LOW)
        
        // Scoreboard reports its own statistics
        
    endfunction

endclass : mac_env
