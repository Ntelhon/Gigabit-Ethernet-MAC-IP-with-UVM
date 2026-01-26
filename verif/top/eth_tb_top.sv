// File: tb/top/eth_tb_top.sv
module eth_tb_top;

  import uvm_pkg::*;
  import eth_test_pkg::*;
  
  // Clock and reset
  logic clk_125m;
  logic clk_axi;
  logic rst_n;
  
  // Interfaces
  axi_stream_if#(32,1,1,1) axis_mac_tx_if(clk_axi, rst_n);
  axi_stream_if#(32,1,1,1) axis_mac_rx_if(clk_axi, rst_n);
  axi4_if#(32,64,4,1)      axi4_mem_if(clk_axi, rst_n);
  axi_lite_if#(32,32)      axi_lite_if(clk_axi, rst_n);
  gmii_if                  gmii_if(clk_125m, clk_125m, rst_n);
  
  // Clock generation
  initial begin
    clk_125m = 0;
    forever #4ns clk_125m = ~clk_125m;  // 125 MHz
  end
  
  initial begin
    clk_axi = 0;
    forever #5ns clk_axi = ~clk_axi;  // 100 MHz
  end
  
  // Reset generation
  initial begin
    rst_n = 0;
    #100ns;
    rst_n = 1;
  end
  
  // DUT instantiation (placeholder - connect to actual RTL)
  // eth_controller_wrapper dut (
  //   .clk_mac(clk_125m),
  //   .clk_axi(clk_axi),
  //   .rst_n(rst_n),
  //   // AXI-Lite
  //   .s_axi_lite_awaddr(axi_lite_if.awaddr),
  //   ...
  //   // AXI-Stream MAC TX
  //   .m_axis_mac_tx_tdata(axis_mac_tx_if.tdata),
  //   ...
  //   // GMII
  //   .gmii_tx_en(gmii_if.tx_en),
  //   ...
  // );
  
  // Interface registration
  initial begin
    uvm_config_db#(virtual axi_stream_if#(32,1,1,1))::set(null, "*.mac_env_h.tx_stream_agent*", "vif", axis_mac_tx_if);
    uvm_config_db#(virtual axi_stream_if#(32,1,1,1))::set(null, "*.mac_env_h.rx_stream_agent*", "vif", axis_mac_rx_if);
    uvm_config_db#(virtual axi_stream_if#(32,1,1,1))::set(null, "*.dma_env_h.axis_tx_agent*", "vif", axis_mac_rx_if);
    uvm_config_db#(virtual axi_stream_if#(32,1,1,1))::set(null, "*.dma_env_h.axis_rx_agent*", "vif", axis_mac_tx_if);
    
    uvm_config_db#(virtual axi4_if#(32,64,4,1))::set(null, "*.dma_env_h.axi4_agent*", "vif", axi4_mem_if);
    uvm_config_db#(virtual axi_lite_if#(32,32))::set(null, "*.axi_lite_agent_h*", "vif", axi_lite_if);
    
    uvm_config_db#(virtual gmii_if)::set(null, "*.mac_env_h.gmii_tx_agent*", "vif", gmii_if);
    uvm_config_db#(virtual gmii_if)::set(null, "*.mac_env_h.gmii_rx_agent*", "vif", gmii_if);
    
    // Run test
    run_test();
  end
  
  // Waveform dumping
  initial begin
    $fsdbDumpvars(0, eth_tb_top);
    // Or: $dumpfile("waves.vcd"); $dumpvars(0, eth_tb_top);
  end

endmodule : eth_tb_top
