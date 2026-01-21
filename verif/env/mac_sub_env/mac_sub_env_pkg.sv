//==============================================================================
// Package: mac_sub_env_pkg
// Description: MAC sub-environment package
//
// Contents:
//   - mac_virtual_sequencer: MAC virtual sequencer
//   - mac_sub_env: MAC sub-environment
//
// Dependencies:
//   - uvm_pkg
//   - gmii_agent_pkg
//   - axi_lite_agent_pkg
//   - axi_stream_agent_pkg
//   - mac_scoreboard_pkg
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package mac_sub_env_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import gmii_agent_pkg::*;
    import axi_lite_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import mac_scoreboard_pkg::*;
    
    // MAC virtual sequencer (from old mac_virtual_sequencer.sv)
    `include "mac_virtual_sequencer.sv"
    
    // MAC sub-environment
    `include "mac_sub_env.sv"

endpackage : mac_sub_env_pkg
