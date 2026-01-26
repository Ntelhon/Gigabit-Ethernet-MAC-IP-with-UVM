// File: tb/env/eth_controller/eth_virtual_sequencer.sv
class eth_virtual_sequencer extends uvm_sequencer;

  `uvm_component_utils(eth_virtual_sequencer)

  // ==========================================
  // SYSTEM-LEVEL SEQUENCER (Wrapper boundary)
  // ==========================================
  axi_lite_sequencer#(32,32) axi_lite_sqr;
  
  // ==========================================
  // MAC-side sequencers
  // ==========================================
  gmii_sequencer             gmii_rx_sqr;  // Drive packets into MAC from PHY
  
  // ==========================================
  // DMA-side sequencers (none - DMA drives itself)
  // ==========================================
  // Note: In real tests, we might add descriptor programming sequencers here
  
  // ==========================================
  // Reference to memory model (for verification)
  // ==========================================
  memory_model mem;
  
  // ==========================================
  // Configuration access
  // ==========================================
  eth_controller_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(eth_controller_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config not found")
  endfunction

endclass : eth_virtual_sequencer
