// File: tb/tests/dma_tests/dma_descriptor_test.sv
class dma_descriptor_test extends eth_base_test;

  `uvm_component_utils(dma_descriptor_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure_env();
    super.configure_env();
    
    // Disable MAC, enable only DMA
    cfg.enable_mac = 0;
    cfg.enable_dma = 1;
    cfg.enable_system_scoreboard = 0;
  endfunction

  task run_phase(uvm_phase phase);
    dma_reg_config_seq dma_cfg_seq;
    
    super.run_phase(phase);
    
    phase.raise_objection(this);
    
    // Configure DMA via AXI-Lite (still available at system level)
    dma_cfg_seq = dma_reg_config_seq::type_id::create("dma_cfg_seq");
    dma_cfg_seq.start(env.axi_lite_agent_h.sequencer);
    
    // Setup descriptors
    setup_test_descriptors();
    
    #10us;
    
    phase.drop_objection(this);
  endtask

  task setup_test_descriptors();
    byte unsigned desc[];
    desc = new[16];
    // Setup descriptor chain
    env.dma_env_h.mem.init_mem(32'h1000_0000, desc);
    `uvm_info("DMA_TEST", "Descriptors initialized", UVM_MEDIUM)
  endtask

endclass : dma_descriptor_test
