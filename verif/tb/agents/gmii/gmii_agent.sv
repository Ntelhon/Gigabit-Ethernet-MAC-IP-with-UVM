// File: tb/agents/gmii/gmii_agent.sv
class gmii_agent extends uvm_agent;

  `uvm_component_utils(gmii_agent)

  gmii_driver    driver;
  gmii_monitor   monitor;
  gmii_sequencer sequencer;
  
  gmii_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(gmii_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")
    
    monitor = gmii_monitor::type_id::create("monitor", this);
    
    if(cfg.is_active == UVM_ACTIVE) begin
      driver    = gmii_driver::type_id::create("driver", this);
      sequencer = gmii_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if(cfg.is_active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass : gmii_agent
