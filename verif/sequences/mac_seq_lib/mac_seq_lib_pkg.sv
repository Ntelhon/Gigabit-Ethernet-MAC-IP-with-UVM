//==============================================================================
// Package: mac_seq_lib_pkg
// Description: MAC sequence library package
//
// Contents:
//   - MAC base sequence
//   - MAC test sequences
//   - MAC frame sequences
//   - GMII loopback sequences
//   - AXI-Stream sequences
//
// Dependencies:
//   - uvm_pkg
//   - gmii_agent_pkg
//   - axi_lite_agent_pkg
//   - axi_stream_agent_pkg
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package mac_seq_lib_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import gmii_agent_pkg::*;
    import axi_lite_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import gmii_seq_lib_pkg::*;  // GMII sequences (tx, rx, multi-frame)
    
    // MAC register definitions
    `include "mac_reg_defines.svh"
    
    // Base sequence (must be included first)
    `include "mac_base_seq.sv"
    
    // MAC test sequences
    `include "mac_test_sequences.sv"
    `include "mac_tx_frame_seq.sv"
    `include "gmii_tx_rx_loopback_seq.sv"
    `include "axi_stream_tx_frame_seq.sv"

endpackage : mac_seq_lib_pkg
