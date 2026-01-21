//==============================================================================
// Package: axi_stream_seq_lib_pkg
// Description: AXI-Stream sequence library
//
// Contains sequences that only drive the AXI-Stream interface
//==============================================================================

package axi_stream_seq_lib_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import axi_stream_agent_pkg::*;
    
    // AXI-Stream sequences (only drive AXI-Stream interface)
    `include "axi_stream_tx_seq.sv"

endpackage : axi_stream_seq_lib_pkg
