//==============================================================================
// AXI4 Memory Master Agent Package
// 
// This package contains UVM components for verifying AXI4 memory master
// interfaces (DMA). Includes:
// - Transaction items for AXI4 read/write
// - Memory model for DMA target
// - Driver (slave responder)
// - Monitor
// - Agent
//==============================================================================

`ifndef AXI_MM_AGENT_PKG_SV
`define AXI_MM_AGENT_PKG_SV

package axi_mm_agent_pkg;
    
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    //==========================================================================
    // Parameters
    //==========================================================================
    parameter int AXI_ADDR_WIDTH = 64;
    parameter int AXI_DATA_WIDTH = 64;
    parameter int AXI_ID_WIDTH   = 4;
    parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
    
    //==========================================================================
    // Forward declarations
    //==========================================================================
    typedef class axi_mm_item;
    typedef class axi_mm_driver;
    typedef class axi_mm_monitor;
    typedef class axi_mm_agent;
    typedef class axi_mm_mem_model;
    
    `include "axi_mm_item.sv"
    `include "axi_mm_mem_model.sv"
    `include "axi_mm_driver.sv"
    `include "axi_mm_monitor.sv"
    `include "axi_mm_agent.sv"
    
endpackage : axi_mm_agent_pkg

`endif // AXI_MM_AGENT_PKG_SV
