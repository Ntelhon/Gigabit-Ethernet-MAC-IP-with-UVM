// File: tb/env/eth_controller/axi_lite_agent/axi_lite_agent.sv
class axi_lite_agent #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 32
) extends uvm_agent;

  `uvm_component_param_utils(axi_lite_agent#(ADDR_WIDTH, DATA_WIDTH))

  typedef axi_lite_driver#(ADDR_WIDTH, DATA_WIDTH)    driver_t;
  typedef axi_lite_monitor#(ADDR_WIDTH, DATA_WIDTH)   monitor_t;
  typedef axi_lite_sequencer#(ADDR_WIDTH, DATA_WIDTH) sequencer_t;

  driver_t    driver;
  monitor_t   monitor;
  sequencer_t sequencer;
  
  axi_lite_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(axi_lite_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")
    
    monitor = monitor_t::type_id::create("monitor", this);
    uvm_config_db#(axi_lite_config)::set(this, "monitor", "cfg", cfg);
    
    if(cfg.is_active == UVM_ACTIVE) begin
      driver    = driver_t::type_id::create("driver", this);
      uvm_config_db#(axi_lite_config)::set(this, "driver", "cfg", cfg);
      
      sequencer = sequencer_t::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if(cfg.is_active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass : axi_lite_agent
