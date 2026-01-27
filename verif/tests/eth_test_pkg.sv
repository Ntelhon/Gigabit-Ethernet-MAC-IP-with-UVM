package eth_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "../top/eth_tb_params.svh"
  
  // Import environment package
  import eth_environment_pkg::*;

  // Import sequence package
  import eth_seq_pkg::*;
  
  // Base Test Components
  `include "src/base/eth_base_test.sv"

  // Mac Test Components
  `include "src/mac_tests/mac_sanity_test.sv"

  // DMA Test Components
  `include "src/dma_tests/dma_descriptor_test.sv"

  // System Test Components
  `include "src/system_tests/eth_sanity_test.sv"
  `include "src/system_tests/eth_rx_path_test.sv"
  `include "src/system_tests/eth_tx_path_test.sv"
  `include "src/system_tests/eth_bidir_test.sv"

endpackage : eth_test_pkg