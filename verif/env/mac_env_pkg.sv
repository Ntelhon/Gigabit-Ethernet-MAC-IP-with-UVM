//==============================================================================
// Package: mac_env_pkg
// Description: UVM environment package for Gigabit Ethernet MAC IP
//
// Purpose:
//   Consolidates all environment components into a single package for
//   easy importing into testbenches and test files.
//
// Contents:
//   - mac_virtual_sequencer: Virtual sequencer for test coordination
//   - mac_virtual_sequence_base: Base class for virtual sequences
//   - mac_env: Top-level UVM environment
//
// Dependencies:
//   - uvm_pkg
//   - gmii_agent_pkg
//   - axi_lite_agent_pkg
//   - eth_scoreboard_pkg
//
// Usage:
//   import mac_env_pkg::*;
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package mac_env_pkg;

    //==========================================================================
    // UVM Import
    //==========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //==========================================================================
    // Agent Package Imports
    //==========================================================================
    import gmii_agent_pkg::*;
    import axi_lite_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import eth_scoreboard_pkg::*;

    //==========================================================================
    // Environment Component Includes
    //==========================================================================
    `include "mac_virtual_sequencer.sv"
    `include "mac_env.sv"

endpackage : mac_env_pkg
