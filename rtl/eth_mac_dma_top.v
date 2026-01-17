//==============================================================================
// Module: eth_controller_top
// Description: Complete Ethernet Controller with optional DMA
//
// This is the top-level integration module that combines:
//   - Gigabit Ethernet MAC (mac_top)
//   - Optional DMA subsystem (eth_dma_top)
//   - Unified register interface (eth_regs)
//
// Key Features:
//   - Single AXI4-Lite interface for all registers
//   - MAC registers at 0x000-0x0FF
//   - DMA registers at 0x200-0x2FF (optional)
//   - Separate mac_irq and dma_irq interrupt outputs
//   - DMA is completely optional via DMA_ENABLE parameter
//   - Clean separation: MAC does not depend on DMA
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
    // AXI4-Lite Register Interface Parameters
    //==========================================================================
    parameter AXI_ADDR_WIDTH    = 10,           // Address width (min 10 for DMA space)
    parameter AXI_DATA_WIDTH    = 32,           // Data width (fixed 32)
    
    //==========================================================================
    // MAC Parameters
    //==========================================================================
    parameter TX_FIFO_DEPTH     = 4,
    parameter RX_FIFO_DEPTH     = 4,
    parameter MIN_FRAME_SIZE    = 64,
    parameter MAX_FRAME_SIZE    = 1518,
    parameter IFG_BYTES         = 12,
    
    //==========================================================================
    // DMA Parameters (only used if DMA_ENABLE=1)
    //==========================================================================
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
    // Unified AXI4-Lite Interface (MAC + DMA registers)
    //==========================================================================
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,
    output wire [1:0]                   s_axi_bresp,
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,
    output wire [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready,

    //==========================================================================
    // Interrupt Outputs
    //==========================================================================
    output wire                         mac_irq,        // MAC interrupt
    output wire                         dma_irq,        // DMA interrupt

    //==========================================================================
    // AXI4 Memory Interface (only if DMA_ENABLE=1)
    //==========================================================================
    output wire [M_AXI_ID_WIDTH-1:0]    m_axi_awid,
    output wire [M_AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output wire [1:0]                   m_axi_awburst,
    output wire                         m_axi_awlock,
    output wire [3:0]                   m_axi_awcache,
    output wire [2:0]                   m_axi_awprot,
    output wire                         m_axi_awvalid,
    input  wire                         m_axi_awready,
    output wire [M_AXI_DATA_WIDTH-1:0]  m_axi_wdata,
    output wire [M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output wire                         m_axi_wlast,
    output wire                         m_axi_wvalid,
    input  wire                         m_axi_wready,
    input  wire [M_AXI_ID_WIDTH-1:0]    m_axi_bid,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output wire                         m_axi_bready,
    output wire [M_AXI_ID_WIDTH-1:0]    m_axi_arid,
    output wire [M_AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire                         m_axi_arlock,
    output wire [3:0]                   m_axi_arcache,
    output wire [2:0]                   m_axi_arprot,
    output wire                         m_axi_arvalid,
    input  wire                         m_axi_arready,
    input  wire [M_AXI_ID_WIDTH-1:0]    m_axi_rid,
    input  wire [M_AXI_DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready,

    //==========================================================================
    // User TX/RX AXI-Stream (only if DMA_ENABLE=0)
    //==========================================================================
    input  wire [7:0]                   s_axis_tx_tdata,
    input  wire                         s_axis_tx_tvalid,
    input  wire                         s_axis_tx_tlast,
    input  wire                         s_axis_tx_tuser,
    output wire                         s_axis_tx_tready,
    
    output wire [7:0]                   m_axis_rx_tdata,
    output wire                         m_axis_rx_tvalid,
    output wire                         m_axis_rx_tlast,
    output wire [1:0]                   m_axis_rx_tuser,
    input  wire                         m_axis_rx_tready,

    //==========================================================================
    // GMII Interface
    //==========================================================================
    output wire                         gmii_tx_clk,
    output wire                         gmii_tx_en,
    output wire [7:0]                   gmii_txd,
    output wire                         gmii_tx_er,
    input  wire                         gmii_rx_clk,
    input  wire                         gmii_rx_dv,
    input  wire [7:0]                   gmii_rxd,
    input  wire                         gmii_rx_er
);

    //==========================================================================
    // Internal Signals - Register Interface
    //==========================================================================
    wire [47:0]                     mac_addr;
    wire                            mac_tx_enable;
    wire                            mac_rx_enable;
    wire                            mac_tx_active;
    wire                            mac_rx_active;
    wire [31:0]                     mac_tx_frame_cnt;
    wire [31:0]                     mac_rx_frame_cnt;
    wire [31:0]                     mac_rx_err_cnt;
    wire                            mac_int_tx_complete;
    wire                            mac_int_rx_received;
    wire                            mac_int_rx_crc_err;
    wire                            mac_int_rx_runt;

    //==========================================================================
    // Internal Signals - DMA Control/Status
    //==========================================================================
    wire                            dma_tx_enable;
    wire                            dma_rx_enable;
    wire                            dma_reset;
    wire [DESC_ADDR_WIDTH-1:0]      tx_desc_base;
    wire [7:0]                      tx_ring_size;
    wire [DESC_ADDR_WIDTH-1:0]      rx_desc_base;
    wire [7:0]                      rx_ring_size;
    wire                            dma_tx_busy;
    wire                            dma_rx_busy;
    wire [31:0]                     dma_tx_pkt_cnt;
    wire [31:0]                     dma_rx_pkt_cnt;
    wire [31:0]                     dma_tx_err_cnt;
    wire [31:0]                     dma_rx_err_cnt;
    wire                            dma_int_tx_complete;
    wire                            dma_int_rx_complete;
    wire                            dma_int_tx_error;
    wire                            dma_int_rx_error;

    //==========================================================================
    // Internal Signals - AXI-Stream (MAC <-> DMA or User)
    //==========================================================================
    wire [7:0]                      mac_tx_axis_tdata;
    wire                            mac_tx_axis_tvalid;
    wire                            mac_tx_axis_tlast;
    wire                            mac_tx_axis_tuser;
    wire                            mac_tx_axis_tready;
    
    wire [7:0]                      mac_rx_axis_tdata;
    wire                            mac_rx_axis_tvalid;
    wire                            mac_rx_axis_tlast;
    wire [1:0]                      mac_rx_axis_tuser;
    wire                            mac_rx_axis_tready;

    //==========================================================================
    // Unified Register Interface
    //==========================================================================
    eth_regs #(
        .ADDR_WIDTH         (AXI_ADDR_WIDTH),
        .DATA_WIDTH         (AXI_DATA_WIDTH),
        .DMA_ENABLE         (DMA_ENABLE),
        .DESC_ADDR_WIDTH    (DESC_ADDR_WIDTH)
    ) u_eth_regs (
        .clk                (sys_clk),
        .rst_n              (sys_rst_n),
        
        // AXI4-Lite Interface
        .s_axi_awaddr       (s_axi_awaddr),
        .s_axi_awvalid      (s_axi_awvalid),
        .s_axi_awready      (s_axi_awready),
        .s_axi_wdata        (s_axi_wdata),
        .s_axi_wstrb        (s_axi_wstrb),
        .s_axi_wvalid       (s_axi_wvalid),
        .s_axi_wready       (s_axi_wready),
        .s_axi_bresp        (s_axi_bresp),
        .s_axi_bvalid       (s_axi_bvalid),
        .s_axi_bready       (s_axi_bready),
        .s_axi_araddr       (s_axi_araddr),
        .s_axi_arvalid      (s_axi_arvalid),
        .s_axi_arready      (s_axi_arready),
        .s_axi_rdata        (s_axi_rdata),
        .s_axi_rresp        (s_axi_rresp),
        .s_axi_rvalid       (s_axi_rvalid),
        .s_axi_rready       (s_axi_rready),
        
        // MAC Control/Status
        .mac_addr           (mac_addr),
        .mac_tx_enable      (mac_tx_enable),
        .mac_rx_enable      (mac_rx_enable),
        .mac_tx_active      (mac_tx_active),
        .mac_rx_active      (mac_rx_active),
        .mac_tx_frame_cnt   (mac_tx_frame_cnt),
        .mac_rx_frame_cnt   (mac_rx_frame_cnt),
        .mac_rx_err_cnt     (mac_rx_err_cnt),
        .mac_int_tx_complete(mac_int_tx_complete),
        .mac_int_rx_received(mac_int_rx_received),
        .mac_int_rx_crc_err (mac_int_rx_crc_err),
        .mac_int_rx_runt    (mac_int_rx_runt),
        .mac_irq            (mac_irq),
        
        // DMA Control/Status
        .dma_tx_enable      (dma_tx_enable),
        .dma_rx_enable      (dma_rx_enable),
        .dma_reset          (dma_reset),
        .tx_desc_base       (tx_desc_base),
        .tx_ring_size       (tx_ring_size),
        .rx_desc_base       (rx_desc_base),
        .rx_ring_size       (rx_ring_size),
        .dma_tx_busy        (dma_tx_busy),
        .dma_rx_busy        (dma_rx_busy),
        .dma_tx_pkt_cnt     (dma_tx_pkt_cnt),
        .dma_rx_pkt_cnt     (dma_rx_pkt_cnt),
        .dma_tx_err_cnt     (dma_tx_err_cnt),
        .dma_rx_err_cnt     (dma_rx_err_cnt),
        .dma_int_tx_complete(dma_int_tx_complete),
        .dma_int_rx_complete(dma_int_rx_complete),
        .dma_int_tx_error   (dma_int_tx_error),
        .dma_int_rx_error   (dma_int_rx_error),
        .dma_irq            (dma_irq)
    );

    //==========================================================================
    // MAC Core Instantiation
    //==========================================================================
    mac_top #(
        .TX_FIFO_DEPTH      (TX_FIFO_DEPTH),
        .RX_FIFO_DEPTH      (RX_FIFO_DEPTH),
        .MIN_FRAME_SIZE     (MIN_FRAME_SIZE),
        .MAX_FRAME_SIZE     (MAX_FRAME_SIZE),
        .IFG_BYTES          (IFG_BYTES)
    ) u_mac_top (
        // System clock domain
        .sys_clk            (sys_clk),
        .sys_rst_n          (sys_rst_n),
        
        // GMII clock domains
        .gtx_clk            (gtx_clk),
        .gtx_rst_n          (gtx_rst_n),
        .rx_clk             (rx_clk),
        .rx_rst_n           (rx_rst_n),
        
        // Control/Status
        .mac_addr           (mac_addr),
        .tx_enable          (mac_tx_enable),
        .rx_enable          (mac_rx_enable),
        .tx_active          (mac_tx_active),
        .rx_active          (mac_rx_active),
        .tx_frame_cnt       (mac_tx_frame_cnt),
        .rx_frame_cnt       (mac_rx_frame_cnt),
        .rx_err_cnt         (mac_rx_err_cnt),
        
        // Interrupts
        .int_tx_complete    (mac_int_tx_complete),
        .int_rx_received    (mac_int_rx_received),
        .int_rx_crc_err     (mac_int_rx_crc_err),
        .int_rx_runt        (mac_int_rx_runt),
        
        // TX AXI-Stream
        .s_axis_tx_tdata    (mac_tx_axis_tdata),
        .s_axis_tx_tvalid   (mac_tx_axis_tvalid),
        .s_axis_tx_tlast    (mac_tx_axis_tlast),
        .s_axis_tx_tuser    (mac_tx_axis_tuser),
        .s_axis_tx_tready   (mac_tx_axis_tready),
        
        // RX AXI-Stream
        .m_axis_rx_tdata    (mac_rx_axis_tdata),
        .m_axis_rx_tvalid   (mac_rx_axis_tvalid),
        .m_axis_rx_tlast    (mac_rx_axis_tlast),
        .m_axis_rx_tuser    (mac_rx_axis_tuser),
        .m_axis_rx_tready   (mac_rx_axis_tready),
        
        // GMII Interface
        .gmii_tx_clk        (gmii_tx_clk),
        .gmii_tx_en         (gmii_tx_en),
        .gmii_txd           (gmii_txd),
        .gmii_tx_er         (gmii_tx_er),
        .gmii_rx_clk        (gmii_rx_clk),
        .gmii_rx_dv         (gmii_rx_dv),
        .gmii_rxd           (gmii_rxd),
        .gmii_rx_er         (gmii_rx_er)
    );

    //==========================================================================
    // DMA Subsystem or Bypass
    //==========================================================================
    generate
        if (DMA_ENABLE) begin : gen_with_dma
            // Instantiate DMA
            eth_dma_core #(
                .M_AXI_ADDR_WIDTH   (M_AXI_ADDR_WIDTH),
                .M_AXI_DATA_WIDTH   (M_AXI_DATA_WIDTH),
                .M_AXI_ID_WIDTH     (M_AXI_ID_WIDTH),
                .M_AXI_MAX_BURST    (M_AXI_MAX_BURST),
                .DESC_ADDR_WIDTH    (DESC_ADDR_WIDTH),
                .DESC_RING_DEPTH    (DESC_RING_DEPTH),
                .BUF_SIZE_WIDTH     (BUF_SIZE_WIDTH)
            ) u_dma (
                .clk                (sys_clk),
                .rst_n              (sys_rst_n & ~dma_reset),
                
                // Control/Status
                .tx_enable          (dma_tx_enable),
                .rx_enable          (dma_rx_enable),
                .tx_desc_base       (tx_desc_base),
                .tx_ring_size       (tx_ring_size),
                .rx_desc_base       (rx_desc_base),
                .rx_ring_size       (rx_ring_size),
                .tx_busy            (dma_tx_busy),
                .rx_busy            (dma_rx_busy),
                .tx_pkt_cnt         (dma_tx_pkt_cnt),
                .rx_pkt_cnt         (dma_rx_pkt_cnt),
                .tx_err_cnt         (dma_tx_err_cnt),
                .rx_err_cnt         (dma_rx_err_cnt),
                
                // Interrupts
                .int_tx_complete    (dma_int_tx_complete),
                .int_rx_complete    (dma_int_rx_complete),
                .int_tx_error       (dma_int_tx_error),
                .int_rx_error       (dma_int_rx_error),
                
                // AXI-Stream to MAC TX
                .m_axis_tx_tdata    (mac_tx_axis_tdata),
                .m_axis_tx_tvalid   (mac_tx_axis_tvalid),
                .m_axis_tx_tlast    (mac_tx_axis_tlast),
                .m_axis_tx_tuser    (mac_tx_axis_tuser),
                .m_axis_tx_tready   (mac_tx_axis_tready),
                
                // AXI-Stream from MAC RX
                .s_axis_rx_tdata    (mac_rx_axis_tdata),
                .s_axis_rx_tvalid   (mac_rx_axis_tvalid),
                .s_axis_rx_tlast    (mac_rx_axis_tlast),
                .s_axis_rx_tuser    (mac_rx_axis_tuser),
                .s_axis_rx_tready   (mac_rx_axis_tready),
                
                // AXI4 Memory Interface
                .m_axi_awid         (m_axi_awid),
                .m_axi_awaddr       (m_axi_awaddr),
                .m_axi_awlen        (m_axi_awlen),
                .m_axi_awsize       (m_axi_awsize),
                .m_axi_awburst      (m_axi_awburst),
                .m_axi_awlock       (m_axi_awlock),
                .m_axi_awcache      (m_axi_awcache),
                .m_axi_awprot       (m_axi_awprot),
                .m_axi_awvalid      (m_axi_awvalid),
                .m_axi_awready      (m_axi_awready),
                .m_axi_wdata        (m_axi_wdata),
                .m_axi_wstrb        (m_axi_wstrb),
                .m_axi_wlast        (m_axi_wlast),
                .m_axi_wvalid       (m_axi_wvalid),
                .m_axi_wready       (m_axi_wready),
                .m_axi_bid          (m_axi_bid),
                .m_axi_bresp        (m_axi_bresp),
                .m_axi_bvalid       (m_axi_bvalid),
                .m_axi_bready       (m_axi_bready),
                .m_axi_arid         (m_axi_arid),
                .m_axi_araddr       (m_axi_araddr),
                .m_axi_arlen        (m_axi_arlen),
                .m_axi_arsize       (m_axi_arsize),
                .m_axi_arburst      (m_axi_arburst),
                .m_axi_arlock       (m_axi_arlock),
                .m_axi_arcache      (m_axi_arcache),
                .m_axi_arprot       (m_axi_arprot),
                .m_axi_arvalid      (m_axi_arvalid),
                .m_axi_arready      (m_axi_arready),
                .m_axi_rid          (m_axi_rid),
                .m_axi_rdata        (m_axi_rdata),
                .m_axi_rresp        (m_axi_rresp),
                .m_axi_rlast        (m_axi_rlast),
                .m_axi_rvalid       (m_axi_rvalid),
                .m_axi_rready       (m_axi_rready)
            );
        end else begin : gen_without_dma
            // Bypass mode - connect user AXI-Stream directly to MAC
            assign mac_tx_axis_tdata  = s_axis_tx_tdata;
            assign mac_tx_axis_tvalid = s_axis_tx_tvalid;
            assign mac_tx_axis_tlast  = s_axis_tx_tlast;
            assign mac_tx_axis_tuser  = s_axis_tx_tuser;
            assign s_axis_tx_tready   = mac_tx_axis_tready;
            
            assign m_axis_rx_tdata    = mac_rx_axis_tdata;
            assign m_axis_rx_tvalid   = mac_rx_axis_tvalid;
            assign m_axis_rx_tlast    = mac_rx_axis_tlast;
            assign m_axis_rx_tuser    = mac_rx_axis_tuser;
            assign mac_rx_axis_tready = m_axis_rx_tready;
            
            // Tie off DMA status signals
            assign dma_tx_busy      = 1'b0;
            assign dma_rx_busy      = 1'b0;
            assign dma_tx_pkt_cnt   = 32'h00000000;
            assign dma_rx_pkt_cnt   = 32'h00000000;
            assign dma_tx_err_cnt   = 32'h00000000;
            assign dma_rx_err_cnt   = 32'h00000000;
            assign dma_int_tx_complete = 1'b0;
            assign dma_int_rx_complete = 1'b0;
            assign dma_int_tx_error = 1'b0;
            assign dma_int_rx_error = 1'b0;
            
            // Tie off AXI4 memory interface
            assign m_axi_awid     = {M_AXI_ID_WIDTH{1'b0}};
            assign m_axi_awaddr   = {M_AXI_ADDR_WIDTH{1'b0}};
            assign m_axi_awlen    = 8'h00;
            assign m_axi_awsize   = 3'b000;
            assign m_axi_awburst  = 2'b01;
            assign m_axi_awlock   = 1'b0;
            assign m_axi_awcache  = 4'h0;
            assign m_axi_awprot   = 3'b000;
            assign m_axi_awvalid  = 1'b0;
            assign m_axi_wdata    = {M_AXI_DATA_WIDTH{1'b0}};
            assign m_axi_wstrb    = {(M_AXI_DATA_WIDTH/8){1'b0}};
            assign m_axi_wlast    = 1'b0;
            assign m_axi_wvalid   = 1'b0;
            assign m_axi_bready   = 1'b0;
            assign m_axi_arid     = {M_AXI_ID_WIDTH{1'b0}};
            assign m_axi_araddr   = {M_AXI_ADDR_WIDTH{1'b0}};
            assign m_axi_arlen    = 8'h00;
            assign m_axi_arsize   = 3'b000;
            assign m_axi_arburst  = 2'b01;
            assign m_axi_arlock   = 1'b0;
            assign m_axi_arcache  = 4'h0;
            assign m_axi_arprot   = 3'b000;
            assign m_axi_arvalid  = 1'b0;
            assign m_axi_rready   = 1'b0;
        end
    endgenerate

endmodule
