package dma_subenvironment_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  
  // Import agent packages (needed for sub-environment)
  import axi_stream_pkg::*;
  import axi4_pkg::*;
  
  // DMA Sub-Environment Components
  `include "memory_model.sv"
  `include "dma_scoreboard.sv"
  `include "dma_config.sv"
  `include "dma_env.sv"

endpackage : dma_subenvironment_pkg
