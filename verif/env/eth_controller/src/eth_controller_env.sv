// File: tb/env/eth_controller/eth_controller_env.sv
class eth_controller_env extends uvm_env;

  `uvm_component_utils(eth_controller_env)

  // Configuration
  eth_controller_config cfg;
  
  // Sub-environments
  mac_env mac_env_h;
  dma_env dma_env_h;
  
  // System-level agent (AXI-Lite for register access)
  axi_lite_agent#(`AXI_LITE_PARAMS) axi_lite_agent_h;
  
  // Virtual sequencer
  eth_virtual_sequencer virtual_sqr;
  
  // System-level scoreboard
  eth_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(eth_controller_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Eth controller config not found")
    
    // Create virtual sequencer
    virtual_sqr = eth_virtual_sequencer::type_id::create("virtual_sqr", this);
    uvm_config_db#(eth_controller_config)::set(this, "virtual_sqr", "cfg", cfg);
    
    // Create AXI-Lite agent (system-level register interface)
    uvm_config_db#(axi_lite_config)::set(this, "axi_lite_agent_h", "cfg", cfg.axi_lite_cfg);
    axi_lite_agent_h = axi_lite_agent#(`AXI_LITE_PARAMS)::type_id::create("axi_lite_agent_h", this);
    
    // Create sub-environments
    if(cfg.enable_mac) begin
      uvm_config_db#(mac_config)::set(this, "mac_env_h", "cfg", cfg.mac_cfg);
      mac_env_h = mac_env::type_id::create("mac_env_h", this);
    end
    
    if(cfg.enable_dma) begin
      uvm_config_db#(dma_config)::set(this, "dma_env_h", "cfg", cfg.dma_cfg);
      dma_env_h = dma_env::type_id::create("dma_env_h", this);
    end
    
    // Create system-level scoreboard
    if(cfg.enable_system_scoreboard) begin
      scoreboard = eth_scoreboard::type_id::create("scoreboard", this);
      if(cfg.enable_dma)
        uvm_config_db#(memory_model)::set(this, "scoreboard", "mem", dma_env_h.mem);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    // Connect virtual sequencer handles
    virtual_sqr.axi_lite_sqr = axi_lite_agent_h.sequencer;
    virtual_sqr.cfg = cfg;
    
    if(cfg.enable_mac) begin
      virtual_sqr.gmii_phy_sqr = mac_env_h.gmii_phy_agent.sequencer;
    end
    
    if(cfg.enable_dma) begin
      virtual_sqr.mem = dma_env_h.mem;
    end
    
    // Connect system scoreboard
    if(cfg.enable_system_scoreboard) begin
      if(cfg.enable_mac) begin
        // mac_env_h.gmii_phy_agent.monitor.rx_ap.connect(scoreboard.gmii_imp);
        // mac_env_h.gmii_phy_agent.monitor.tx_ap.connect(scoreboard.gmii_imp);
        //mac_env_h.tx_stream_agent.monitor.ap.connect(scoreboard.axis_mac_tx_imp);
        //mac_env_h.rx_stream_agent.monitor.ap.connect(scoreboard.axis_mac_rx_imp);
      end
      
      if(cfg.enable_dma) begin
        dma_env_h.axi4_slave_agent.monitor.ap.connect(scoreboard.axi4_imp);
      end
    end
  endfunction

endclass : eth_controller_env
