// File: tb/top/eth_pkg.sv
package eth_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  
  // ==========================================
  // Protocol VIP Packages (reusable)
  // ==========================================
  
  // AXI-Stream
  `include "tb/agents/axi_stream/axi_stream_item.sv"
  `include "tb/agents/axi_stream/axi_stream_config.sv"
  `include "tb/agents/axi_stream/axi_stream_driver.sv"
  `include "tb/agents/axi_stream/axi_stream_monitor.sv"
  `include "tb/agents/axi_stream/axi_stream_sequencer.sv"
  `include "tb/agents/axi_stream/axi_stream_agent.sv"
  
  // AXI4
  `include "tb/agents/axi4/axi4_item.sv"
  `include "tb/agents/axi4/axi4_config.sv"
  `include "tb/agents/axi4/axi4_driver.sv"
  `include "tb/agents/axi4/axi4_monitor.sv"
  `include "tb/agents/axi4/axi4_sequencer.sv"
  `include "tb/agents/axi4/axi4_agent.sv"
  
  // AXI-Lite
  `include "tb/env/eth_controller/axi_lite_agent/axi_lite_item.sv"
  `include "tb/env/eth_controller/axi_lite_agent/axi_lite_config.sv"
  `include "tb/env/eth_controller/axi_lite_agent/axi_lite_driver.sv"
  `include "tb/env/eth_controller/axi_lite_agent/axi_lite_monitor.sv"
  `include "tb/env/eth_controller/axi_lite_agent/axi_lite_sequencer.sv"
  `include "tb/env/eth_controller/axi_lite_agent/axi_lite_agent.sv"
  
  // GMII
  `include "tb/agents/gmii/gmii_item.sv"
  `include "tb/agents/gmii/gmii_config.sv"
  `include "tb/agents/gmii/gmii_driver.sv"
  `include "tb/agents/gmii/gmii_monitor.sv"
  `include "tb/agents/gmii/gmii_sequencer.sv"
  `include "tb/agents/gmii/gmii_agent.sv"
  
  // ==========================================
  // MAC Environment
  // ==========================================
  `include "tb/env/mac/mac_config.sv"
  `include "tb/env/mac/mac_scoreboard.sv"
  `include "tb/env/mac/mac_env.sv"
  
  // ==========================================
  // DMA Environment
  // ==========================================
  `include "tb/env/dma/memory_model.sv"
  `include "tb/env/dma/dma_config.sv"
  `include "tb/env/dma/dma_scoreboard.sv"
  `include "tb/env/dma/dma_env.sv"
  
  // ==========================================
  // Top-Level Environment
  // ==========================================
  `include "tb/env/eth_controller/eth_controller_config.sv"
  `include "tb/env/eth_controller/eth_virtual_sequencer.sv"
  `include "tb/env/eth_controller/eth_scoreboard.sv"
  `include "tb/env/eth_controller/eth_controller_env.sv"
  
  // ==========================================
  // Sequence Library
  // ==========================================
  `include "tb/sequences/lib/axi_lite_base_seq.sv"
  `include "tb/sequences/lib/axi_lite_write_seq.sv"
  `include "tb/sequences/lib/axi_lite_read_seq.sv"
  `include "tb/sequences/lib/mac_reg_config_seq.sv"
  `include "tb/sequences/lib/dma_reg_config_seq.sv"
  `include "tb/sequences/lib/gmii_single_packet_seq.sv"
  `include "tb/sequences/lib/gmii_burst_seq.sv"
  
  `include "tb/sequences/virtual/eth_base_vseq.sv"
  `include "tb/sequences/virtual/eth_sanity_vseq.sv"
  `include "tb/sequences/virtual/eth_rx_path_vseq.sv"
  `include "tb/sequences/virtual/eth_tx_path_vseq.sv"
  `include "tb/sequences/virtual/eth_bidir_vseq.sv"
  
  // ==========================================
  // Test Library
  // ==========================================
  `include "tb/tests/base/eth_base_test.sv"
  `include "tb/tests/system_tests/eth_sanity_test.sv"
  `include "tb/tests/system_tests/eth_rx_path_test.sv"
  `include "tb/tests/system_tests/eth_tx_path_test.sv"
  `include "tb/tests/system_tests/eth_bidir_test.sv"
  `include "tb/tests/mac_tests/mac_sanity_test.sv"
  `include "tb/tests/dma_tests/dma_descriptor_test.sv"

endpackage : eth_pkg
