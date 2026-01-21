//==============================================================================
// Package: mac_scoreboard_pkg
// Description: MAC scoreboard package
//
// Contents:
//   - eth_crc_model:   CRC32 reference model
//   - mac_scoreboard:  Frame comparison scoreboard for MAC layer
//
// Dependencies:
//   - uvm_pkg
//   - gmii_agent_pkg (for gmii_frame)
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package mac_scoreboard_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import gmii_agent_pkg::*;
    
    // CRC reference model
    `include "eth_crc_model.sv"
    
    // MAC scoreboard
    `include "mac_scoreboard.sv"

endpackage : mac_scoreboard_pkg
