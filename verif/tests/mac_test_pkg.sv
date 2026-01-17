//==============================================================================
// Package: mac_test_pkg
// Description: UVM test package for Gigabit Ethernet Controller IP
//
// Purpose:
//   Consolidates all test classes and sequences into a single package
//   for easy importing into the testbench top.
//
// Contents:
//   MAC Tests:
//   - mac_base_test: Base test class
//   - mac_tx_basic_test: RX path verification (legacy name)
//   - mac_tx_only_test: True TX path verification
//   - mac_tx_rx_loopback_test: Full TX-RX loopback test
//   - mac_rx_basic_test: RX path verification
//   - mac_crc_error_test: CRC error detection
//   - mac_runt_frame_test: Runt frame handling
//   - mac_ifg_test: Inter-Frame Gap verification
//   - mac_reset_during_traffic_test: Reset robustness
//   - mac_comprehensive_test: MAC-only comprehensive test
//
//   DMA Tests:
//   - dma_base_test: DMA base test class
//   - dma_tx_only_test: DMA TX path only
//   - dma_rx_only_test: DMA RX path only
//   - dma_tx_rx_test: DMA bidirectional
//   - dma_multi_packet_test: Multiple packet bursts
//   - dma_stress_test: High traffic stress test
//
//   Full Controller Tests:
//   - eth_controller_full_test: All features comprehensive test
//
// Dependencies:
//   - uvm_pkg
//   - mac_env_pkg
//   - axi_mm_agent_pkg
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
    import axi_mm_agent_pkg::*;

    //==========================================================================
    // Test Component Includes
    //==========================================================================
    
    // Base test class (must be first)
    `include "mac_base_test.sv"
    
    // MAC test sequences (from sequences folder)
    `include "../sequences/mac_test_sequences.sv"
    `include "../sequences/mac_tx_frame_seq.sv"
    `include "../sequences/gmii_tx_rx_loopback_seq.sv"
    `include "../sequences/axi_stream_tx_frame_seq.sv"
    
    // DMA test sequences (from sequences folder)
    `include "../sequences/dma_base_seq.sv"
    `include "../sequences/dma_config_seq.sv"
    `include "../sequences/dma_tx_seq.sv"
    `include "../sequences/dma_rx_seq.sv"
    `include "../sequences/dma_loopback_seq.sv"
    
    // MAC directed tests
    `include "mac_tx_basic_test.sv"
    `include "mac_tx_only_test.sv"
    `include "mac_tx_rx_loopback_test.sv"
    `include "mac_rx_basic_test.sv"
    `include "mac_crc_error_test.sv"
    `include "mac_runt_frame_test.sv"
    `include "mac_ifg_test.sv"
    `include "mac_reset_during_traffic_test.sv"
    `include "mac_comprehensive_test.sv"
    
    // DMA tests
    `include "dma_base_test.sv"
    `include "dma_tx_only_test.sv"
    `include "dma_rx_only_test.sv"
    `include "dma_tx_rx_test.sv"
    `include "dma_multi_packet_test.sv"
    `include "dma_stress_test.sv"
    
    // Full controller test
    `include "eth_controller_full_test.sv"

endpackage : mac_test_pkg
