//==============================================================================
// Package: eth_seq_lib_pkg
// Description: Ethernet sequence library package (Top-level)
//
// Contents:
//   - MAC sequence library
//   - DMA sequence library
//
// This package imports both MAC and DMA sequence libraries and provides
// a single consolidated sequence library for the Ethernet controller.
//
// Dependencies:
//   - uvm_pkg
//   - gmii_agent_pkg
//   - axi_lite_agent_pkg
//   - axi_stream_agent_pkg
//   - axi_mm_agent_pkg
//   - mac_seq_lib_pkg
//   - dma_seq_lib_pkg
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package eth_seq_lib_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // Import agent packages (required by sequence libraries)
    import gmii_agent_pkg::*;
    import axi_lite_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import axi_mm_agent_pkg::*;
    
    //// AXI-Lite sequence library
    import axi_lite_seq_lib_pkg::*;
    
    //// GMII sequence library
    import gmii_seq_lib_pkg::*;

    //// AXI-Stream sequence library
    import axi_stream_seq_lib_pkg::*;

    //// AXI-MM sequence library
    //import axi_mm_seq_lib_pkg::*;

endpackage : eth_seq_lib_pkg
