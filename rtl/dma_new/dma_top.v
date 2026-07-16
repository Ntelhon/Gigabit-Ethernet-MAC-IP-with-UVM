//==============================================================================
// File: dma_top.v
// Description: Scatter-Gather DMA Subsystem Top (Gigabit Ethernet class)
//
// Purpose:
//   Purely structural top level. Instantiates and wires:
//     dma_regs        - AXI4-Lite CSR block
//     dma_irq         - interrupt latch/mask/coalescing
//     dma_desc_tx     - TX descriptor ring engine
//     dma_desc_rx     - RX descriptor ring engine
//     dma_tx          - TX channel (fetch + FIFOs + stream master)
//     dma_rx          - RX channel (stream slave + FIFOs + writer)
//     dma_axi_rd_arb  - read masters {0: desc_tx, 1: desc_rx, 2: tx_fetch}
//     dma_axi_wr_arb  - write masters {0: desc_tx, 1: desc_rx, 2: rx_write}
//   onto ONE external AXI4 master port, one AXI4-Lite slave port and the
//   two 8-bit AXI-Stream ports toward the MAC.
//
// Interrupt gating: the per-channel CTRL.IRQ_EN bit gates the DONE events
// of its channel (error events always reach the interrupt controller).
// Final masking is INT_MASK inside dma_irq.
//
// Clocking: single clock domain (clk). MAC-side CDC is handled inside the
// MAC's own FIFOs; dma_sync_cell is reserved for future multi-clock use.
//
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_top #(
    parameter ADDR_WIDTH     = 64,      // System address width
    parameter AXI_DATA_W     = 64,      // AXI data width (desc engines: 32/64)
    parameter AXI_ID_W       = 4,       // AXI ID width
    parameter AXIS_DATA_W    = 8,       // MAC stream width
    parameter MAX_BURST_LEN  = 16,      // Max beats per AXI burst
    parameter TX_FIFO_DEPTH  = 2048,    // TX data FIFO (bytes)
    parameter RX_FIFO_DEPTH  = 4096,    // RX data FIFO (bytes)
    parameter PKT_FIFO_DEPTH = 16,      // Packet metadata FIFOs (entries)
    parameter LEN_W          = 16,      // Length field width
    parameter TX_AXI_ID      = 1,       // ID for TX payload reads
    parameter RX_AXI_ID      = 2,       // ID for RX payload writes
    parameter DESC_AXI_ID    = 0,       // ID for descriptor traffic
    parameter CSR_ADDR_W     = 8,       // CSR byte-address width
    parameter MAX_PKT_LEN    = 16383,   // Longest accepted RX packet
    parameter COAL_PRESCALE  = 1000     // clk cycles per coalescing tick
)(
    input  wire                     clk,
    input  wire                     rst_n,

    //--------------------------------------------------------------------------
    // AXI4-Lite slave (CSR)
    //--------------------------------------------------------------------------
    input  wire                     s_axil_awvalid,
    output wire                     s_axil_awready,
    input  wire [CSR_ADDR_W-1:0]    s_axil_awaddr,
    input  wire                     s_axil_wvalid,
    output wire                     s_axil_wready,
    input  wire [31:0]              s_axil_wdata,
    input  wire [3:0]               s_axil_wstrb,
    output wire                     s_axil_bvalid,
    input  wire                     s_axil_bready,
    output wire [1:0]               s_axil_bresp,
    input  wire                     s_axil_arvalid,
    output wire                     s_axil_arready,
    input  wire [CSR_ADDR_W-1:0]    s_axil_araddr,
    output wire                     s_axil_rvalid,
    input  wire                     s_axil_rready,
    output wire [31:0]              s_axil_rdata,
    output wire [1:0]               s_axil_rresp,

    //--------------------------------------------------------------------------
    // AXI4 master (system memory)
    //--------------------------------------------------------------------------
    output wire                     m_axi_awvalid,
    input  wire                     m_axi_awready,
    output wire [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output wire [7:0]               m_axi_awlen,
    output wire [2:0]               m_axi_awsize,
    output wire [1:0]               m_axi_awburst,
    output wire [AXI_ID_W-1:0]      m_axi_awid,
    output wire                     m_axi_wvalid,
    input  wire                     m_axi_wready,
    output wire [AXI_DATA_W-1:0]    m_axi_wdata,
    output wire [AXI_DATA_W/8-1:0]  m_axi_wstrb,
    output wire                     m_axi_wlast,
    input  wire                     m_axi_bvalid,
    output wire                     m_axi_bready,
    input  wire [1:0]               m_axi_bresp,
    input  wire [AXI_ID_W-1:0]      m_axi_bid,
    output wire                     m_axi_arvalid,
    input  wire                     m_axi_arready,
    output wire [ADDR_WIDTH-1:0]    m_axi_araddr,
    output wire [7:0]               m_axi_arlen,
    output wire [2:0]               m_axi_arsize,
    output wire [1:0]               m_axi_arburst,
    output wire [AXI_ID_W-1:0]      m_axi_arid,
    input  wire                     m_axi_rvalid,
    output wire                     m_axi_rready,
    input  wire [AXI_DATA_W-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire [AXI_ID_W-1:0]      m_axi_rid,

    //--------------------------------------------------------------------------
    // AXI-Stream to/from MAC
    //--------------------------------------------------------------------------
    output wire                     m_axis_tx_tvalid,
    input  wire                     m_axis_tx_tready,
    output wire [AXIS_DATA_W-1:0]   m_axis_tx_tdata,
    output wire                     m_axis_tx_tlast,
    output wire                     m_axis_tx_tuser,

    input  wire                     s_axis_rx_tvalid,
    output wire                     s_axis_rx_tready,
    input  wire [AXIS_DATA_W-1:0]   s_axis_rx_tdata,
    input  wire                     s_axis_rx_tlast,
    input  wire                     s_axis_rx_tuser,

    //--------------------------------------------------------------------------
    // Interrupt
    //--------------------------------------------------------------------------
    output wire                     dma_irq
);

    localparam WSTRB_W = AXI_DATA_W / 8;

    //--------------------------------------------------------------------------
    // Regs <-> channels / descriptor engines
    //--------------------------------------------------------------------------
    wire                    tx_enable,     rx_enable;
    wire                    tx_soft_reset, rx_soft_reset;
    wire                    tx_irq_en,     rx_irq_en;
    wire [ADDR_WIDTH-1:0]   tx_ring_base,  rx_ring_base;
    wire [15:0]             tx_ring_size,  rx_ring_size;
    wire [15:0]             tx_head_ptr,   rx_head_ptr;
    wire [15:0]             tx_tail_ptr,   rx_tail_ptr;
    wire [31:0]             tx_pkt_cnt,    rx_pkt_cnt;
    wire [31:0]             tx_byte_cnt,   rx_byte_cnt;
    wire [31:0]             rx_drop_cnt;

    wire                    txch_busy,   txch_halted, txch_error;
    wire                    rxch_busy,   rxch_halted, rxch_error;
    wire                    dtx_busy,    dtx_halted;
    wire                    drx_busy,    drx_halted;
    wire                    dtx_desc_err, drx_desc_err;

    //--------------------------------------------------------------------------
    // Descriptor dispatch / writeback
    //--------------------------------------------------------------------------
    wire                    txd_valid,  txd_ready;
    wire [ADDR_WIDTH-1:0]   txd_buf_addr;
    wire [LEN_W-1:0]        txd_buf_len;
    wire                    txd_sop, txd_eop, txd_irq_en_d;
    wire [15:0]             txd_index;
    wire                    txwb_valid, txwb_ready;
    wire [15:0]             txwb_index;
    wire                    txwb_err;

    wire                    rxd_valid,  rxd_ready;
    wire [ADDR_WIDTH-1:0]   rxd_buf_addr;
    wire [LEN_W-1:0]        rxd_buf_len;
    wire                    rxd_irq_en;
    wire [15:0]             rxd_index;
    wire                    rxwb_valid, rxwb_ready;
    wire [15:0]             rxwb_index;
    wire [LEN_W-1:0]        rxwb_length;
    wire [3:0]              rxwb_status;
    wire                    rxwb_irq_en;

    //--------------------------------------------------------------------------
    // Interrupt events
    //--------------------------------------------------------------------------
    wire                    ev_tx_done, ev_tx_err;
    wire                    ev_rx_done, ev_rx_err;
    wire [4:0]              int_status;
    wire [4:0]              int_clear;
    wire [4:0]              int_mask;
    wire [15:0]             int_coal_cnt, int_coal_time;

    //--------------------------------------------------------------------------
    // Internal AXI read masters {0: desc_tx, 1: desc_rx, 2: tx_fetch}
    //--------------------------------------------------------------------------
    wire                    dtx_arvalid,  drx_arvalid,  txf_arvalid;
    wire                    dtx_arready,  drx_arready,  txf_arready;
    wire [ADDR_WIDTH-1:0]   dtx_araddr,   drx_araddr,   txf_araddr;
    wire [7:0]              dtx_arlen,    drx_arlen,    txf_arlen;
    wire [2:0]              dtx_arsize,   drx_arsize,   txf_arsize;
    wire [1:0]              dtx_arburst,  drx_arburst,  txf_arburst;
    wire [AXI_ID_W-1:0]     dtx_arid,     drx_arid,     txf_arid;
    wire                    dtx_rvalid,   drx_rvalid,   txf_rvalid;
    wire                    dtx_rready,   drx_rready,   txf_rready;
    wire [AXI_DATA_W-1:0]   rd_rdata;
    wire [1:0]              rd_rresp;
    wire                    rd_rlast;
    wire [AXI_ID_W-1:0]     rd_rid;

    //--------------------------------------------------------------------------
    // Internal AXI write masters {0: desc_tx, 1: desc_rx, 2: rx_write}
    //--------------------------------------------------------------------------
    wire                    dtx_awvalid,  drx_awvalid,  rxw_awvalid;
    wire                    dtx_awready,  drx_awready,  rxw_awready;
    wire [ADDR_WIDTH-1:0]   dtx_awaddr,   drx_awaddr,   rxw_awaddr;
    wire [7:0]              dtx_awlen,    drx_awlen,    rxw_awlen;
    wire [2:0]              dtx_awsize,   drx_awsize,   rxw_awsize;
    wire [1:0]              dtx_awburst,  drx_awburst,  rxw_awburst;
    wire [AXI_ID_W-1:0]     dtx_awid,     drx_awid,     rxw_awid;
    wire                    dtx_wvalid,   drx_wvalid,   rxw_wvalid;
    wire                    dtx_wready,   drx_wready,   rxw_wready;
    wire [AXI_DATA_W-1:0]   dtx_wdata,    drx_wdata,    rxw_wdata;
    wire [WSTRB_W-1:0]      dtx_wstrb,    drx_wstrb,    rxw_wstrb;
    wire                    dtx_wlast,    drx_wlast,    rxw_wlast;
    wire                    dtx_bvalid,   drx_bvalid,   rxw_bvalid;
    wire                    dtx_bready,   drx_bready,   rxw_bready;
    wire [1:0]              wr_bresp;
    wire [AXI_ID_W-1:0]     wr_bid;

    //--------------------------------------------------------------------------
    // Composite channel status toward the CSR block
    //--------------------------------------------------------------------------
    wire tx_busy_all   = txch_busy   | dtx_busy;
    wire tx_halted_all = txch_halted | dtx_halted;
    wire rx_busy_all   = rxch_busy   | drx_busy;
    wire rx_halted_all = rxch_halted | drx_halted;

    // CTRL.IRQ_EN gates completion events only; errors always propagate
    wire ev_tx_done_g = ev_tx_done & tx_irq_en;
    wire ev_rx_done_g = ev_rx_done & rx_irq_en;
    wire ev_desc_err  = dtx_desc_err | drx_desc_err;

    //--------------------------------------------------------------------------
    // CSR block
    //--------------------------------------------------------------------------
    dma_regs #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CSR_ADDR_W (CSR_ADDR_W)
    ) u_regs (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),
        .s_axil_bresp   (s_axil_bresp),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),
        .s_axil_araddr  (s_axil_araddr),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),
        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),
        .tx_enable      (tx_enable),
        .tx_soft_reset  (tx_soft_reset),
        .tx_irq_en      (tx_irq_en),
        .tx_busy        (tx_busy_all),
        .tx_halted      (tx_halted_all),
        .tx_error       (txch_error),
        .tx_ring_base   (tx_ring_base),
        .tx_ring_size   (tx_ring_size),
        .tx_head_ptr    (tx_head_ptr),
        .tx_tail_ptr    (tx_tail_ptr),
        .tx_pkt_cnt     (tx_pkt_cnt),
        .tx_byte_cnt    (tx_byte_cnt),
        .rx_enable      (rx_enable),
        .rx_soft_reset  (rx_soft_reset),
        .rx_irq_en      (rx_irq_en),
        .rx_busy        (rx_busy_all),
        .rx_halted      (rx_halted_all),
        .rx_error       (rxch_error),
        .rx_ring_base   (rx_ring_base),
        .rx_ring_size   (rx_ring_size),
        .rx_head_ptr    (rx_head_ptr),
        .rx_tail_ptr    (rx_tail_ptr),
        .rx_pkt_cnt     (rx_pkt_cnt),
        .rx_byte_cnt    (rx_byte_cnt),
        .rx_drop_cnt    (rx_drop_cnt),
        .int_status     (int_status),
        .int_clear      (int_clear),
        .int_mask       (int_mask),
        .int_coal_cnt   (int_coal_cnt),
        .int_coal_time  (int_coal_time)
    );

    //--------------------------------------------------------------------------
    // Interrupt controller
    //--------------------------------------------------------------------------
    dma_irq #(
        .N_INT         (5),
        .COAL_TIMER_W  (16),
        .COAL_PRESCALE (COAL_PRESCALE)
    ) u_irq (
        .clk              (clk),
        .rst_n            (rst_n),
        .ev_tx_done       (ev_tx_done_g),
        .ev_tx_err        (ev_tx_err),
        .ev_rx_done       (ev_rx_done_g),
        .ev_rx_err        (ev_rx_err),
        .ev_desc_err      (ev_desc_err),
        .int_clear        (int_clear),
        .int_mask         (int_mask),
        .coal_cnt_thresh  (int_coal_cnt),
        .coal_time_thresh (int_coal_time),
        .int_status       (int_status),
        .dma_irq          (dma_irq)
    );

    //--------------------------------------------------------------------------
    // TX descriptor engine
    //--------------------------------------------------------------------------
    dma_desc_tx #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .AXI_DATA_W  (AXI_DATA_W),
        .AXI_ID_W    (AXI_ID_W),
        .AXI_ID      (DESC_AXI_ID),
        .LEN_W       (LEN_W),
        .DESC_SIZE_B (16)
    ) u_desc_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (tx_enable),
        .soft_reset    (tx_soft_reset),
        .ring_base     (tx_ring_base),
        .ring_size     (tx_ring_size),
        .head_ptr      (tx_head_ptr),
        .tail_ptr      (tx_tail_ptr),
        .busy          (dtx_busy),
        .halted        (dtx_halted),
        .desc_err      (dtx_desc_err),
        .desc_valid    (txd_valid),
        .desc_ready    (txd_ready),
        .desc_buf_addr (txd_buf_addr),
        .desc_buf_len  (txd_buf_len),
        .desc_sop      (txd_sop),
        .desc_eop      (txd_eop),
        .desc_irq_en   (txd_irq_en_d),
        .desc_index    (txd_index),
        .wb_valid      (txwb_valid),
        .wb_ready      (txwb_ready),
        .wb_index      (txwb_index),
        .wb_err        (txwb_err),
        .ev_tx_done    (ev_tx_done),
        .ev_tx_err     (ev_tx_err),
        .m_axi_arvalid (dtx_arvalid),
        .m_axi_arready (dtx_arready),
        .m_axi_araddr  (dtx_araddr),
        .m_axi_arlen   (dtx_arlen),
        .m_axi_arsize  (dtx_arsize),
        .m_axi_arburst (dtx_arburst),
        .m_axi_arid    (dtx_arid),
        .m_axi_rvalid  (dtx_rvalid),
        .m_axi_rready  (dtx_rready),
        .m_axi_rdata   (rd_rdata),
        .m_axi_rresp   (rd_rresp),
        .m_axi_rlast   (rd_rlast),
        .m_axi_rid     (rd_rid),
        .m_axi_awvalid (dtx_awvalid),
        .m_axi_awready (dtx_awready),
        .m_axi_awaddr  (dtx_awaddr),
        .m_axi_awlen   (dtx_awlen),
        .m_axi_awsize  (dtx_awsize),
        .m_axi_awburst (dtx_awburst),
        .m_axi_awid    (dtx_awid),
        .m_axi_wvalid  (dtx_wvalid),
        .m_axi_wready  (dtx_wready),
        .m_axi_wdata   (dtx_wdata),
        .m_axi_wstrb   (dtx_wstrb),
        .m_axi_wlast   (dtx_wlast),
        .m_axi_bvalid  (dtx_bvalid),
        .m_axi_bready  (dtx_bready),
        .m_axi_bresp   (wr_bresp),
        .m_axi_bid     (wr_bid)
    );

    //--------------------------------------------------------------------------
    // RX descriptor engine
    //--------------------------------------------------------------------------
    dma_desc_rx #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .AXI_DATA_W  (AXI_DATA_W),
        .AXI_ID_W    (AXI_ID_W),
        .AXI_ID      (DESC_AXI_ID),
        .LEN_W       (LEN_W),
        .DESC_SIZE_B (16)
    ) u_desc_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (rx_enable),
        .soft_reset    (rx_soft_reset),
        .ring_base     (rx_ring_base),
        .ring_size     (rx_ring_size),
        .head_ptr      (rx_head_ptr),
        .tail_ptr      (rx_tail_ptr),
        .busy          (drx_busy),
        .halted        (drx_halted),
        .desc_err      (drx_desc_err),
        .desc_valid    (rxd_valid),
        .desc_ready    (rxd_ready),
        .desc_buf_addr (rxd_buf_addr),
        .desc_buf_len  (rxd_buf_len),
        .desc_irq_en   (rxd_irq_en),
        .desc_index    (rxd_index),
        .wb_valid      (rxwb_valid),
        .wb_ready      (rxwb_ready),
        .wb_index      (rxwb_index),
        .wb_length     (rxwb_length),
        .wb_status     (rxwb_status),
        .wb_irq_en     (rxwb_irq_en),
        .ev_rx_done    (ev_rx_done),
        .ev_rx_err     (ev_rx_err),
        .m_axi_arvalid (drx_arvalid),
        .m_axi_arready (drx_arready),
        .m_axi_araddr  (drx_araddr),
        .m_axi_arlen   (drx_arlen),
        .m_axi_arsize  (drx_arsize),
        .m_axi_arburst (drx_arburst),
        .m_axi_arid    (drx_arid),
        .m_axi_rvalid  (drx_rvalid),
        .m_axi_rready  (drx_rready),
        .m_axi_rdata   (rd_rdata),
        .m_axi_rresp   (rd_rresp),
        .m_axi_rlast   (rd_rlast),
        .m_axi_rid     (rd_rid),
        .m_axi_awvalid (drx_awvalid),
        .m_axi_awready (drx_awready),
        .m_axi_awaddr  (drx_awaddr),
        .m_axi_awlen   (drx_awlen),
        .m_axi_awsize  (drx_awsize),
        .m_axi_awburst (drx_awburst),
        .m_axi_awid    (drx_awid),
        .m_axi_wvalid  (drx_wvalid),
        .m_axi_wready  (drx_wready),
        .m_axi_wdata   (drx_wdata),
        .m_axi_wstrb   (drx_wstrb),
        .m_axi_wlast   (drx_wlast),
        .m_axi_bvalid  (drx_bvalid),
        .m_axi_bready  (drx_bready),
        .m_axi_bresp   (wr_bresp),
        .m_axi_bid     (wr_bid)
    );

    //--------------------------------------------------------------------------
    // TX channel
    //--------------------------------------------------------------------------
    dma_tx #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .AXI_DATA_W     (AXI_DATA_W),
        .AXI_ID_W       (AXI_ID_W),
        .AXI_ID         (TX_AXI_ID),
        .AXIS_DATA_W    (AXIS_DATA_W),
        .MAX_BURST_LEN  (MAX_BURST_LEN),
        .FIFO_DEPTH     (TX_FIFO_DEPTH),
        .PKT_FIFO_DEPTH (PKT_FIFO_DEPTH),
        .LEN_W          (LEN_W)
    ) u_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (tx_enable),
        .soft_reset    (tx_soft_reset),
        .busy          (txch_busy),
        .halted        (txch_halted),
        .error         (txch_error),
        .desc_valid    (txd_valid),
        .desc_ready    (txd_ready),
        .desc_buf_addr (txd_buf_addr),
        .desc_buf_len  (txd_buf_len),
        .desc_sop      (txd_sop),
        .desc_eop      (txd_eop),
        .desc_index    (txd_index),
        .wb_valid      (txwb_valid),
        .wb_ready      (txwb_ready),
        .wb_index      (txwb_index),
        .wb_err        (txwb_err),
        .m_axi_arvalid (txf_arvalid),
        .m_axi_arready (txf_arready),
        .m_axi_araddr  (txf_araddr),
        .m_axi_arlen   (txf_arlen),
        .m_axi_arsize  (txf_arsize),
        .m_axi_arburst (txf_arburst),
        .m_axi_arid    (txf_arid),
        .m_axi_rvalid  (txf_rvalid),
        .m_axi_rready  (txf_rready),
        .m_axi_rdata   (rd_rdata),
        .m_axi_rresp   (rd_rresp),
        .m_axi_rlast   (rd_rlast),
        .m_axi_rid     (rd_rid),
        .m_axis_tvalid (m_axis_tx_tvalid),
        .m_axis_tready (m_axis_tx_tready),
        .m_axis_tdata  (m_axis_tx_tdata),
        .m_axis_tlast  (m_axis_tx_tlast),
        .m_axis_tuser  (m_axis_tx_tuser),
        .tx_pkt_cnt    (tx_pkt_cnt),
        .tx_byte_cnt   (tx_byte_cnt)
    );

    //--------------------------------------------------------------------------
    // RX channel
    //--------------------------------------------------------------------------
    dma_rx #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .AXI_DATA_W     (AXI_DATA_W),
        .AXI_ID_W       (AXI_ID_W),
        .AXI_ID         (RX_AXI_ID),
        .AXIS_DATA_W    (AXIS_DATA_W),
        .MAX_BURST_LEN  (MAX_BURST_LEN),
        .FIFO_DEPTH     (RX_FIFO_DEPTH),
        .PKT_FIFO_DEPTH (PKT_FIFO_DEPTH),
        .LEN_W          (LEN_W),
        .MAX_PKT_LEN    (MAX_PKT_LEN)
    ) u_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (rx_enable),
        .soft_reset    (rx_soft_reset),
        .busy          (rxch_busy),
        .halted        (rxch_halted),
        .error         (rxch_error),
        .desc_valid    (rxd_valid),
        .desc_ready    (rxd_ready),
        .desc_buf_addr (rxd_buf_addr),
        .desc_buf_len  (rxd_buf_len),
        .desc_irq_en   (rxd_irq_en),
        .desc_index    (rxd_index),
        .wb_valid      (rxwb_valid),
        .wb_ready      (rxwb_ready),
        .wb_index      (rxwb_index),
        .wb_length     (rxwb_length),
        .wb_status     (rxwb_status),
        .wb_irq_en     (rxwb_irq_en),
        .m_axi_awvalid (rxw_awvalid),
        .m_axi_awready (rxw_awready),
        .m_axi_awaddr  (rxw_awaddr),
        .m_axi_awlen   (rxw_awlen),
        .m_axi_awsize  (rxw_awsize),
        .m_axi_awburst (rxw_awburst),
        .m_axi_awid    (rxw_awid),
        .m_axi_wvalid  (rxw_wvalid),
        .m_axi_wready  (rxw_wready),
        .m_axi_wdata   (rxw_wdata),
        .m_axi_wstrb   (rxw_wstrb),
        .m_axi_wlast   (rxw_wlast),
        .m_axi_bvalid  (rxw_bvalid),
        .m_axi_bready  (rxw_bready),
        .m_axi_bresp   (wr_bresp),
        .m_axi_bid     (wr_bid),
        .s_axis_tvalid (s_axis_rx_tvalid),
        .s_axis_tready (s_axis_rx_tready),
        .s_axis_tdata  (s_axis_rx_tdata),
        .s_axis_tlast  (s_axis_rx_tlast),
        .s_axis_tuser  (s_axis_rx_tuser),
        .rx_pkt_cnt    (rx_pkt_cnt),
        .rx_byte_cnt   (rx_byte_cnt),
        .rx_drop_cnt   (rx_drop_cnt)
    );

    //--------------------------------------------------------------------------
    // AXI read arbiter {0: desc_tx, 1: desc_rx, 2: tx_fetch}
    //--------------------------------------------------------------------------
    dma_axi_rd_arb #(
        .N_MASTERS  (3),
        .ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_W (AXI_DATA_W),
        .AXI_ID_W   (AXI_ID_W)
    ) u_rd_arb (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_arvalid     ({txf_arvalid, drx_arvalid, dtx_arvalid}),
        .s_arready     ({txf_arready, drx_arready, dtx_arready}),
        .s_araddr      ({txf_araddr,  drx_araddr,  dtx_araddr}),
        .s_arlen       ({txf_arlen,   drx_arlen,   dtx_arlen}),
        .s_arsize      ({txf_arsize,  drx_arsize,  dtx_arsize}),
        .s_arburst     ({txf_arburst, drx_arburst, dtx_arburst}),
        .s_arid        ({txf_arid,    drx_arid,    dtx_arid}),
        .s_rvalid      ({txf_rvalid,  drx_rvalid,  dtx_rvalid}),
        .s_rready      ({txf_rready,  drx_rready,  dtx_rready}),
        .s_rdata       (rd_rdata),
        .s_rresp       (rd_rresp),
        .s_rlast       (rd_rlast),
        .s_rid         (rd_rid),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arlen   (m_axi_arlen),
        .m_axi_arsize  (m_axi_arsize),
        .m_axi_arburst (m_axi_arburst),
        .m_axi_arid    (m_axi_arid),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready),
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rresp   (m_axi_rresp),
        .m_axi_rlast   (m_axi_rlast),
        .m_axi_rid     (m_axi_rid)
    );

    //--------------------------------------------------------------------------
    // AXI write arbiter {0: desc_tx, 1: desc_rx, 2: rx_write}
    //--------------------------------------------------------------------------
    dma_axi_wr_arb #(
        .N_MASTERS  (3),
        .ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_W (AXI_DATA_W),
        .AXI_ID_W   (AXI_ID_W)
    ) u_wr_arb (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_awvalid     ({rxw_awvalid, drx_awvalid, dtx_awvalid}),
        .s_awready     ({rxw_awready, drx_awready, dtx_awready}),
        .s_awaddr      ({rxw_awaddr,  drx_awaddr,  dtx_awaddr}),
        .s_awlen       ({rxw_awlen,   drx_awlen,   dtx_awlen}),
        .s_awsize      ({rxw_awsize,  drx_awsize,  dtx_awsize}),
        .s_awburst     ({rxw_awburst, drx_awburst, dtx_awburst}),
        .s_awid        ({rxw_awid,    drx_awid,    dtx_awid}),
        .s_wvalid      ({rxw_wvalid,  drx_wvalid,  dtx_wvalid}),
        .s_wready      ({rxw_wready,  drx_wready,  dtx_wready}),
        .s_wdata       ({rxw_wdata,   drx_wdata,   dtx_wdata}),
        .s_wstrb       ({rxw_wstrb,   drx_wstrb,   dtx_wstrb}),
        .s_wlast       ({rxw_wlast,   drx_wlast,   dtx_wlast}),
        .s_bvalid      ({rxw_bvalid,  drx_bvalid,  dtx_bvalid}),
        .s_bready      ({rxw_bready,  drx_bready,  dtx_bready}),
        .s_bresp       (wr_bresp),
        .s_bid         (wr_bid),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awlen   (m_axi_awlen),
        .m_axi_awsize  (m_axi_awsize),
        .m_axi_awburst (m_axi_awburst),
        .m_axi_awid    (m_axi_awid),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wlast   (m_axi_wlast),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready),
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_bid     (m_axi_bid)
    );

endmodule
