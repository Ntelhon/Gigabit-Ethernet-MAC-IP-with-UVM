// File: tb/tests/base/eth_base_test.sv
class eth_base_test extends uvm_test;

  `uvm_component_utils(eth_base_test)

  // Environment
  eth_controller_env env;
  eth_controller_config cfg;
  
  // Timeout
  int timeout_cycles = 100000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Create configuration
    cfg = eth_controller_config::type_id::create("cfg");
    configure_env();
    
    // Set config in database
    uvm_config_db#(eth_controller_config)::set(this, "env", "cfg", cfg);
    
    // Create environment
    env = eth_controller_env::type_id::create("env", this);
    
    // Set verbosity
    uvm_top.set_report_verbosity_level_hier(UVM_MEDIUM);
  endfunction

  virtual function void configure_env();
    // Default: Enable both MAC and DMA
    cfg.enable_mac = 1;
    cfg.enable_dma = 1;
    cfg.enable_system_scoreboard = 1;
    
    // MAC configuration
    cfg.mac_cfg.mac_address = 48'h001122334455;
    
    // DMA configuration
    cfg.dma_cfg.tx_desc_base_addr = 32'h1000_0000;
    cfg.dma_cfg.rx_desc_base_addr = 32'h2000_0000;
    cfg.dma_cfg.buffer_base_addr  = 32'h3000_0000;
  endfunction

  task run_phase(uvm_phase phase);
    // Watchdog timer
    fork
      begin
        phase.phase_done.set_drain_time(this, 10us);
      end
      begin
        #(timeout_cycles * 10ns);
        `uvm_fatal("TIMEOUT", "Test timeout!")
      end
    join_none
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server svr;
    super.report_phase(phase);
    
    svr = uvm_report_server::get_server();
    
    `uvm_info("TEST_RESULT", "======================================", UVM_NONE)
    if(svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) == 0) begin
      `uvm_info("TEST_RESULT", "          TEST PASSED", UVM_NONE)
    end else begin
      `uvm_info("TEST_RESULT", "          TEST FAILED", UVM_NONE)
    end
    `uvm_info("TEST_RESULT", "======================================", UVM_NONE)
  endfunction

endclass : eth_base_test
