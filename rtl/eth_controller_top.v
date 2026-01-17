//==============================================================================
// Module: eth_controller_top
// Description: Complete Ethernet Controller with optional DMA
//
// This is the top-level integration module that combines:
//   - Gigabit Ethernet MAC (mac_top)
//   - Optional DMA subsystem (eth_dma_top)
//
// Architecture Modes:
//   DMA_ENABLE=1: Full Ethernet Controller with DMA
//     ┌──────────────────────────────────────────────────────────┐
//     │              eth_controller_top                           │
//     │                                                           │
//     │  ┌──────────────┐         ┌────────────────┐             │
//     │  │              │  AXI-S  │                │             │
//     │  │   MAC Core   │◄───────►│   DMA Engine   │◄──── Memory│
//     │  │   (mac_top)  │         │  (eth_dma_top) │     (AXI4) │
//     │  └──────┬───────┘         └────────┬───────┘             │
//     │         │                          │                     │
//     │     GMII/RGMII              AXI-Lite Control              │
//     └─────────┼──────────────────────────┼─────────────────────┘
//               │                          │
//             PHY                     CPU/Software
//
//   DMA_ENABLE=0: MAC-only mode (DMA bypassed)
//     ┌──────────────────────────────────────────────────────────┐
//     │              eth_controller_top                           │
//     │                                                           │
//     │  ┌──────────────┐                                        │
//     │  │              │  AXI-S                                 │
//     │  │   MAC Core   │◄────────────────────── CPU/Software   │
//     │  │   (mac_top)  │        (Direct connection)            │
//     │  └──────┬───────┘                                        │
//     │         │                                                │
//     │     GMII/RGMII                                           │
//     └─────────┼──────────────────────────────────────────────┘
//               │
//             PHY
//
// Key Features:
//   - DMA is completely optional via parameter
//   - Separate AXI-Lite address spaces for MAC and DMA
//   - Clean separation: MAC does not depend on DMA
//   - Can be used in three configurations:
//     1. MAC + DMA (embedded systems)
//     2. MAC only (FPGA direct streaming)
//     3. Future: MAC + custom datapath
//
// Clocking:
//   - sys_clk: System bus, MAC data interfaces, DMA
//   - gtx_clk: GMII TX clock (125 MHz)
//   - rx_clk:  GMII RX clock (125 MHz from PHY)
//
// Reset:
//   - sys_rst_n:  Resets system domain (MAC regs, DMA, AXI-Stream)
//   - gtx_rst_n:  Resets GMII TX domain
//   - rx_rst_n:   Resets GMII RX domain
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_controller_top #(
    //==========================================================================
    // DMA Enable/Bypass
    //==========================================================================
    parameter DMA_ENABLE        = 1,            // 1=DMA enabled, 0=MAC only
    
    //==========================================================================
    // MAC Parameters
    //==========================================================================
    parameter AXI_ADDR_WIDTH    = 8,
    parameter AXI_DATA_WIDTH    = 32,
    parameter TX_FIFO_DEPTH     = 4,
    parameter RX_FIFO_DEPTH     = 4,
    parameter MIN_FRAME_SIZE    = 64,
    parameter MAX_FRAME_SIZE    = 1518,
    parameter IFG_BYTES         = 12,
    
    //==========================================================================
    // DMA Parameters (only used if DMA_ENABLE=1)
    //==========================================================================
    parameter DMA_ADDR_WIDTH    = 8,
    parameter M_AXI_ADDR_WIDTH  = 32,
    parameter M_AXI_DATA_WIDTH  = 64,
    parameter M_AXI_ID_WIDTH    = 4,
    parameter M_AXI_MAX_BURST   = 16,
    parameter DESC_ADDR_WIDTH   = 32,
    parameter DESC_RING_DEPTH   = 8,
    parameter BUF_SIZE_WIDTH    = 14
) (
    //==========================================================================
    // Clocks and Resets
    //==========================================================================
    input  wire                         sys_clk,
    input  wire                         sys_rst_n,
    input  wire                         gtx_clk,
    input  wire                         gtx_rst_n,
    input  wire                         rx_clk,
    input  wire                         rx_rst_n,

    //==========================================================================
    // MAC AXI4-Lite Interface
    //==========================================================================
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_mac_awaddr,
    input  wire                         s_axi_mac_awvalid,
    output wire                         s_axi_mac_awready,
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_mac_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_mac_wstrb,
    input  wire                         s_axi_mac_wvalid,
    output wire                         s_axi_mac_wready,
    output wire [1:0]                   s_axi_mac_bresp,
    output wire                         s_axi_mac_bvalid,
    input  wire                         s_axi_mac_bready,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_mac_araddr,
    input  wire                         s_axi_mac_arvalid,
    output wire                         s_axi_mac_arready,
    output wire [AXI_DATA_WIDTH-1:0]    s_axi_mac_rdata,
    output wire [1:0]                   s_axi_mac_rresp,
    output wire                         s_axi_mac_rvalid,
    input  wire                         s_axi_mac_rready,

    //==========================================================================
    // DMA AXI4-Lite Interface (only if DMA_ENABLE=1)
    //==========================================================================
    input  wire [DMA_ADDR_WIDTH-1:0]    s_axi_dma_awaddr,
    input  wire                         s_axi_dma_awvalid,
    output wire                         s_axi_dma_awready,
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_dma_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_dma_wstrb,
    input  wire                         s_axi_dma_wvalid,
    output wire                         s_axi_dma_wready,
    output wire [1:0]                   s_axi_dma_bresp,
    output wire                         s_axi_dma_bvalid,
    input  wire                         s_axi_dma_bready,
    input  wire [DMA_ADDR_WIDTH-1:0]    s_axi_dma_araddr,
    input  wire                         s_axi_dma_arvalid,
    output wire                         s_axi_dma_arready,
    output wire [AXI_DATA_WIDTH-1:0]    s_axi_dma_rdata,
    output wire [1:0]                   s_axi_dma_rresp,
    output wire                         s_axi_dma_rvalid,
    input  wire                         s_axi_dma_rready,

    //==========================================================================
    // AXI4 Memory Interface (only if DMA_ENABLE=1)
    //==========================================================================
    output wire [M_AXI_ID_WIDTH-1:0]    m_axi_mem_awid,
    output wire [M_AXI_ADDR_WIDTH-1:0]  m_axi_mem_awaddr,
    output wire [7:0]                   m_axi_mem_awlen,
    output wire [2:0]                   m_axi_mem_awsize,
    output wire [1:0]                   m_axi_mem_awburst,
    output wire                         m_axi_mem_awlock,
    output wire [3:0]                   m_axi_mem_awcache,
    output wire [2:0]                   m_axi_mem_awprot,
    output wire                         m_axi_mem_awvalid,
    input  wire                         m_axi_mem_awready,
    output wire [M_AXI_DATA_WIDTH-1:0]  m_axi_mem_wdata,
    output wire [M_AXI_DATA_WIDTH/8-1:0] m_axi_mem_wstrb,
    output wire                         m_axi_mem_wlast,
    output wire                         m_axi_mem_wvalid,
    input  wire                         m_axi_mem_wready,
    input  wire [M_AXI_ID_WIDTH-1:0]    m_axi_mem_bid,
    input  wire [1:0]                   m_axi_mem_bresp,
    input  wire                         m_axi_mem_bvalid,
    output wire                         m_axi_mem_bready,
    output wire [M_AXI_ID_WIDTH-1:0]    m_axi_mem_arid,
    output wire [M_AXI_ADDR_WIDTH-1:0]  m_axi_mem_araddr,
    output wire [7:0]                   m_axi_mem_arlen,
    output wire [2:0]                   m_axi_mem_arsize,
    output wire [1:0]                   m_axi_mem_arburst,
    output wire                         m_axi_mem_arlock,
    output wire [3:0]                   m_axi_mem_arcache,
    output wire [2:0]                   m_axi_mem_arprot,
    output wire                         m_axi_mem_arvalid,
    input  wire                         m_axi_mem_arready,
    input  wire [M_AXI_ID_WIDTH-1:0]    m_axi_mem_rid,
    input  wire [M_AXI_DATA_WIDTH-1:0]  m_axi_mem_rdata,
    input  wire [1:0]                   m_axi_mem_rresp,
    input  wire                         m_axi_mem_rlast,
    input  wire                         m_axi_mem_rvalid,
    output wire                         m_axi_mem_rready,

    //==========================================================================
    // User TX/RX AXI-Stream (only if DMA_ENABLE=0)
    //==========================================================================
    input  wire [7:0]                   s_axis_user_tx_tdata,
    input  wire                         s_axis_user_tx_tvalid,
    input  wire                         s_axis_user_tx_tlast,
    input  wire                         s_axis_user_tx_tuser,
    output wire                         s_axis_user_tx_tready,
    
    output wire [7:0]                   m_axis_user_rx_tdata,
    output wire                         m_axis_user_rx_tvalid,
    output wire                         m_axis_user_rx_tlast,
    output wire [1:0]                   m_axis_user_rx_tuser,
    input  wire                         m_axis_user_rx_tready,

    //==========================================================================
    // GMII Interface
    //==========================================================================
    output wire [7:0]                   gmii_txd,
    output wire                         gmii_tx_en,
    output wire                         gmii_tx_er,
    input  wire [7:0]                   gmii_rxd,
    input  wire                         gmii_rx_dv,
    input  wire                         gmii_rx_er,
    input  wire                         gmii_col,
    input  wire                         gmii_crs,

    //==========================================================================
    // Interrupts
    //==========================================================================
    output wire                         irq_mac,
    output wire                         irq_dma_tx_done,
    output wire                         irq_dma_rx_done,
    output wire                         irq_dma_tx_error,
    output wire                         irq_dma_rx_error,
    output wire                         irq_dma_combined
);

    //==========================================================================
    // Internal AXI-Stream Signals (MAC ↔ DMA)
    //==========================================================================
    wire [7:0]  mac_tx_tdata;
    wire        mac_tx_tvalid;
    wire        mac_tx_tlast;
    wire        mac_tx_tuser;
    wire        mac_tx_tready;
    
    wire [7:0]  mac_rx_tdata;
    wire        mac_rx_tvalid;
    wire        mac_rx_tlast;
    wire [1:0]  mac_rx_tuser;
    wire        mac_rx_tready;

    //==========================================================================
    // MAC Instantiation
    //==========================================================================
    mac_top #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .TX_FIFO_DEPTH  (TX_FIFO_DEPTH),
        .RX_FIFO_DEPTH  (RX_FIFO_DEPTH),
        .MIN_FRAME_SIZE (MIN_FRAME_SIZE),
        .MAX_FRAME_SIZE (MAX_FRAME_SIZE),
        .IFG_BYTES      (IFG_BYTES)
    ) u_mac (
        // Clocks and resets
        .sys_clk        (sys_clk),
        .sys_rst_n      (sys_rst_n),
        .gtx_clk        (gtx_clk),
        .gtx_rst_n      (gtx_rst_n),
        .rx_clk         (rx_clk),
        .rx_rst_n       (rx_rst_n),
        
        // AXI4-Lite interface
        .s_axi_awaddr   (s_axi_mac_awaddr),
        .s_axi_awvalid  (s_axi_mac_awvalid),
        .s_axi_awready  (s_axi_mac_awready),
        .s_axi_wdata    (s_axi_mac_wdata),
        .s_axi_wstrb    (s_axi_mac_wstrb),
        .s_axi_wvalid   (s_axi_mac_wvalid),
        .s_axi_wready   (s_axi_mac_wready),
        .s_axi_bresp    (s_axi_mac_bresp),
        .s_axi_bvalid   (s_axi_mac_bvalid),
        .s_axi_bready   (s_axi_mac_bready),
        .s_axi_araddr   (s_axi_mac_araddr),
        .s_axi_arvalid  (s_axi_mac_arvalid),
        .s_axi_arready  (s_axi_mac_arready),
        .s_axi_rdata    (s_axi_mac_rdata),
        .s_axi_rresp    (s_axi_mac_rresp),
        .s_axi_rvalid   (s_axi_mac_rvalid),
        .s_axi_rready   (s_axi_mac_rready),
        
        // TX AXI-Stream (from DMA or user)
        .tx_axis_tdata  (mac_tx_tdata),
        .tx_axis_tvalid (mac_tx_tvalid),
        .tx_axis_tlast  (mac_tx_tlast),
        .tx_axis_tuser  (mac_tx_tuser),
        .tx_axis_tready (mac_tx_tready),
        
        // RX AXI-Stream (to DMA or user)
        .rx_axis_tdata  (mac_rx_tdata),
        .rx_axis_tvalid (mac_rx_tvalid),
        .rx_axis_tlast  (mac_rx_tlast),
        .rx_axis_tuser  (mac_rx_tuser),
        .rx_axis_tready (mac_rx_tready),
        
        // GMII interface
        .gmii_txd       (gmii_txd),
        .gmii_tx_en     (gmii_tx_en),
        .gmii_tx_er     (gmii_tx_er),
        .gmii_rxd       (gmii_rxd),
        .gmii_rx_dv     (gmii_rx_dv),
        .gmii_rx_er     (gmii_rx_er),
        .gmii_col       (gmii_col),
        .gmii_crs       (gmii_crs),
        
        // Interrupt
        .irq            (irq_mac)
    );

    //==========================================================================
    // DMA Instantiation (conditional)
    //==========================================================================
    eth_dma_top #(
        .DMA_ENABLE         (DMA_ENABLE),
        .C_ADDR_WIDTH       (DMA_ADDR_WIDTH),
        .C_DATA_WIDTH       (AXI_DATA_WIDTH),
        .M_AXI_ADDR_WIDTH   (M_AXI_ADDR_WIDTH),
        .M_AXI_DATA_WIDTH   (M_AXI_DATA_WIDTH),
        .M_AXI_ID_WIDTH     (M_AXI_ID_WIDTH),
        .M_AXI_MAX_BURST    (M_AXI_MAX_BURST),
        .DESC_ADDR_WIDTH    (DESC_ADDR_WIDTH),
        .DESC_RING_DEPTH    (DESC_RING_DEPTH),
        .BUF_SIZE_WIDTH     (BUF_SIZE_WIDTH),
        .MIN_FRAME_SIZE     (MIN_FRAME_SIZE),
        .MAX_FRAME_SIZE     (MAX_FRAME_SIZE),
        .AXIS_DATA_WIDTH    (8),
        .AXIS_USER_WIDTH    (2)
    ) u_dma (
        .clk                    (sys_clk),
        .rst_n                  (sys_rst_n),
        
        // DMA control interface
        .s_axi_ctrl_awaddr      (s_axi_dma_awaddr),
        .s_axi_ctrl_awvalid     (s_axi_dma_awvalid),
        .s_axi_ctrl_awready     (s_axi_dma_awready),
        .s_axi_ctrl_wdata       (s_axi_dma_wdata),
        .s_axi_ctrl_wstrb       (s_axi_dma_wstrb),
        .s_axi_ctrl_wvalid      (s_axi_dma_wvalid),
        .s_axi_ctrl_wready      (s_axi_dma_wready),
        .s_axi_ctrl_bresp       (s_axi_dma_bresp),
        .s_axi_ctrl_bvalid      (s_axi_dma_bvalid),
        .s_axi_ctrl_bready      (s_axi_dma_bready),
        .s_axi_ctrl_araddr      (s_axi_dma_araddr),
        .s_axi_ctrl_arvalid     (s_axi_dma_arvalid),
        .s_axi_ctrl_arready     (s_axi_dma_arready),
        .s_axi_ctrl_rdata       (s_axi_dma_rdata),
        .s_axi_ctrl_rresp       (s_axi_dma_rresp),
        .s_axi_ctrl_rvalid      (s_axi_dma_rvalid),
        .s_axi_ctrl_rready      (s_axi_dma_rready),
        
        // Memory interface
        .m_axi_mem_awid         (m_axi_mem_awid),
        .m_axi_mem_awaddr       (m_axi_mem_awaddr),
        .m_axi_mem_awlen        (m_axi_mem_awlen),
        .m_axi_mem_awsize       (m_axi_mem_awsize),
        .m_axi_mem_awburst      (m_axi_mem_awburst),
        .m_axi_mem_awlock       (m_axi_mem_awlock),
        .m_axi_mem_awcache      (m_axi_mem_awcache),
        .m_axi_mem_awprot       (m_axi_mem_awprot),
        .m_axi_mem_awvalid      (m_axi_mem_awvalid),
        .m_axi_mem_awready      (m_axi_mem_awready),
        .m_axi_mem_wdata        (m_axi_mem_wdata),
        .m_axi_mem_wstrb        (m_axi_mem_wstrb),
        .m_axi_mem_wlast        (m_axi_mem_wlast),
        .m_axi_mem_wvalid       (m_axi_mem_wvalid),
        .m_axi_mem_wready       (m_axi_mem_wready),
        .m_axi_mem_bid          (m_axi_mem_bid),
        .m_axi_mem_bresp        (m_axi_mem_bresp),
        .m_axi_mem_bvalid       (m_axi_mem_bvalid),
        .m_axi_mem_bready       (m_axi_mem_bready),
        .m_axi_mem_arid         (m_axi_mem_arid),
        .m_axi_mem_araddr       (m_axi_mem_araddr),
        .m_axi_mem_arlen        (m_axi_mem_arlen),
        .m_axi_mem_arsize       (m_axi_mem_arsize),
        .m_axi_mem_arburst      (m_axi_mem_arburst),
        .m_axi_mem_arlock       (m_axi_mem_arlock),
        .m_axi_mem_arcache      (m_axi_mem_arcache),
        .m_axi_mem_arprot       (m_axi_mem_arprot),
        .m_axi_mem_arvalid      (m_axi_mem_arvalid),
        .m_axi_mem_arready      (m_axi_mem_arready),
        .m_axi_mem_rid          (m_axi_mem_rid),
        .m_axi_mem_rdata        (m_axi_mem_rdata),
        .m_axi_mem_rresp        (m_axi_mem_rresp),
        .m_axi_mem_rlast        (m_axi_mem_rlast),
        .m_axi_mem_rvalid       (m_axi_mem_rvalid),
        .m_axi_mem_rready       (m_axi_mem_rready),
        
        // MAC-side AXI-Stream
        .m_axis_mac_tx_tdata    (mac_tx_tdata),
        .m_axis_mac_tx_tvalid   (mac_tx_tvalid),
        .m_axis_mac_tx_tlast    (mac_tx_tlast),
        .m_axis_mac_tx_tuser    (mac_tx_tuser),
        .m_axis_mac_tx_tready   (mac_tx_tready),
        .s_axis_mac_rx_tdata    (mac_rx_tdata),
        .s_axis_mac_rx_tvalid   (mac_rx_tvalid),
        .s_axis_mac_rx_tlast    (mac_rx_tlast),
        .s_axis_mac_rx_tuser    (mac_rx_tuser),
        .s_axis_mac_rx_tready   (mac_rx_tready),
        
        // User-side AXI-Stream (for bypass mode)
        .s_axis_user_tx_tdata   (s_axis_user_tx_tdata),
        .s_axis_user_tx_tvalid  (s_axis_user_tx_tvalid),
        .s_axis_user_tx_tlast   (s_axis_user_tx_tlast),
        .s_axis_user_tx_tuser   (s_axis_user_tx_tuser),
        .s_axis_user_tx_tready  (s_axis_user_tx_tready),
        .m_axis_user_rx_tdata   (m_axis_user_rx_tdata),
        .m_axis_user_rx_tvalid  (m_axis_user_rx_tvalid),
        .m_axis_user_rx_tlast   (m_axis_user_rx_tlast),
        .m_axis_user_rx_tuser   (m_axis_user_rx_tuser),
        .m_axis_user_rx_tready  (m_axis_user_rx_tready),
        
        // Interrupts
        .irq_tx_done            (irq_dma_tx_done),
        .irq_rx_done            (irq_dma_rx_done),
        .irq_tx_error           (irq_dma_tx_error),
        .irq_rx_error           (irq_dma_rx_error),
        .irq_combined           (irq_dma_combined)
    );

endmodule
