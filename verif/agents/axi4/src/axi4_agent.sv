// File: tb/agents/axi4/axi4_agent.sv
class axi4_agent #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 64,
  int ID_WIDTH   = 4,
  int USER_WIDTH = 1
) extends uvm_agent;

  `uvm_component_param_utils(axi4_agent#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH))

  typedef axi4_driver#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH)    driver_t;
  typedef axi4_monitor#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH)   monitor_t;
  typedef axi4_sequencer#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH) sequencer_t;

  driver_t    driver;
  monitor_t   monitor;
  sequencer_t sequencer;
  
  axi4_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(axi4_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")
    
    monitor = monitor_t::type_id::create("monitor", this);
    
    if(cfg.is_active == UVM_ACTIVE) begin
      driver    = driver_t::type_id::create("driver", this);
      sequencer = sequencer_t::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if(cfg.is_active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass : axi4_agent
