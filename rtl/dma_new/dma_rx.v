//==============================================================================
// File: dma_rx.v
// Description: RX DMA Channel Top (MAC -> memory)
//
// Purpose:
//   Container for the complete RX data path:
//     dma_rx_stream - AXI-Stream slave, pushes packets with commit/rewind
//     dma_fifo      - RX data FIFO (PKT_MODE) + packet metadata FIFO
//     dma_rx_write  - AXI write master, stores packets into descriptors
//   The descriptor dispatch and writeback interfaces of dma_rx_write are
//   routed through this module to dma_desc_rx; the channel snoops the
//   writeback handshake to maintain the sticky error flag.
//
// Soft reset: srst_hold is asserted from the soft_reset pulse until the
// write engine drains its in-flight AXI burst (zero-strobe completion);
// the FIFOs are flushed for the whole window, the stream endpoint resets
// immediately.
//
// Statistics (hard-reset only):
//   rx_pkt_cnt  - packets fully written to memory (writebacks issued)
//   rx_byte_cnt - payload bytes accepted from the MAC
//   rx_drop_cnt - packets dropped by the stream endpoint (overflow/oversize)
//
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_rx #(
    parameter ADDR_WIDTH     = 64,
    parameter AXI_DATA_W     = 64,
    parameter AXI_ID_W       = 4,
    parameter AXI_ID         = 2,
    parameter AXIS_DATA_W    = 8,
    parameter MAX_BURST_LEN  = 16,
    parameter FIFO_DEPTH     = 4096,    // RX data FIFO depth (bytes)
    parameter PKT_FIFO_DEPTH = 16,      // Packet metadata FIFO depth
    parameter LEN_W          = 16,
    parameter MAX_PKT_LEN    = 16383    // Longest accepted packet (bytes)
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Control / status
    input  wire                     enable,
    input  wire                     soft_reset,     // 1-cycle pulse
    output wire                     busy,
    output wire                     halted,         // Reserved (desc engine halts)
    output reg                      error,          // Sticky, cleared by soft reset

    // Descriptor dispatch (from dma_desc_rx)
    input  wire                     desc_valid,
    output wire                     desc_ready,
    input  wire [ADDR_WIDTH-1:0]    desc_buf_addr,
    input  wire [LEN_W-1:0]         desc_buf_len,
    input  wire                     desc_irq_en,
    input  wire [15:0]              desc_index,

    // Writeback request (to dma_desc_rx)
    output wire                     wb_valid,
    input  wire                     wb_ready,
    output wire [15:0]              wb_index,
    output wire [LEN_W-1:0]         wb_length,
    output wire [3:0]               wb_status,      // {axi,trunc,crc,done}
    output wire                     wb_irq_en,

    // AXI write master (through dma_axi_wr_arb)
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

    // AXI-Stream slave (from MAC)
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire [AXIS_DATA_W-1:0]   s_axis_tdata,
    input  wire                     s_axis_tlast,
    input  wire                     s_axis_tuser,

    // Statistics
    output reg  [31:0]              rx_pkt_cnt,
    output reg  [31:0]              rx_byte_cnt,
    output reg  [31:0]              rx_drop_cnt
);

    //--------------------------------------------------------------------------
    // Internal wires
    //--------------------------------------------------------------------------
    reg              srst_hold;

    // Data FIFO (PKT_MODE)
    wire             dfifo_wr_en;
    wire [7:0]       dfifo_wr_data;
    wire             dfifo_full;
    wire             dfifo_commit;
    wire             dfifo_rewind;
    wire             dfifo_rd_en;
    wire [7:0]       dfifo_rd_data;
    wire             dfifo_empty;

    // Packet metadata FIFO
    wire             mfifo_wr_en;
    wire [LEN_W+1:0] mfifo_wr_data;
    wire             mfifo_full;
    wire             mfifo_rd_en;
    wire [LEN_W+1:0] mfifo_rd_data;
    wire             mfifo_empty;

    // Statistics pulses
    wire             pkt_rcvd;
    wire             pkt_dropped;
    wire             byte_rcvd;
    wire             pkt_written;
    wire             rxw_busy;

    //--------------------------------------------------------------------------
    // Soft reset hold: flush FIFOs until the write engine drains
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            srst_hold <= 1'b0;
        end else if (soft_reset) begin
            srst_hold <= 1'b1;
        end else if (srst_hold && !rxw_busy) begin
            srst_hold <= 1'b0;
        end
    end

    wire fifo_flush = srst_hold | soft_reset;

    //--------------------------------------------------------------------------
    // Sticky error: any writeback that reports an AXI error
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error <= 1'b0;
        end else if (soft_reset) begin
            error <= 1'b0;
        end else if (wb_valid && wb_ready && wb_status[3]) begin
            error <= 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // Composite status
    //--------------------------------------------------------------------------
    assign busy   = rxw_busy | ~mfifo_empty | ~dfifo_empty;
    assign halted = 1'b0;   // Channel never self-halts; desc engine does

    //--------------------------------------------------------------------------
    // Statistics (hard reset only)
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_pkt_cnt  <= 32'd0;
            rx_byte_cnt <= 32'd0;
            rx_drop_cnt <= 32'd0;
        end else begin
            if (pkt_written) begin
                rx_pkt_cnt <= rx_pkt_cnt + 32'd1;
            end
            if (byte_rcvd) begin
                rx_byte_cnt <= rx_byte_cnt + 32'd1;
            end
            if (pkt_dropped) begin
                rx_drop_cnt <= rx_drop_cnt + 32'd1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Stream endpoint (MAC -> byte FIFO, commit/rewind)
    //--------------------------------------------------------------------------
    dma_rx_stream #(
        .AXIS_DATA_W (AXIS_DATA_W),
        .LEN_W       (LEN_W),
        .MAX_PKT_LEN (MAX_PKT_LEN)
    ) u_stream (
        .clk           (clk),
        .rst_n         (rst_n),
        .soft_reset    (fifo_flush),
        .enable        (enable),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tuser  (s_axis_tuser),
        .fifo_wr_en    (dfifo_wr_en),
        .fifo_wr_data  (dfifo_wr_data),
        .fifo_full     (dfifo_full),
        .fifo_commit   (dfifo_commit),
        .fifo_rewind   (dfifo_rewind),
        .meta_wr_en    (mfifo_wr_en),
        .meta_wr_data  (mfifo_wr_data),
        .meta_full     (mfifo_full),
        .pkt_rcvd      (pkt_rcvd),
        .pkt_dropped   (pkt_dropped),
        .byte_rcvd     (byte_rcvd)
    );

    //--------------------------------------------------------------------------
    // RX data FIFO (packet mode: reader sees only committed packets)
    //--------------------------------------------------------------------------
    dma_fifo #(
        .DATA_W        (8),
        .DEPTH         (FIFO_DEPTH),
        .AFULL_THRESH  (FIFO_DEPTH - 4),
        .AEMPTY_THRESH (4),
        .PKT_MODE      (1)
    ) u_data_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .flush        (fifo_flush),
        .wr_en        (dfifo_wr_en),
        .wr_data      (dfifo_wr_data),
        .full         (dfifo_full),
        .almost_full  (),
        .commit       (dfifo_commit),
        .rewind       (dfifo_rewind),
        .rd_en        (dfifo_rd_en),
        .rd_data      (dfifo_rd_data),
        .empty        (dfifo_empty),
        .almost_empty (),
        .count        (),
        .overflow     (),
        .underflow    ()
    );

    //--------------------------------------------------------------------------
    // Packet metadata FIFO ({err_crc, rsvd, length} per committed packet)
    //--------------------------------------------------------------------------
    dma_fifo #(
        .DATA_W        (LEN_W + 2),
        .DEPTH         (PKT_FIFO_DEPTH),
        .AFULL_THRESH  (PKT_FIFO_DEPTH - 1),
        .AEMPTY_THRESH (1),
        .PKT_MODE      (0)
    ) u_meta_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .flush        (fifo_flush),
        .wr_en        (mfifo_wr_en),
        .wr_data      (mfifo_wr_data),
        .full         (mfifo_full),
        .almost_full  (),
        .commit       (1'b0),
        .rewind       (1'b0),
        .rd_en        (mfifo_rd_en),
        .rd_data      (mfifo_rd_data),
        .empty        (mfifo_empty),
        .almost_empty (),
        .count        (),
        .overflow     (),
        .underflow    ()
    );

    //--------------------------------------------------------------------------
    // Write engine (byte FIFO -> AXI, descriptor pairing + writeback)
    //--------------------------------------------------------------------------
    dma_rx_write #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .AXI_DATA_W    (AXI_DATA_W),
        .AXI_ID_W      (AXI_ID_W),
        .AXI_ID        (AXI_ID),
        .MAX_BURST_LEN (MAX_BURST_LEN),
        .LEN_W         (LEN_W)
    ) u_write (
        .clk           (clk),
        .rst_n         (rst_n),
        .soft_reset    (soft_reset),
        .meta_rd_en    (mfifo_rd_en),
        .meta_rd_data  (mfifo_rd_data),
        .meta_empty    (mfifo_empty),
        .fifo_rd_en    (dfifo_rd_en),
        .fifo_rd_data  (dfifo_rd_data),
        .fifo_empty    (dfifo_empty),
        .desc_valid    (desc_valid),
        .desc_ready    (desc_ready),
        .desc_buf_addr (desc_buf_addr),
        .desc_buf_len  (desc_buf_len),
        .desc_irq_en   (desc_irq_en),
        .desc_index    (desc_index),
        .wb_valid      (wb_valid),
        .wb_ready      (wb_ready),
        .wb_index      (wb_index),
        .wb_length     (wb_length),
        .wb_status     (wb_status),
        .wb_irq_en     (wb_irq_en),
        .pkt_written   (pkt_written),
        .busy          (rxw_busy),
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
