//==============================================================================
// File: eth_seq_pkg.sv
// Description: Ethernet Sequence Package
//
// This package contains all sequence libraries for the Ethernet testbench:
// - AXI-Lite register access sequences
// - MAC/DMA configuration sequences
// - GMII packet sequences
// - Virtual sequences for coordinated multi-agent scenarios
//
// Usage:
//   import uvm_pkg::*;
//   import axi_lite_pkg::*;
//   import gmii_pkg::*;
//   import eth_seq_pkg::*;
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

package eth_seq_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  
  // Import agent packages (needed for sequences)
  import axi_stream_pkg::*;
  import axi4_pkg::*;
  import axi_lite_pkg::*;
  import gmii_pkg::*;

  // Import environment package (for configs, etc.)
  //import mac_subenvironment_pkg::*;
  //import dma_subenvironment_pkg::*;

  import eth_environment_pkg::*;
  
  // ==========================================
  // Sequence Library - Protocol-Specific
  // ==========================================
  
  // AXI-Lite Sequences
  `include "lib/axi_lite_base_seq.sv"
  `include "lib/axi_lite_write_seq.sv"
  `include "lib/axi_lite_read_seq.sv"
  
  // Register Configuration Sequences
  `include "lib/mac_reg_config_seq.sv"
  `include "lib/dma_reg_config_seq.sv"
  
  // GMII Packet Sequences
  `include "lib/gmii_single_packet_seq.sv"
  `include "lib/gmii_burst_seq.sv"
  
  // ==========================================
  // Virtual Sequences - System-Level
  // ==========================================
  `include "virtual/eth_base_vseq.sv"
  `include "virtual/eth_sanity_vseq.sv"
  `include "virtual/eth_rx_path_vseq.sv"
  `include "virtual/eth_tx_path_vseq.sv"
  `include "virtual/eth_bidir_vseq.sv"

endpackage : eth_seq_pkg
