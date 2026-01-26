// File: tb/tests/mac_tests/mac_sanity_test.sv
class mac_sanity_test extends eth_base_test;

  `uvm_component_utils(mac_sanity_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure_env();
    super.configure_env();
    
    // Disable DMA, enable only MAC
    cfg.enable_mac = 1;
    cfg.enable_dma = 0;
    cfg.enable_system_scoreboard = 0;
    
    // Make MAC agents active for standalone testing
    cfg.mac_cfg.gmii_tx_cfg.is_active = UVM_PASSIVE;
    cfg.mac_cfg.gmii_rx_cfg.is_active = UVM_ACTIVE;
  endfunction

  task run_phase(uvm_phase phase);
    gmii_burst_seq burst_seq;
    
    super.run_phase(phase);
    
    phase.raise_objection(this);
    
    // Configure MAC via backdoor (no AXI-Lite in MAC-only mode)
    configure_mac_backdoor();
    
    // Send packets via GMII
    burst_seq = gmii_burst_seq::type_id::create("burst_seq");
    burst_seq.num_packets = 5;
    burst_seq.start(env.mac_env_h.gmii_rx_agent.sequencer);
    
    #5us;
    
    phase.drop_objection(this);
  endtask

  task configure_mac_backdoor();
    // Use hierarchical path or force
    `uvm_info("MAC_TEST", "Configuring MAC via backdoor", UVM_MEDIUM)
    // Example: force tb_top.dut.mac.enable_rx = 1'b1;
  endtask

endclass : mac_sanity_test
