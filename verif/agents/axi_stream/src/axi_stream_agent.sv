// File: tb/agents/axi_stream/axi_stream_agent.sv
class axi_stream_agent #(
  int DATA_WIDTH = 32,
  int USER_WIDTH = 1,
  int DEST_WIDTH = 1,
  int ID_WIDTH   = 1
) extends uvm_agent;

  `uvm_component_param_utils(axi_stream_agent#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH))

  typedef axi_stream_driver#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH)    driver_t;
  typedef axi_stream_monitor#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH)   monitor_t;
  typedef axi_stream_sequencer#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH) sequencer_t;

  driver_t    driver;
  monitor_t   monitor;
  sequencer_t sequencer;
  
  axi_stream_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(axi_stream_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")
    
    monitor = monitor_t::type_id::create("monitor", this);
    uvm_config_db#(axi_stream_config)::set(this, "monitor", "cfg", cfg);
    
    if(cfg.is_active == UVM_ACTIVE) begin
      driver    = driver_t::type_id::create("driver", this);
      uvm_config_db#(axi_stream_config)::set(this, "driver", "cfg", cfg);
      
      sequencer = sequencer_t::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if(cfg.is_active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass : axi_stream_agent
