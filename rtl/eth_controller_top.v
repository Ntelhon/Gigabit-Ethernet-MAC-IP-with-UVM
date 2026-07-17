//==============================================================================
// File: eth_controller_top.v
// Description: Ethernet Controller Top Module with Optional DMA
//
// Purpose:
//   Top-level module for the Ethernet Controller IP. Integrates:
//   - Gigabit Ethernet MAC (mac_top)
//   - Optional DMA subsystem (dma_top)
//   - Unified register block (eth_controller_regs)
//   - Interrupt controller (eth_controller_irq)
//
// Configuration:
//   DMA_ENABLE = 1: Full NIC-class architecture with scatter-gather DMA
//   DMA_ENABLE = 0: MAC-only mode with AXI-Stream interfaces exposed
//
// Interfaces:
//   - AXI4-Lite (32-bit): Configuration registers
//   - AXI4 Master (64-bit): Memory access for DMA (only when DMA_ENABLE=1)
//   - AXI-Stream TX (8-bit): Packet transmit (exposed when DMA_ENABLE=0)
//   - AXI-Stream RX (8-bit): Packet receive (exposed when DMA_ENABLE=0)
//   - GMII: PHY interface
//   - Interrupts: mac_irq, dma_irq
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_controller_top #(
    //--------------------------------------------------------------------------
    // Feature Configuration
    //--------------------------------------------------------------------------
    parameter DMA_ENABLE     = 1,       // Enable DMA subsystem (0=MAC only)

    //==========================================================================
    // AXI4-Lite Register Interface Parameters
    //==========================================================================
    parameter AXI_ADDR_WIDTH    = 10,        // Address width (min 10 for DMA space)
    
    //--------------------------------------------------------------------------
    // DMA Parameters (ignored when DMA_ENABLE=0)
    //--------------------------------------------------------------------------
    parameter DMA_ADDR_WIDTH      = 64,      // AXI address width (32 or 64)
    parameter DMA_DATA_WIDTH      = 64,      // AXI-MM data width
    parameter DMA_MAX_BURST_LEN   = 16,      // Max AXI burst length
    parameter DMA_TX_FIFO_DEPTH   = 2048,    // TX DMA FIFO depth
    parameter DMA_RX_FIFO_DEPTH   = 4096,    // RX DMA FIFO depth

    //--------------------------------------------------------------------------
    // MAC Parameters
    //--------------------------------------------------------------------------
    parameter MAC_TX_FIFO_DEPTH     = 2048, // MAC TX FIFO depth
    parameter MAC_RX_FIFO_DEPTH     = 2048, // MAC RX FIFO depth
    parameter MAC_MIN_FRAME_SIZE    = 64,   // Minimum frame size (bytes)
    parameter MAC_MAX_FRAME_SIZE    = 1518, // Maximum frame size (bytes)
    parameter MAC_IFG_BYTES         = 12    // Inter-frame gap (bytes)
)(
    //--------------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------------
    input  wire                         sys_clk,        // System clock (AXI)
    input  wire                         sys_rst_n,      // System reset (active low)
    
    // GMII clocks
    input  wire                         gtx_clk,        // TX clock (125 MHz)
    input  wire                         rx_clk,         // RX clock from PHY
    
    //--------------------------------------------------------------------------
    // AXI4-Lite Configuration Interface
    //--------------------------------------------------------------------------
    // Write Address Channel
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,   // 10-bit: 0x000-0x3FF
    input  wire [2:0]                   s_axi_awprot,
    
    // Write Data Channel
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,
    input  wire [32-1:0]                s_axi_wdata,
    input  wire [32/8-1:0]              s_axi_wstrb,
    
    // Write Response Channel
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,
    output wire [1:0]                   s_axi_bresp,
    
    // Read Address Channel
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [2:0]                   s_axi_arprot,
    
    // Read Data Channel
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready,
    output wire [32-1:0]                s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    
    //--------------------------------------------------------------------------
    // AXI4 Master Interface (DMA - Memory Access)
    // Only active when DMA_ENABLE=1
    //--------------------------------------------------------------------------
    // Write Address Channel
    output wire                         m_axi_awvalid,
    input  wire                         m_axi_awready,
    output wire [DMA_ADDR_WIDTH-1:0]    m_axi_awaddr,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output wire [1:0]                   m_axi_awburst,
    output wire [3:0]                   m_axi_awid,
    
    // Write Data Channel
    output wire                         m_axi_wvalid,
    input  wire                         m_axi_wready,
    output wire [DMA_DATA_WIDTH-1:0]    m_axi_wdata,
    output wire [DMA_DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output wire                         m_axi_wlast,
    
    // Write Response Channel
    input  wire                         m_axi_bvalid,
    output wire                         m_axi_bready,
    input  wire [1:0]                   m_axi_bresp,
    input  wire [3:0]                   m_axi_bid,
    
    // Read Address Channel
    output wire                         m_axi_arvalid,
    input  wire                         m_axi_arready,
    output wire [DMA_ADDR_WIDTH-1:0]    m_axi_araddr,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire [3:0]                   m_axi_arid,
    
    // Read Data Channel
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready,
    input  wire [DMA_DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire [3:0]                   m_axi_rid,
    
    //--------------------------------------------------------------------------
    // AXI-Stream TX Interface (exposed when DMA_ENABLE=0)
    //--------------------------------------------------------------------------
    input  wire                         s_axis_tx_tvalid,
    output wire                         s_axis_tx_tready,
    input  wire [7:0]                   s_axis_tx_tdata,
    input  wire                         s_axis_tx_tlast,
    input  wire                         s_axis_tx_tuser,    // SOF indicator
    
    //--------------------------------------------------------------------------
    // AXI-Stream RX Interface (exposed when DMA_ENABLE=0)
    //--------------------------------------------------------------------------
    output wire                         m_axis_rx_tvalid,
    input  wire                         m_axis_rx_tready,
    output wire [7:0]                   m_axis_rx_tdata,
    output wire                         m_axis_rx_tlast,
    output wire                         m_axis_rx_tuser,    // Error on last
    
    //--------------------------------------------------------------------------
    // GMII Interface
    //--------------------------------------------------------------------------
    output wire [7:0]                   gmii_txd,
    output wire                         gmii_tx_en,
    output wire                         gmii_tx_er,
    input  wire [7:0]                   gmii_rxd,
    input  wire                         gmii_rx_dv,
    input  wire                         gmii_rx_er,
    input  wire                         gmii_col,
    input  wire                         gmii_crs,

    //--------------------------------------------------------------------------
    // Interrupts
    //--------------------------------------------------------------------------
    output wire                         mac_irq,
    output wire                         dma_irq
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    //--------------------------------------------------------------------------
    // Register Interface Signals
    //--------------------------------------------------------------------------
    // MAC register interface
    wire        mac_awvalid, mac_awready;
    wire [7:0]  mac_awaddr;
    wire        mac_wvalid, mac_wready;
    wire [31:0] mac_wdata;
    wire [3:0]  mac_wstrb;
    wire        mac_bvalid, mac_bready;
    wire [1:0]  mac_bresp;
    wire        mac_arvalid, mac_arready;
    wire [7:0]  mac_araddr;
    wire        mac_rvalid, mac_rready;
    wire [31:0] mac_rdata;
    wire [1:0]  mac_rresp;
    
    // DMA register interface
    wire        dma_reg_awvalid, dma_reg_awready;
    wire [7:0]  dma_reg_awaddr;
    wire        dma_reg_wvalid, dma_reg_wready;
    wire [31:0] dma_reg_wdata;
    wire [3:0]  dma_reg_wstrb;
    wire        dma_reg_bvalid, dma_reg_bready;
    wire [1:0]  dma_reg_bresp;
    wire        dma_reg_arvalid, dma_reg_arready;
    wire [7:0]  dma_reg_araddr;
    wire        dma_reg_rvalid, dma_reg_rready;
    wire [31:0] dma_reg_rdata;
    wire [1:0]  dma_reg_rresp;
    
    //--------------------------------------------------------------------------
    // MAC Internal AXI-Stream Signals
    //--------------------------------------------------------------------------
    wire        mac_tx_axis_tvalid;
    wire        mac_tx_axis_tready;
    wire [7:0]  mac_tx_axis_tdata;
    wire        mac_tx_axis_tlast;
    wire        mac_tx_axis_tuser;
    
    wire        mac_rx_axis_tvalid;
    wire        mac_rx_axis_tready;
    wire [7:0]  mac_rx_axis_tdata;
    wire        mac_rx_axis_tlast;
    wire        mac_rx_axis_tuser;
    
    //--------------------------------------------------------------------------
    // DMA AXI-Stream Signals
    //--------------------------------------------------------------------------
    wire        dma_tx_axis_tvalid;
    wire        dma_tx_axis_tready;
    wire [7:0]  dma_tx_axis_tdata;
    wire        dma_tx_axis_tlast;
    wire        dma_tx_axis_tuser;
    
    wire        dma_rx_axis_tvalid;
    wire        dma_rx_axis_tready;
    wire [7:0]  dma_rx_axis_tdata;
    wire        dma_rx_axis_tlast;
    wire        dma_rx_axis_tuser;
    
    //--------------------------------------------------------------------------
    // Interrupt Signals
    //--------------------------------------------------------------------------
    wire        mac_irq_internal;
    wire        dma_irq_internal;

    //==========================================================================
    // Unified Register Block
    //==========================================================================
    eth_controller_regs #(
        .DMA_ENABLE (DMA_ENABLE),
        .ADDR_WIDTH (AXI_ADDR_WIDTH)
    ) u_regs (
        .clk            (sys_clk),
        .rst_n          (sys_rst_n),
        
        // Host AXI-Lite
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        
        // MAC interface
        .mac_awvalid    (mac_awvalid),
        .mac_awready    (mac_awready),
        .mac_awaddr     (mac_awaddr),
        .mac_wvalid     (mac_wvalid),
        .mac_wready     (mac_wready),
        .mac_wdata      (mac_wdata),
        .mac_wstrb      (mac_wstrb),
        .mac_bvalid     (mac_bvalid),
        .mac_bready     (mac_bready),
        .mac_bresp      (mac_bresp),
        .mac_arvalid    (mac_arvalid),
        .mac_arready    (mac_arready),
        .mac_araddr     (mac_araddr),
        .mac_rvalid     (mac_rvalid),
        .mac_rready     (mac_rready),
        .mac_rdata      (mac_rdata),
        .mac_rresp      (mac_rresp),
        
        // DMA interface
        .dma_awvalid    (dma_reg_awvalid),
        .dma_awready    (dma_reg_awready),
        .dma_awaddr     (dma_reg_awaddr),
        .dma_wvalid     (dma_reg_wvalid),
        .dma_wready     (dma_reg_wready),
        .dma_wdata      (dma_reg_wdata),
        .dma_wstrb      (dma_reg_wstrb),
        .dma_bvalid     (dma_reg_bvalid),
        .dma_bready     (dma_reg_bready),
        .dma_bresp      (dma_reg_bresp),
        .dma_arvalid    (dma_reg_arvalid),
        .dma_arready    (dma_reg_arready),
        .dma_araddr     (dma_reg_araddr),
        .dma_rvalid     (dma_reg_rvalid),
        .dma_rready     (dma_reg_rready),
        .dma_rdata      (dma_reg_rdata),
        .dma_rresp      (dma_reg_rresp)
    );

    //==========================================================================
    // Gigabit Ethernet MAC
    //==========================================================================
    mac_top #(
        .TX_FIFO_DEPTH  (MAC_TX_FIFO_DEPTH),
        .RX_FIFO_DEPTH  (MAC_RX_FIFO_DEPTH),
        .MIN_FRAME_SIZE (MAC_MIN_FRAME_SIZE),
        .MAX_FRAME_SIZE (MAC_MAX_FRAME_SIZE),
        .IFG_BYTES      (MAC_IFG_BYTES)
    ) u_mac (
        // Clocks and Reset
        .sys_clk        (sys_clk),
        .sys_rst_n      (sys_rst_n),
        .gtx_clk        (gtx_clk),
        .gtx_rst_n      (sys_rst_n),  // Assume same reset for GTX
        .rx_clk         (rx_clk),
        .rx_rst_n       (sys_rst_n),  // Assume same reset for RX
        
        // AXI-Lite Configuration
        .s_axi_awvalid  (mac_awvalid),
        .s_axi_awready  (mac_awready),
        .s_axi_awaddr   (mac_awaddr),
        .s_axi_wvalid   (mac_wvalid),
        .s_axi_wready   (mac_wready),
        .s_axi_wdata    (mac_wdata),
        .s_axi_wstrb    (mac_wstrb),
        .s_axi_bvalid   (mac_bvalid),
        .s_axi_bready   (mac_bready),
        .s_axi_bresp    (mac_bresp),
        .s_axi_arvalid  (mac_arvalid),
        .s_axi_arready  (mac_arready),
        .s_axi_araddr   (mac_araddr),
        .s_axi_rvalid   (mac_rvalid),
        .s_axi_rready   (mac_rready),
        .s_axi_rdata    (mac_rdata),
        .s_axi_rresp    (mac_rresp),
        
        // AXI-Stream TX (input to MAC)
        .tx_axis_tdata    (mac_tx_axis_tdata),
        .tx_axis_tvalid   (mac_tx_axis_tvalid),
        .tx_axis_tlast    (mac_tx_axis_tlast),
        .tx_axis_tuser    (mac_tx_axis_tuser),
        .tx_axis_tready   (mac_tx_axis_tready),

        // AXI-Stream RX (output from MAC)
        .rx_axis_tdata    (mac_rx_axis_tdata),
        .rx_axis_tvalid   (mac_rx_axis_tvalid),
        .rx_axis_tlast    (mac_rx_axis_tlast),
        .rx_axis_tuser    (mac_rx_axis_tuser),
        .rx_axis_tready   (mac_rx_axis_tready),

        // GMII Interface
        .gmii_txd       (gmii_txd),
        .gmii_tx_en     (gmii_tx_en),
        .gmii_tx_er     (gmii_tx_er),
        .gmii_rxd       (gmii_rxd),
        .gmii_rx_dv     (gmii_rx_dv),
        .gmii_rx_er     (gmii_rx_er),
        .gmii_col       (gmii_col),
        .gmii_crs       (gmii_crs),

        // Interrupt
        .irq        (mac_irq_internal)
    );

    //==========================================================================
    // DMA Subsystem (Conditional)
    //==========================================================================
    generate
        if (DMA_ENABLE) begin : gen_dma

            //------------------------------------------------------------------
            // Reset synchronizer for the DMA sys_clk domain
            // (async assert, sync de-assert). dma_top takes an asynchronous
            // rst_n and does NOT synchronize it internally, so give its flops
            // a clean, metastability-free reset release here.
            //------------------------------------------------------------------
            wire dma_rst_sync_n;
            rst_sync u_dma_rst_sync (
                .clk         (sys_clk),
                .async_rst_n (sys_rst_n),
                .rst_n       (dma_rst_sync_n)
            );
            
            dma_top #(
                .ADDR_WIDTH     (DMA_ADDR_WIDTH),
                .AXI_DATA_W     (DMA_DATA_WIDTH),
                .AXIS_DATA_W    (8),
                .MAX_BURST_LEN  (DMA_MAX_BURST_LEN),
                .TX_FIFO_DEPTH  (DMA_TX_FIFO_DEPTH),
                .RX_FIFO_DEPTH  (DMA_RX_FIFO_DEPTH)
            ) u_dma (
                .clk            (sys_clk),
                .rst_n          (dma_rst_sync_n),
                
                // AXI-Lite registers
                .s_axil_awvalid  (dma_reg_awvalid),
                .s_axil_awready  (dma_reg_awready),
                .s_axil_awaddr   (dma_reg_awaddr),
                .s_axil_wvalid   (dma_reg_wvalid),
                .s_axil_wready   (dma_reg_wready),
                .s_axil_wdata    (dma_reg_wdata),
                .s_axil_wstrb    (dma_reg_wstrb),
                .s_axil_bvalid   (dma_reg_bvalid),
                .s_axil_bready   (dma_reg_bready),
                .s_axil_bresp    (dma_reg_bresp),
                .s_axil_arvalid  (dma_reg_arvalid),
                .s_axil_arready  (dma_reg_arready),
                .s_axil_araddr   (dma_reg_araddr),
                .s_axil_rvalid   (dma_reg_rvalid),
                .s_axil_rready   (dma_reg_rready),
                .s_axil_rdata    (dma_reg_rdata),
                .s_axil_rresp    (dma_reg_rresp),
                
                // AXI4 Master
                .m_axi_awvalid  (m_axi_awvalid),
                .m_axi_awready  (m_axi_awready),
                .m_axi_awaddr   (m_axi_awaddr),
                .m_axi_awlen    (m_axi_awlen),
                .m_axi_awsize   (m_axi_awsize),
                .m_axi_awburst  (m_axi_awburst),
                .m_axi_awid     (m_axi_awid),
                .m_axi_wvalid   (m_axi_wvalid),
                .m_axi_wready   (m_axi_wready),
                .m_axi_wdata    (m_axi_wdata),
                .m_axi_wstrb    (m_axi_wstrb),
                .m_axi_wlast    (m_axi_wlast),
                .m_axi_bvalid   (m_axi_bvalid),
                .m_axi_bready   (m_axi_bready),
                .m_axi_bresp    (m_axi_bresp),
                .m_axi_bid      (m_axi_bid),
                .m_axi_arvalid  (m_axi_arvalid),
                .m_axi_arready  (m_axi_arready),
                .m_axi_araddr   (m_axi_araddr),
                .m_axi_arlen    (m_axi_arlen),
                .m_axi_arsize   (m_axi_arsize),
                .m_axi_arburst  (m_axi_arburst),
                .m_axi_arid     (m_axi_arid),
                .m_axi_rvalid   (m_axi_rvalid),
                .m_axi_rready   (m_axi_rready),
                .m_axi_rdata    (m_axi_rdata),
                .m_axi_rresp    (m_axi_rresp),
                .m_axi_rlast    (m_axi_rlast),
                .m_axi_rid      (m_axi_rid),
                
                // AXI-Stream TX (DMA -> MAC)
                .m_axis_tx_tvalid   (dma_tx_axis_tvalid),
                .m_axis_tx_tready   (dma_tx_axis_tready),
                .m_axis_tx_tdata    (dma_tx_axis_tdata),
                .m_axis_tx_tlast    (dma_tx_axis_tlast),
                .m_axis_tx_tuser    (dma_tx_axis_tuser),
                
                // AXI-Stream RX (MAC -> DMA)
                .s_axis_rx_tvalid   (dma_rx_axis_tvalid),
                .s_axis_rx_tready   (dma_rx_axis_tready),
                .s_axis_rx_tdata    (dma_rx_axis_tdata),
                .s_axis_rx_tlast    (dma_rx_axis_tlast),
                .s_axis_rx_tuser    (dma_rx_axis_tuser),
                
                // Interrupt
                .dma_irq        (dma_irq_internal)
            );
            
            // Connect DMA to MAC
            assign mac_tx_axis_tvalid = dma_tx_axis_tvalid;
            assign dma_tx_axis_tready = mac_tx_axis_tready;
            assign mac_tx_axis_tdata  = dma_tx_axis_tdata;
            assign mac_tx_axis_tlast  = dma_tx_axis_tlast;
            assign mac_tx_axis_tuser  = dma_tx_axis_tuser;
            
            assign dma_rx_axis_tvalid = mac_rx_axis_tvalid;
            assign mac_rx_axis_tready = dma_rx_axis_tready;
            assign dma_rx_axis_tdata  = mac_rx_axis_tdata;
            assign dma_rx_axis_tlast  = mac_rx_axis_tlast;
            assign dma_rx_axis_tuser  = mac_rx_axis_tuser;
            
            // External AXI-Stream ports are unused when DMA is enabled
            assign s_axis_tx_tready = 1'b0;
            assign m_axis_rx_tvalid = 1'b0;
            assign m_axis_rx_tdata  = 8'd0;
            assign m_axis_rx_tlast  = 1'b0;
            assign m_axis_rx_tuser  = 1'b0;
            
        end else begin : gen_no_dma
            
            // No DMA - Connect external AXI-Stream directly to MAC
            assign mac_tx_axis_tvalid = s_axis_tx_tvalid;
            assign s_axis_tx_tready   = mac_tx_axis_tready;
            assign mac_tx_axis_tdata  = s_axis_tx_tdata;
            assign mac_tx_axis_tlast  = s_axis_tx_tlast;
            assign mac_tx_axis_tuser  = s_axis_tx_tuser;
            
            assign m_axis_rx_tvalid   = mac_rx_axis_tvalid;
            assign mac_rx_axis_tready = m_axis_rx_tready;
            assign m_axis_rx_tdata    = mac_rx_axis_tdata;
            assign m_axis_rx_tlast    = mac_rx_axis_tlast;
            assign m_axis_rx_tuser    = mac_rx_axis_tuser;
            
            // Tie off DMA register interface
            assign dma_reg_awready = 1'b1;
            assign dma_reg_wready  = 1'b1;
            assign dma_reg_bvalid  = 1'b0;
            assign dma_reg_bresp   = 2'b00;
            assign dma_reg_arready = 1'b1;
            assign dma_reg_rvalid  = 1'b0;
            assign dma_reg_rdata   = 32'd0;
            assign dma_reg_rresp   = 2'b00;
            
            // Tie off AXI Master interface
            assign m_axi_awvalid = 1'b0;
            assign m_axi_awaddr  = {DMA_ADDR_WIDTH{1'b0}};
            assign m_axi_awlen   = 8'd0;
            assign m_axi_awsize  = 3'd0;
            assign m_axi_awburst = 2'd0;
            assign m_axi_awid    = 4'd0;
            assign m_axi_wvalid  = 1'b0;
            assign m_axi_wdata   = {DMA_DATA_WIDTH{1'b0}};
            assign m_axi_wstrb   = {(DMA_DATA_WIDTH/8){1'b0}};
            assign m_axi_wlast   = 1'b0;
            assign m_axi_bready  = 1'b1;
            assign m_axi_arvalid = 1'b0;
            assign m_axi_araddr  = {DMA_ADDR_WIDTH{1'b0}};
            assign m_axi_arlen   = 8'd0;
            assign m_axi_arsize  = 3'd0;
            assign m_axi_arburst = 2'd0;
            assign m_axi_arid    = 4'd0;
            assign m_axi_rready  = 1'b1;
            
            // No DMA interrupt
            assign dma_irq_internal = 1'b0;
            
        end
    endgenerate

    //==========================================================================
    // Interrupt Controller
    //==========================================================================
    eth_controller_irq #(
        .DMA_ENABLE (DMA_ENABLE)
    ) u_irq (
        .clk            (sys_clk),
        .rst_n          (sys_rst_n),
        .mac_irq_in     (mac_irq_internal),
        .dma_irq_in     (dma_irq_internal),
        .mac_irq        (mac_irq),
        .dma_irq        (dma_irq)
    );

endmodule
