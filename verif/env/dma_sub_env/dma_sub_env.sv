//==============================================================================
// Class: dma_sub_env
// Description: DMA engine sub-environment
//
// Purpose:
//   DMA-specific verification environment containing AXI-MM agent,
//   DMA scoreboard, and virtual sequencer for descriptor and memory operations.
//
// Components:
//   - axi_mm_agt:  AXI4 Memory Mapped agent (DMA master to memory)
//   - axis_agt:    AXI-Stream agent (optional, for DMA data path monitoring)
//   - scb:         DMA scoreboard (descriptor/buffer checking)
//   - v_sqr:       DMA virtual sequencer
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim, Xcelium
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class dma_sub_env extends uvm_env;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(dma_sub_env)

    //==========================================================================
    // Agent Handles
    //==========================================================================
    
    // AXI-MM agent - DMA master memory access
    axi_mm_agent axi_mm_agt;
    
    // AXI-Stream agent (optional - for DMA data path)
    axi_stream_agent axis_agt;
    
    // DMA scoreboard - descriptor and buffer checking
    dma_scoreboard scb;
    
    // DMA virtual sequencer
    dma_virtual_sequencer v_sqr;

    //==========================================================================
    // Configuration
    //==========================================================================
    bit enable_scoreboard = 1;
    bit enable_axis_agent = 0;  // Optional AXI-Stream for data monitoring
    uvm_active_passive_enum axi_mm_mode = UVM_ACTIVE;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "dma_sub_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info("DMA_ENV", "Building DMA Sub-Environment", UVM_LOW)
        
        // Get configuration
        if (!uvm_config_db#(bit)::get(this, "", "enable_scoreboard", enable_scoreboard))
            `uvm_info("DMA_ENV", "Using default enable_scoreboard=1", UVM_MEDIUM)
        
        if (!uvm_config_db#(bit)::get(this, "", "enable_axis_agent", enable_axis_agent))
            `uvm_info("DMA_ENV", "Using default enable_axis_agent=0", UVM_MEDIUM)
        
        // Create AXI-MM agent (always needed for DMA)
        axi_mm_agt = axi_mm_agent::type_id::create("axi_mm_agt", this);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "axi_mm_agt", "is_active", axi_mm_mode);
        
        // Create optional AXI-Stream agent
        if (enable_axis_agent) begin
            axis_agt = axi_stream_agent::type_id::create("axis_agt", this);
        end
        
        // Create scoreboard
        if (enable_scoreboard) begin
            scb = dma_scoreboard::type_id::create("scb", this);
        end
        
        // Create virtual sequencer
        v_sqr = dma_virtual_sequencer::type_id::create("v_sqr", this);
        
    endfunction

    //==========================================================================
    // Connect Phase
    //==========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        `uvm_info("DMA_ENV", "Connecting DMA Sub-Environment", UVM_LOW)
        
        // // Connect virtual sequencer
        // if (axi_mm_agt.sequencer != null)
        //     v_sqr.axi_mm_sqr = axi_mm_agt.sequencer;
        
        if (enable_axis_agent && axis_agt != null && axis_agt.sequencer != null)
            v_sqr.axis_sqr = axis_agt.sequencer;
        
        // Connect scoreboard
        if (enable_scoreboard && scb != null) begin
            // Connect AXI-MM monitor to scoreboard
            axi_mm_agt.monitor.read_ap.connect(scb.axi_mm_write_export);
            axi_mm_agt.monitor.write_ap.connect(scb.axi_mm_read_export);

            // Connect AXI-Stream if available
            if (enable_axis_agent && axis_agt != null) begin
                axis_agt.monitor.tx_ap.connect(scb.axis_tx_export);
                axis_agt.monitor.rx_ap.connect(scb.axis_rx_export);
            end
            
            `uvm_info("DMA_ENV", "Connected scoreboard analysis ports", UVM_MEDIUM)
        end
        
    endfunction

    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info("DMA_ENV", "=== DMA Sub-Environment Topology ===", UVM_LOW)
        `uvm_info("DMA_ENV", $sformatf("  AXI-MM Agent:     %s", axi_mm_mode.name()), UVM_LOW)
        `uvm_info("DMA_ENV", $sformatf("  AXI-Stream Agent: %s", enable_axis_agent ? "ENABLED" : "DISABLED"), UVM_LOW)
        `uvm_info("DMA_ENV", $sformatf("  Scoreboard:       %s", enable_scoreboard ? "ENABLED" : "DISABLED"), UVM_LOW)
        
    endfunction

endclass : dma_sub_env
