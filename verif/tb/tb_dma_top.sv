//==============================================================================
// Module: tb_dma_top
// Description: UVM testbench top module for Ethernet Controller with DMA
//
// Purpose:
//   Top-level testbench that instantiates the eth_controller_top DUT which
//   includes both MAC and DMA functionality.
//
// Components:
//   - Clock generators (125 MHz GMII, 100 MHz AXI)
//   - Reset generation
//   - DUT instantiation (eth_controller_top)
//   - Interface instantiation (GMII, AXI-Lite, AXI-Stream, AXI-MM)
//   - AXI-MM Memory Model
//   - UVM configuration and test launch
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//   - No DPI
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`timescale 1ns/1ps

module tb_dma_top;

    //==========================================================================
    // Import Packages
    //==========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import gmii_agent_pkg::*;
    import axi_lite_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import axi_mm_agent_pkg::*;
    import eth_scoreboard_pkg::*;
    import mac_env_pkg::*;
    import mac_test_pkg::*;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter DMA_ENABLE = 1;
    parameter AXI_ADDR_WIDTH = 32;
    parameter AXI_DATA_WIDTH = 32;
    parameter AXI_MM_DATA_WIDTH = 64;
    parameter DESC_COUNT = 16;
    parameter BUF_SIZE = 2048;

    //==========================================================================
    // Clock and Reset Signals
    //==========================================================================
    
    // GMII clock (125 MHz for 1 Gbps)
    logic gmii_clk;
    
    // AXI clock (100 MHz typical)
    logic axi_clk;
    
    // Resets (active high)
    logic gmii_rst;
    logic axi_rst;

    //==========================================================================
    // Clock Generation
    //==========================================================================
    
    // GMII clock: 125 MHz (8 ns period)
    initial begin
        gmii_clk = 0;
        forever #4ns gmii_clk = ~gmii_clk;
    end
    
    // AXI clock: 100 MHz (10 ns period)
    initial begin
        axi_clk = 0;
        forever #5ns axi_clk = ~axi_clk;
    end

    //==========================================================================
    // Reset Generation
    //==========================================================================
    
    initial begin
        gmii_rst = 1;
        axi_rst  = 1;
        
        // Hold reset for 100 ns
        #100ns;
        
        // Deassert resets synchronously
        @(posedge gmii_clk);
        gmii_rst = 0;
        
        @(posedge axi_clk);
        axi_rst = 0;
    end

    //==========================================================================
    // Interface Instantiation
    //==========================================================================
    
    // GMII interface
    gmii_if gmii_vif(
        .tx_clk(gmii_clk),
        .rx_clk(gmii_clk)
    );
    
    // AXI-Lite interface
    axi_lite_if #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) axi_vif(
        .aclk(axi_clk),
        .aresetn(~axi_rst)
    );

    // AXI-Stream interface (for non-DMA TX and RX)
    axi_stream_if axis_vif(
        .aclk(axi_clk),
        .aresetn(~axi_rst)
    );

    // AXI-MM interface (for DMA memory access)
    axi_mm_if #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_MM_DATA_WIDTH),
        .ID_WIDTH(4)
    ) axi_mm_vif(
        .aclk(axi_clk),
        .aresetn(~axi_rst)
    );

    //==========================================================================
    // DMA Internal Signals (when DMA_ENABLE=1, these are internal)
    // For non-DMA mode, these connect to axis_vif
    //==========================================================================
    
    // TX AXI-Stream (to MAC)
    wire [7:0]  tx_axis_tdata;
    wire        tx_axis_tvalid;
    wire        tx_axis_tlast;
    wire        tx_axis_tuser;
    wire        tx_axis_tready;
    
    // RX AXI-Stream (from MAC)
    wire [7:0]  rx_axis_tdata;
    wire        rx_axis_tvalid;
    wire        rx_axis_tlast;
    wire        rx_axis_tuser;
    wire        rx_axis_tready;
    
    // Interrupts
    wire        mac_irq;
    wire        dma_irq;

    //==========================================================================
    // DUT Instantiation - eth_controller_top (MAC + DMA)
    //==========================================================================
    
    eth_controller_top #(
        .DMA_ENABLE        (DMA_ENABLE),
        .AXI_ADDR_WIDTH    (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH    (AXI_DATA_WIDTH),
        .AXI_MM_DATA_WIDTH (AXI_MM_DATA_WIDTH),
        .DESC_COUNT        (DESC_COUNT),
        .BUF_SIZE          (BUF_SIZE),
        .TX_FIFO_DEPTH     (12),  // 2^12 = 4096 entries
        .RX_FIFO_DEPTH     (12)   // 2^12 = 4096 entries
    ) dut (
        //------------------------------------------------------------------
        // System Clock Domain
        //------------------------------------------------------------------
        .sys_clk        (axi_clk),
        .sys_rst_n      (~axi_rst),
        
        //------------------------------------------------------------------
        // GMII TX Clock Domain
        //------------------------------------------------------------------
        .gtx_clk        (gmii_clk),
        .gtx_rst_n      (~gmii_rst),
        
        //------------------------------------------------------------------
        // GMII RX Clock Domain
        //------------------------------------------------------------------
        .rx_clk         (gmii_clk),
        .rx_rst_n       (~gmii_rst),
        
        //------------------------------------------------------------------
        // AXI-Lite Register Interface
        //------------------------------------------------------------------
        .s_axi_awaddr   (axi_vif.awaddr),
        .s_axi_awvalid  (axi_vif.awvalid),
        .s_axi_awready  (axi_vif.awready),
        .s_axi_wdata    (axi_vif.wdata),
        .s_axi_wstrb    (axi_vif.wstrb),
        .s_axi_wvalid   (axi_vif.wvalid),
        .s_axi_wready   (axi_vif.wready),
        .s_axi_bresp    (axi_vif.bresp),
        .s_axi_bvalid   (axi_vif.bvalid),
        .s_axi_bready   (axi_vif.bready),
        .s_axi_araddr   (axi_vif.araddr),
        .s_axi_arvalid  (axi_vif.arvalid),
        .s_axi_arready  (axi_vif.arready),
        .s_axi_rdata    (axi_vif.rdata),
        .s_axi_rresp    (axi_vif.rresp),
        .s_axi_rvalid   (axi_vif.rvalid),
        .s_axi_rready   (axi_vif.rready),
        
        //------------------------------------------------------------------
        // AXI-MM Master Interface (DMA Memory Access)
        //------------------------------------------------------------------
        .m_axi_awid     (axi_mm_vif.awid),
        .m_axi_awaddr   (axi_mm_vif.awaddr),
        .m_axi_awlen    (axi_mm_vif.awlen),
        .m_axi_awsize   (axi_mm_vif.awsize),
        .m_axi_awburst  (axi_mm_vif.awburst),
        .m_axi_awvalid  (axi_mm_vif.awvalid),
        .m_axi_awready  (axi_mm_vif.awready),
        .m_axi_wdata    (axi_mm_vif.wdata),
        .m_axi_wstrb    (axi_mm_vif.wstrb),
        .m_axi_wlast    (axi_mm_vif.wlast),
        .m_axi_wvalid   (axi_mm_vif.wvalid),
        .m_axi_wready   (axi_mm_vif.wready),
        .m_axi_bid      (axi_mm_vif.bid),
        .m_axi_bresp    (axi_mm_vif.bresp),
        .m_axi_bvalid   (axi_mm_vif.bvalid),
        .m_axi_bready   (axi_mm_vif.bready),
        .m_axi_arid     (axi_mm_vif.arid),
        .m_axi_araddr   (axi_mm_vif.araddr),
        .m_axi_arlen    (axi_mm_vif.arlen),
        .m_axi_arsize   (axi_mm_vif.arsize),
        .m_axi_arburst  (axi_mm_vif.arburst),
        .m_axi_arvalid  (axi_mm_vif.arvalid),
        .m_axi_arready  (axi_mm_vif.arready),
        .m_axi_rid      (axi_mm_vif.rid),
        .m_axi_rdata    (axi_mm_vif.rdata),
        .m_axi_rresp    (axi_mm_vif.rresp),
        .m_axi_rlast    (axi_mm_vif.rlast),
        .m_axi_rvalid   (axi_mm_vif.rvalid),
        .m_axi_rready   (axi_mm_vif.rready),
        
        //------------------------------------------------------------------
        // AXI-Stream TX Interface (when DMA_ENABLE=0)
        //------------------------------------------------------------------
        .tx_axis_tdata  (tx_axis_tdata),
        .tx_axis_tvalid (tx_axis_tvalid),
        .tx_axis_tlast  (tx_axis_tlast),
        .tx_axis_tuser  (tx_axis_tuser),
        .tx_axis_tready (tx_axis_tready),
        
        //------------------------------------------------------------------
        // AXI-Stream RX Interface (when DMA_ENABLE=0)
        //------------------------------------------------------------------
        .rx_axis_tdata  (rx_axis_tdata),
        .rx_axis_tvalid (rx_axis_tvalid),
        .rx_axis_tlast  (rx_axis_tlast),
        .rx_axis_tuser  (rx_axis_tuser),
        .rx_axis_tready (rx_axis_tready),
        
        //------------------------------------------------------------------
        // GMII TX Interface (MAC to PHY)
        //------------------------------------------------------------------
        .gmii_txd       (gmii_vif.txd),
        .gmii_tx_en     (gmii_vif.tx_en),
        .gmii_tx_er     (gmii_vif.tx_er),
        
        //------------------------------------------------------------------
        // GMII RX Interface (PHY to MAC)
        //------------------------------------------------------------------
        .gmii_rxd       (gmii_vif.rxd),
        .gmii_rx_dv     (gmii_vif.rx_dv),
        .gmii_rx_er     (gmii_vif.rx_er),
        
        //------------------------------------------------------------------
        // GMII Control Signals
        //------------------------------------------------------------------
        .gmii_col       (1'b0),
        .gmii_crs       (1'b0),
        
        //------------------------------------------------------------------
        // Interrupts
        //------------------------------------------------------------------
        .mac_irq        (mac_irq),
        .dma_irq        (dma_irq)
    );

    //==========================================================================
    // AXI-Stream Interface Connection (Non-DMA mode)
    //==========================================================================
    generate
        if (!DMA_ENABLE) begin : axis_conn
            // Connect AXI-Stream interface for non-DMA operation
            assign tx_axis_tdata  = axis_vif.tdata;
            assign tx_axis_tvalid = axis_vif.tvalid;
            assign tx_axis_tlast  = axis_vif.tlast;
            assign tx_axis_tuser  = axis_vif.tuser;
            assign axis_vif.tready = tx_axis_tready;
            
            assign axis_vif.rx_tdata  = rx_axis_tdata;
            assign axis_vif.rx_tvalid = rx_axis_tvalid;
            assign axis_vif.rx_tlast  = rx_axis_tlast;
            assign axis_vif.rx_tuser  = rx_axis_tuser;
            assign rx_axis_tready = axis_vif.rx_tready;
        end else begin : dma_axis
            // In DMA mode, AXI-Stream is internal - tie off external
            assign axis_vif.tready = 1'b1;
            assign axis_vif.rx_tdata  = 8'h0;
            assign axis_vif.rx_tvalid = 1'b0;
            assign axis_vif.rx_tlast  = 1'b0;
            assign axis_vif.rx_tuser  = 1'b0;
        end
    endgenerate

    //==========================================================================
    // Interface Binding to UVM Config DB
    //==========================================================================
    
    initial begin
        // Set GMII interface
        uvm_config_db#(virtual gmii_if)::set(
            null, "uvm_test_top.env.gmii_agt*", "vif", gmii_vif
        );
        
        // Set AXI-Lite interface
        uvm_config_db#(virtual axi_lite_if#(32,32))::set(
            null, "uvm_test_top.env.axi_lite_agt*", "vif", axi_vif
        );
        
        // Set AXI-Stream interface
        uvm_config_db#(virtual axi_stream_if)::set(
            null, "uvm_test_top.env.axis_agt*", "vif", axis_vif
        );
        
        // Set AXI-MM interface (for DMA memory access)
        uvm_config_db#(virtual axi_mm_if#(32,64,4))::set(
            null, "uvm_test_top.env.axi_mm_agt*", "vif", axi_mm_vif
        );
        
        // Global access paths
        uvm_config_db#(virtual gmii_if)::set(
            null, "*", "gmii_vif", gmii_vif
        );
        
        uvm_config_db#(virtual axi_lite_if#(32,32))::set(
            null, "*", "axi_vif", axi_vif
        );
        
        uvm_config_db#(virtual axi_stream_if)::set(
            null, "*", "axis_vif", axis_vif
        );
        
        uvm_config_db#(virtual axi_mm_if#(32,64,4))::set(
            null, "*", "axi_mm_vif", axi_mm_vif
        );
        
        // Set DMA enable flag
        uvm_config_db#(bit)::set(null, "*", "dma_enable", DMA_ENABLE);
    end

    //==========================================================================
    // UVM Test Launch
    //==========================================================================
    
    initial begin
        // Print simulation start
        $display("==============================================================================");
        $display("Gigabit Ethernet Controller with DMA - UVM Testbench");
        $display("DMA_ENABLE: %0d", DMA_ENABLE);
        $display("Simulator: Vivado xsim");
        $display("UVM Version: 1.2");
        $display("==============================================================================");
        
        // Run UVM test
        run_test();
    end

    //==========================================================================
    // Simulation Timeout (Safety)
    //==========================================================================
    
    initial begin
        #50ms;  // Extended timeout for DMA tests
        $display("==============================================================================");
        $display("SIMULATION TIMEOUT - 50ms reached");
        $display("==============================================================================");
        $finish;
    end

    //==========================================================================
    // Interrupt Monitoring
    //==========================================================================
    
    always @(posedge mac_irq) begin
        $display("[IRQ] @%0t: MAC interrupt asserted", $time);
    end
    
    always @(posedge dma_irq) begin
        $display("[IRQ] @%0t: DMA interrupt asserted", $time);
    end

    //==========================================================================
    // Debug Monitoring (enabled with +define+DEBUG)
    //==========================================================================
    `ifdef DEBUG
    int gmii_byte_cnt = 0;
    bit in_gmii_frame = 0;
    
    always @(posedge gmii_clk) begin
        if (gmii_vif.tx_en) begin
            if (!in_gmii_frame) begin
                $display("[GMII_TX] @%0t: FRAME START", $time);
                in_gmii_frame = 1;
                gmii_byte_cnt = 0;
            end
            $display("[GMII_TX] @%0t: TX_EN=1 TXD=%02h (byte %0d)", 
                     $time, gmii_vif.txd, gmii_byte_cnt);
            gmii_byte_cnt++;
        end else if (in_gmii_frame) begin
            $display("[GMII_TX] @%0t: FRAME END (total %0d bytes)", $time, gmii_byte_cnt);
            in_gmii_frame = 0;
        end
    end
    
    // Monitor AXI-MM transactions
    always @(posedge axi_clk) begin
        if (axi_mm_vif.awvalid && axi_mm_vif.awready) begin
            $display("[AXI_MM] @%0t: Write Addr: 0x%h, Len: %0d", 
                     $time, axi_mm_vif.awaddr, axi_mm_vif.awlen + 1);
        end
        if (axi_mm_vif.arvalid && axi_mm_vif.arready) begin
            $display("[AXI_MM] @%0t: Read Addr: 0x%h, Len: %0d", 
                     $time, axi_mm_vif.araddr, axi_mm_vif.arlen + 1);
        end
    end
    `endif

endmodule : tb_dma_top
