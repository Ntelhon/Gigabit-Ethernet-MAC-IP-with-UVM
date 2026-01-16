//==============================================================================
// Package: mac_test_pkg
// Description: UVM test package for Gigabit Ethernet MAC IP
//
// Purpose:
//   Consolidates all test classes and sequences into a single package
//   for easy importing into the testbench top.
//
// Contents:
//   - mac_base_test: Base test class
//   - mac_test_sequences: All directed test sequences
//   - mac_tx_frame_seq: TX frame generation sequence (AXI-Stream TX)
//   - gmii_tx_rx_loopback_seq: TX-RX loopback sequence
//   - mac_tx_basic_test: RX path verification (legacy name)
//   - mac_tx_only_test: True TX path verification
//   - mac_tx_rx_loopback_test: Full TX-RX loopback test
//   - mac_rx_basic_test: RX path verification
//   - mac_crc_error_test: CRC error detection
//   - mac_runt_frame_test: Runt frame handling
//   - mac_ifg_test: Inter-Frame Gap verification
//   - mac_reset_during_traffic_test: Reset robustness
//
// Dependencies:
//   - uvm_pkg
//   - mac_env_pkg
//
// Usage:
//   import mac_test_pkg::*;
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package mac_test_pkg;

    //==========================================================================
    // UVM Import
    //==========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //==========================================================================
    // Environment Package Import
    //==========================================================================
    import mac_env_pkg::*;
    import gmii_agent_pkg::*;
    import axi_lite_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import eth_scoreboard_pkg::*;

    //==========================================================================
    // Test Component Includes
    //==========================================================================
    
    // Base test class (must be first)
    `include "mac_base_test.sv"
    
    // Test sequences (from sequences folder)
    `include "../sequences/mac_test_sequences.sv"
    `include "../sequences/mac_tx_frame_seq.sv"
    `include "../sequences/gmii_tx_rx_loopback_seq.sv"
    `include "../sequences/axi_stream_tx_frame_seq.sv"
    
    // Directed tests (one per file)
    `include "mac_tx_basic_test.sv"
    `include "mac_tx_only_test.sv"
    `include "mac_tx_rx_loopback_test.sv"
    `include "mac_rx_basic_test.sv"
    `include "mac_crc_error_test.sv"
    `include "mac_runt_frame_test.sv"
    `include "mac_ifg_test.sv"
    `include "mac_reset_during_traffic_test.sv"
    `include "mac_comprehensive_test.sv"

endpackage : mac_test_pkg
