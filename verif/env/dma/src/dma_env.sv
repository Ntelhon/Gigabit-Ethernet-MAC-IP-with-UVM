// File: tb/env/dma/dma_env.sv
class dma_env extends uvm_env;

  `uvm_component_utils(dma_env)

  // Configuration
  dma_config cfg;
  
  // Agents
  axi4_agent#(`AXI4_PARAMS)             axi4_slave_agent; // Memory AXI4 Slave
  axi_stream_agent#(`AXI_STREAM_PARAMS) axis_tx_agent;  // DMA → MAC
  axi_stream_agent#(`AXI_STREAM_PARAMS) axis_rx_agent;  // MAC → DMA

  // Memory model
  memory_model mem;
  
  // Scoreboard
  dma_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(dma_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "DMA config not found")
    
    // Create memory model
    mem = memory_model::type_id::create("mem", this);
    uvm_config_db#(memory_model)::set(this, "scoreboard", "mem", mem);
    
    // Configure and create agents
    uvm_config_db#(axi4_config)::set(this, "axi4_slave_agent", "cfg", cfg.axi4_mem_cfg);
    uvm_config_db#(axi_stream_config)::set(this, "axis_tx_agent", "cfg", cfg.axis_tx_cfg);
    uvm_config_db#(axi_stream_config)::set(this, "axis_rx_agent", "cfg", cfg.axis_rx_cfg);

    axi4_slave_agent = axi4_agent#(`AXI4_PARAMS)::type_id::create("axi4_slave_agent", this);
    axis_tx_agent = axi_stream_agent#(`AXI_STREAM_PARAMS)::type_id::create("axis_tx_agent", this);
    axis_rx_agent = axi_stream_agent#(`AXI_STREAM_PARAMS)::type_id::create("axis_rx_agent", this);

    if(cfg.enable_scoreboard)
      scoreboard = dma_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    if(cfg.enable_scoreboard) begin
      axi4_slave_agent.monitor.ap.connect(scoreboard.dma_axi4_imp);
    end
  endfunction

endclass : dma_env
