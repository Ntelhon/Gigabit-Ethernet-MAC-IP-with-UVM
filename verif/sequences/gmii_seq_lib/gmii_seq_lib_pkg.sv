//==============================================================================
// Package: gmii_seq_lib_pkg
// Description: GMII sequence library package
//
// Contents:
//   - gmii_tx_seq:          Send single frame to MAC
//   - gmii_rx_seq:          Receive frames from MAC
//   - gmii_multi_frame_seq: Send multiple frames
//
// Usage:
//   import gmii_seq_lib_pkg::*;
//
// Dependencies:
//   - uvm_pkg
//   - gmii_agent_pkg
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package gmii_seq_lib_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import gmii_agent_pkg::*;
    
    // Include sequence files (only GMII interface drivers)
    `include "gmii_rx_seq.sv"
    `include "gmii_multi_frame_seq.sv"

endpackage : gmii_seq_lib_pkg
