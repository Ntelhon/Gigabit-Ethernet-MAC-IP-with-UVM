//==============================================================================
// Package: eth_test_pkg
// Description: Ethernet Controller test package
//
// Contents:
//   - eth_base_test: Base test class for all tests
//   - MAC tests: TX, RX, loopback, error injection tests
//   - DMA tests: DMA TX, RX, stress tests
//   - Full controller tests: Comprehensive integration tests
//
// Dependencies:
//   - uvm_pkg
//   - eth_env_pkg
//   - eth_seq_lib_pkg (includes mac_seq_lib_pkg and dma_seq_lib_pkg)
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package eth_test_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import gmii_agent_pkg::*;
    import axi_lite_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import axi_mm_agent_pkg::*;
    import mac_scoreboard_pkg::*;
    import dma_scoreboard_pkg::*;
    import mac_sub_env_pkg::*;      // Import MAC sub-environment types
    import dma_sub_env_pkg::*;      // Import DMA sub-environment types
    
    // Import interface-specific sequence libraries
    import axi_lite_seq_lib_pkg::*;   // AXI-Lite register sequences
    import gmii_seq_lib_pkg::*;       // GMII frame sequences
    import axi_stream_seq_lib_pkg::*; // AXI-Stream data sequences
    
    import eth_env_pkg::*;

    // Base test class
    `include "eth_base_test.sv"
    
    // MAC tests
    `include "mac_base_test.sv"
    `include "mac_rx_basic_test.sv"
    `include "mac_tx_basic_test.sv"
    `include "mac_crc_error_test.sv"
    `include "mac_runt_frame_test.sv"
    `include "mac_tx_rx_loopback_test.sv"
    `include "mac_ifg_test.sv"
    `include "mac_reset_during_traffic_test.sv"
    `include "mac_comprehensive_test.sv"
    
    // DMA tests
    //`include "dma_base_test.sv"
    //`include "dma_tx_only_test.sv"
    //`include "dma_rx_only_test.sv"
    //`include "dma_tx_rx_test.sv"
    //`include "dma_multi_packet_test.sv"
    //`include "dma_stress_test.sv"
    //
    //// Full controller test
    //`include "eth_controller_full_test.sv"

endpackage : eth_test_pkg
