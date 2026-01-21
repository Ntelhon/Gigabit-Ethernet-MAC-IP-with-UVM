//==============================================================================
// Class: eth_env
// Description: Top-level UVM environment for Gigabit Ethernet Controller
//
// Purpose:
//   Top-level verification environment that instantiates MAC and DMA
//   sub-environments, providing a unified hierarchy for comprehensive
//   Ethernet controller verification.
//
// Architecture:
//   eth_env (Top)
//     ├── axi_lite_agt  (Shared register access for MAC and DMA)
//     ├── mac_sub_env   (MAC verification sub-environment)
//     └── dma_sub_env   (DMA verification sub-environment)
//
// Components:
//   - axi_lite_agt: Shared AXI-Lite agent for register access (MAC & DMA)
//   - mac_sub_env:  MAC layer verification (GMII, AXI-Stream)
//   - dma_sub_env:  DMA engine verification (AXI-MM memory access, descriptors)
//   - eth_v_sqr:    Top-level virtual sequencer for coordinating tests
//
// Configuration:
//   - enable_mac:  Enable MAC sub-environment (default: 1)
//   - enable_dma:  Enable DMA sub-environment (default: 0)
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim, Xcelium
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class eth_env extends uvm_env;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(eth_env)

    //==========================================================================
    // Sub-Environment Handles
    //==========================================================================
    
    // MAC sub-environment (always instantiated for MAC-only or full tests)
    mac_sub_env mac_env;
    
    // DMA sub-environment (instantiated for DMA-enabled tests)
    dma_sub_env dma_env;
    
    // Shared AXI-Lite agent (used by both MAC and DMA for register access)
    axi_lite_agent axi_lite_agt;
    
    // Top-level virtual sequencer
    eth_virtual_sequencer v_sqr;

    //==========================================================================
    // Configuration Flags
    //==========================================================================
    
    // Enable/disable sub-environments
    bit enable_mac = 1;  // Default: MAC enabled
    bit enable_dma = 0;  // Default: DMA disabled (MAC-only tests)
    
    // Global test configuration
    bit enable_coverage = 1;
    bit enable_checks = 1;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "eth_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("ETH_ENV", "Building Ethernet Controller Environment", UVM_LOW)
        
        // Check configuration database for environment enables
        if (!uvm_config_db#(bit)::get(this, "", "enable_mac", enable_mac))
            `uvm_info("ETH_ENV", "Using default enable_mac=1", UVM_MEDIUM)
        
        if (!uvm_config_db#(bit)::get(this, "", "enable_dma", enable_dma))
            `uvm_info("ETH_ENV", "Using default enable_dma=0", UVM_MEDIUM)
        
        // Create virtual sequencer
        v_sqr = eth_virtual_sequencer::type_id::create("v_sqr", this);
        
        // Create shared AXI-Lite agent (used for both MAC and DMA register access)
        axi_lite_agt = axi_lite_agent::type_id::create("axi_lite_agt", this);
        `uvm_info("ETH_ENV", "Created shared AXI-Lite agent", UVM_MEDIUM)
        
        // Create MAC sub-environment (if enabled)
        if (enable_mac) begin
            `uvm_info("ETH_ENV", "Creating MAC sub-environment", UVM_LOW)
            mac_env = mac_sub_env::type_id::create("mac_env", this);
        end
        
        // Create DMA sub-environment (if enabled)
        if (enable_dma) begin
            `uvm_info("ETH_ENV", "Creating DMA sub-environment", UVM_LOW)
            dma_env = dma_sub_env::type_id::create("dma_env", this);
        end
        
    endfunction

    //==========================================================================
    // Connect Phase
    //==========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        `uvm_info("ETH_ENV", "Connecting Ethernet Controller Environment", UVM_LOW)
        
        // Connect shared AXI-Lite sequencer to sub-environment virtual sequencers
        if (enable_mac && mac_env != null) begin
            v_sqr.mac_sqr = mac_env.v_sqr;
            mac_env.v_sqr.axi_lite_sqr = axi_lite_agt.sequencer;
            `uvm_info("ETH_ENV", "Connected MAC virtual sequencer with shared AXI-Lite", UVM_MEDIUM)
        end
        
        if (enable_dma && dma_env != null) begin
            v_sqr.dma_sqr = dma_env.v_sqr;
            dma_env.v_sqr.axi_lite_sqr = axi_lite_agt.sequencer;
            `uvm_info("ETH_ENV", "Connected DMA virtual sequencer with shared AXI-Lite", UVM_MEDIUM)
            
            // If both MAC and DMA are enabled, connect cross-environment ports
            if (enable_mac && mac_env != null) begin
                // Connect AXI-Stream from MAC TX to DMA scoreboard
                // TODO: Type mismatch - axis sends axi_stream_txn, dma_scb expects different type
                // mac_env.axis_agt.monitor.tx_ap.connect(dma_env.scb.mac_tx_export);
                
                // Connect AXI-Stream from DMA TX to MAC scoreboard  
                // TODO: Type mismatch - axis sends axi_stream_txn, mac_scb expects gmii_frame
                // if (dma_env.axis_agt != null) begin
                //     dma_env.axis_agt.monitor.rx_ap.connect(mac_env.scb.tx_frame_export);
                // end
                
                `uvm_info("ETH_ENV", "Cross-environment connections skipped (type mismatch)", UVM_MEDIUM)
            end
        end
        
    endfunction

    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info("ETH_ENV", "==============================================", UVM_LOW)
        `uvm_info("ETH_ENV", "  Ethernet Controller Environment Topology  ", UVM_LOW)
        `uvm_info("ETH_ENV", "==============================================", UVM_LOW)
        `uvm_info("ETH_ENV", $sformatf("  MAC Sub-Environment: %s", enable_mac ? "ENABLED" : "DISABLED"), UVM_LOW)
        `uvm_info("ETH_ENV", $sformatf("  DMA Sub-Environment: %s", enable_dma ? "ENABLED" : "DISABLED"), UVM_LOW)
        `uvm_info("ETH_ENV", $sformatf("  Coverage:            %s", enable_coverage ? "ENABLED" : "DISABLED"), UVM_LOW)
        `uvm_info("ETH_ENV", "==============================================", UVM_LOW)
        
    endfunction

    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("ETH_ENV", "=== Ethernet Controller Environment Final Report ===", UVM_LOW)
        
        if (enable_mac && mac_env != null) begin
            `uvm_info("ETH_ENV", "MAC Sub-Environment: Active", UVM_LOW)
        end
        
        if (enable_dma && dma_env != null) begin
            `uvm_info("ETH_ENV", "DMA Sub-Environment: Active", UVM_LOW)
        end
        
    endfunction

endclass : eth_env
