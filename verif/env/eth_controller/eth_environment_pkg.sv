package eth_environment_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "../../top/eth_tb_params.svh"
  
  // Import agent packages
  import axi_stream_pkg::*;
  import axi4_pkg::*;
  import axi_lite_pkg::*;
  import gmii_pkg::*;

  // MAC Environment Components
  `include "../mac/src/mac_config.sv"
  `include "../mac/src/mac_scoreboard.sv"
  `include "../mac/src/mac_env.sv"
  
  // DMA Environment Components
  `include "../dma/src/memory_model.sv"
  `include "../dma/src/dma_config.sv"
  `include "../dma/src/dma_scoreboard.sv"
  `include "../dma/src/dma_env.sv"
  
  // Ethernet Controller Environment Components
  `include "src/eth_controller_config.sv"
  `include "src/eth_virtual_sequencer.sv"
  `include "src/eth_scoreboard.sv"
  `include "src/eth_controller_env.sv"

endpackage : eth_environment_pkg