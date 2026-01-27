// File: tb/env/mac/mac_env.sv
class mac_env extends uvm_env;

  `uvm_component_utils(mac_env)

  // Configuration
  mac_config cfg;
  
  // Agents
  axi_stream_agent#(`AXI_STREAM_PARAMS) tx_stream_agent;  // MAC → DMA
  axi_stream_agent#(`AXI_STREAM_PARAMS) rx_stream_agent;  // DMA → MAC
  gmii_agent                            gmii_tx_agent;    // MAC → PHY
  gmii_agent                            gmii_rx_agent;    // PHY → MAC
  
  // Scoreboard
  mac_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(mac_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "MAC config not found")
    
    // Configure and create agents
    uvm_config_db#(axi_stream_config)::set(this, "tx_stream_agent", "cfg", cfg.tx_stream_cfg);
    uvm_config_db#(axi_stream_config)::set(this, "rx_stream_agent", "cfg", cfg.rx_stream_cfg);
    uvm_config_db#(gmii_config)::set(this, "gmii_tx_agent", "cfg", cfg.gmii_tx_cfg);
    uvm_config_db#(gmii_config)::set(this, "gmii_rx_agent", "cfg", cfg.gmii_rx_cfg);

    tx_stream_agent = axi_stream_agent#(`AXI_STREAM_PARAMS)::type_id::create("tx_stream_agent", this);
    rx_stream_agent = axi_stream_agent#(`AXI_STREAM_PARAMS)::type_id::create("rx_stream_agent", this);
    gmii_tx_agent   = gmii_agent::type_id::create("gmii_tx_agent", this);
    gmii_rx_agent   = gmii_agent::type_id::create("gmii_rx_agent", this);
    
    if(cfg.enable_scoreboard)
      scoreboard = mac_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    if(cfg.enable_scoreboard) begin
      // RX path: GMII RX → AXI-Stream TX
      gmii_rx_agent.monitor.ap.connect(scoreboard.gmii_rx_imp);
      tx_stream_agent.monitor.ap.connect(scoreboard.axis_tx_imp);
      
      // TX path: AXI-Stream RX → GMII TX
      rx_stream_agent.monitor.ap.connect(scoreboard.axis_rx_imp);
      gmii_tx_agent.monitor.ap.connect(scoreboard.gmii_tx_imp);
    end
  endfunction

endclass : mac_env
