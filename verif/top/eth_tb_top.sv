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
  eth_controller_top #(
    // DMA Enable
    .DMA_ENABLE(1),

    // AXI4-Lite parameters
    .AXI_ADDR_WIDTH(32),

    // MAC parameters
    .MAC_TX_FIFO_DEPTH(16),
    .MAC_RX_FIFO_DEPTH(16),
    .MAC_MIN_FRAME_SIZE(64),
    .MAC_MAX_FRAME_SIZE(1518),
    .MAC_IFG_BYTES(12),

    // DMA parameters
    .DMA_ADDR_WIDTH(32),
    .DMA_DATA_WIDTH(64),
    .DMA_MAX_BURST_LEN(16),
    .DMA_TX_FIFO_DEPTH(32),
    .DMA_RX_FIFO_DEPTH(32)
  ) dut (
    // System signals
    .sys_clk(clk_axi),
    .sys_rst_n(rst_n),
    .gtx_clk(clk_125m),
    .rx_clk(clk_125m),

    // AXI-Lite Interface
    .s_axi_awaddr(axi_lite_if.awaddr),
    .s_axi_awvalid(axi_lite_if.awvalid),
    .s_axi_awready(axi_lite_if.awready),
    .s_axi_wdata(axi_lite_if.wdata),
    .s_axi_wstrb(axi_lite_if.wstrb),
    .s_axi_wvalid(axi_lite_if.wvalid),
    .s_axi_wready(axi_lite_if.wready),
    .s_axi_bresp(axi_lite_if.bresp),
    .s_axi_bvalid(axi_lite_if.bvalid),
    .s_axi_bready(axi_lite_if.bready),
    .s_axi_araddr(axi_lite_if.araddr),
    .s_axi_arvalid(axi_lite_if.arvalid),
    .s_axi_arready(axi_lite_if.arready),
    .s_axi_rdata(axi_lite_if.rdata),
    .s_axi_rresp(axi_lite_if.rresp),
    .s_axi_rvalid(axi_lite_if.rvalid),
    .s_axi_rready(axi_lite_if.rready),

    // GMII
    .gmii_txd(gmii_if.txd),
    .gmii_tx_en(gmii_if.tx_en),
    .gmii_tx_er(gmii_if.tx_er),

    .gmii_rxd(gmii_if.rxd),
    .gmii_rx_dv(gmii_if.rx_dv),
    .gmii_rx_er(gmii_if.rx_er),

    // AXI-Stream MAC TX
    .s_axis_tx_tdata(axis_mac_tx_if.tdata),
    .s_axis_tx_tvalid(axis_mac_tx_if.tvalid),
    .s_axis_tx_tlast(axis_mac_tx_if.tlast),
    .s_axis_tx_tuser(axis_mac_tx_if.tuser),
    .s_axis_tx_tready(axis_mac_tx_if.tready),

    // AXI-Stream MAC RX
    .m_axis_rx_tdata(axis_mac_rx_if.tdata),
    .m_axis_rx_tvalid(axis_mac_rx_if.tvalid),
    .m_axis_rx_tlast(axis_mac_rx_if.tlast),
    .m_axis_rx_tuser(axis_mac_rx_if.tuser),
    .m_axis_rx_tready(axis_mac_rx_if.tready),

    // AXI4 Memory Master Interface
    // Write Address Channel
    .m_axi_awvalid(axi4_mem_if.awvalid),
    .m_axi_awready(axi4_mem_if.awready),
    .m_axi_awaddr(axi4_mem_if.awaddr),
    .m_axi_awlen(axi4_mem_if.awlen),
    .m_axi_awsize(axi4_mem_if.awsize),
    .m_axi_awburst(axi4_mem_if.awburst),
    .m_axi_awid(axi4_mem_if.awid),
    // Write Data Channel
    .m_axi_wvalid(axi4_mem_if.wvalid),
    .m_axi_wready(axi4_mem_if.wready),
    .m_axi_wdata(axi4_mem_if.wdata),
    .m_axi_wstrb(axi4_mem_if.wstrb),
    .m_axi_wlast(axi4_mem_if.wlast),
    // Write Response Channel
    .m_axi_bvalid(axi4_mem_if.bvalid),
    .m_axi_bready(axi4_mem_if.bready),
    .m_axi_bresp(axi4_mem_if.bresp),
    .m_axi_bid(axi4_mem_if.bid),
    // Read Address Channel
    .m_axi_arvalid(axi4_mem_if.arvalid),
    .m_axi_arready(axi4_mem_if.arready),
    .m_axi_araddr(axi4_mem_if.araddr),
    .m_axi_arlen(axi4_mem_if.arlen),
    .m_axi_arsize(axi4_mem_if.arsize),
    .m_axi_arburst(axi4_mem_if.arburst),
    .m_axi_arid(axi4_mem_if.arid),
    // Read Data Channel
    .m_axi_rvalid(axi4_mem_if.rvalid),
    .m_axi_rready(axi4_mem_if.rready),
    .m_axi_rdata(axi4_mem_if.rdata),
    .m_axi_rresp(axi4_mem_if.rresp),
    .m_axi_rlast(axi4_mem_if.rlast),
    .m_axi_rid(axi4_mem_if.rid),

    // Interrupt
    .mac_irq(mac_irq),
    .dma_irq(dma_irq)
  );
  
  // Interface registration
  initial begin
    uvm_config_db#(virtual axi_stream_if#(8,1,1,1))::set(null, "*.mac_env_h.tx_stream_agent*", "vif", axis_mac_tx_if);
    uvm_config_db#(virtual axi_stream_if#(8,1,1,1))::set(null, "*.mac_env_h.rx_stream_agent*", "vif", axis_mac_rx_if);
    uvm_config_db#(virtual axi_stream_if#(8,1,1,1))::set(null, "*.dma_env_h.axis_tx_agent*", "vif", axis_mac_rx_if);
    uvm_config_db#(virtual axi_stream_if#(8,1,1,1))::set(null, "*.dma_env_h.axis_rx_agent*", "vif", axis_mac_tx_if);
    
    uvm_config_db#(virtual axi4_if#(32,64,4,1))::set(null, "*.dma_env_h.axi4_master_agent*", "vif", axi4_mem_if);
    uvm_config_db#(virtual axi_lite_if#(32,32))::set(null, "*.axi_lite_agent_h*", "vif", axi_lite_if);
    
    uvm_config_db#(virtual gmii_if)::set(null, "*.mac_env_h.gmii_tx_agent*", "vif", gmii_if);
    uvm_config_db#(virtual gmii_if)::set(null, "*.mac_env_h.gmii_rx_agent*", "vif", gmii_if);
    
    // Run test
    run_test();
  end
  
  // Waveform dumping
  initial begin
    // $fsdbDumpvars(0, eth_tb_top);
    // Or: $dumpfile("waves.vcd"); $dumpvars(0, eth_tb_top);
  end

endmodule : eth_tb_top
