//==============================================================================
// File: dma_tx.v
// Description: TX DMA Channel Top (memory -> MAC)
//
// Purpose:
//   Container for the complete TX data path:
//     dma_tx_fetch  - AXI read master, pushes payload bytes
//     dma_fifo      - TX data FIFO (bytes) + packet metadata FIFO
//     dma_tx_stream - AXI-Stream master toward the MAC
//   plus a small channel FSM that turns each dispatched descriptor into a
//   fetch command and returns a writeback request when the fetch completes.
//
// Channel FSM: CH_IDLE -> CH_CMD -> CH_WAIT -> CH_WB -> CH_IDLE
//
// Soft reset: srst_hold is asserted from the soft_reset pulse until the
// fetch engine drains its in-flight AXI burst; the FIFOs are flushed for
// the whole window and the stream endpoint resets immediately.
//
// Statistics (hard-reset only, survive soft reset):
//   tx_pkt_cnt  - packets whose tlast was accepted by the MAC
//   tx_byte_cnt - payload bytes accepted by the MAC
//
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_tx #(
    parameter ADDR_WIDTH    = 64,
    parameter AXI_DATA_W    = 64,
    parameter AXI_ID_W      = 4,
    parameter AXI_ID        = 1,
    parameter AXIS_DATA_W   = 8,
    parameter MAX_BURST_LEN = 16,
    parameter FIFO_DEPTH    = 2048,     // TX data FIFO depth (bytes)
    parameter PKT_FIFO_DEPTH = 16,      // Packet metadata FIFO depth
    parameter LEN_W         = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Control / status
    input  wire                     enable,
    input  wire                     soft_reset,     // 1-cycle pulse
    output wire                     busy,
    output wire                     halted,         // Reserved (desc engine halts)
    output reg                      error,          // Sticky, cleared by soft reset

    // Descriptor dispatch (from dma_desc_tx)
    input  wire                     desc_valid,
    output wire                     desc_ready,
    input  wire [ADDR_WIDTH-1:0]    desc_buf_addr,
    input  wire [LEN_W-1:0]         desc_buf_len,
    input  wire                     desc_sop,       // Informational
    input  wire                     desc_eop,
    input  wire [15:0]              desc_index,

    // Writeback request (to dma_desc_tx)
    output reg                      wb_valid,
    input  wire                     wb_ready,
    output reg  [15:0]              wb_index,
    output reg                      wb_err,

    // AXI read master (through dma_axi_rd_arb)
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

    // AXI-Stream master (to MAC)
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire [AXIS_DATA_W-1:0]   m_axis_tdata,
    output wire                     m_axis_tlast,
    output wire                     m_axis_tuser,

    // Statistics
    output reg  [31:0]              tx_pkt_cnt,
    output reg  [31:0]              tx_byte_cnt
);

    localparam AXI_BYTES = AXI_DATA_W / 8;

    //--------------------------------------------------------------------------
    // Channel FSM states
    //--------------------------------------------------------------------------
    localparam [1:0] CH_IDLE = 2'd0,    // Wait for a dispatched descriptor
                     CH_CMD  = 2'd1,    // Hand the fetch command over
                     CH_WAIT = 2'd2,    // Fetch in progress
                     CH_WB   = 2'd3;    // Writeback handshake

    reg [1:0]            ch_state;

    //--------------------------------------------------------------------------
    // Internal wires
    //--------------------------------------------------------------------------
    reg                  srst_hold;     // Held until fetch engine drains

    reg                  cmd_valid;
    reg [ADDR_WIDTH-1:0] cmd_addr;
    reg [LEN_W-1:0]      cmd_len;
    reg                  cmd_eop;
    reg [15:0]           cmd_meta;
    wire                 cmd_ready;

    wire                 done_valid;
    wire                 done_err;
    wire [15:0]          done_meta;

    wire                 fetch_busy;
    wire                 stream_busy;

    // Data FIFO
    wire                 dfifo_wr_en;
    wire [7:0]           dfifo_wr_data;
    wire                 dfifo_full;
    wire                 dfifo_afull;
    wire                 dfifo_rd_en;
    wire [7:0]           dfifo_rd_data;
    wire                 dfifo_empty;

    // Packet metadata FIFO
    wire                 mfifo_wr_en;
    wire [LEN_W:0]       mfifo_wr_data;
    wire                 mfifo_full;
    wire                 mfifo_rd_en;
    wire [LEN_W:0]       mfifo_rd_data;
    wire                 mfifo_empty;

    // Statistics pulses
    wire                 pkt_sent;
    wire                 byte_sent;

    //--------------------------------------------------------------------------
    // Channel FSM: descriptor -> fetch command -> writeback
    //--------------------------------------------------------------------------
    assign desc_ready = (ch_state == CH_IDLE) && !srst_hold && !soft_reset;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ch_state  <= CH_IDLE;
            cmd_valid <= 1'b0;
            cmd_addr  <= {ADDR_WIDTH{1'b0}};
            cmd_len   <= {LEN_W{1'b0}};
            cmd_eop   <= 1'b0;
            cmd_meta  <= 16'd0;
            wb_valid  <= 1'b0;
            wb_index  <= 16'd0;
            wb_err    <= 1'b0;
            error     <= 1'b0;
        end else if (soft_reset) begin
            ch_state  <= CH_IDLE;
            cmd_valid <= 1'b0;
            wb_valid  <= 1'b0;
            error     <= 1'b0;
        end else begin
            case (ch_state)
                CH_IDLE: begin
                    if (desc_valid && desc_ready) begin
                        cmd_addr  <= desc_buf_addr;
                        cmd_len   <= desc_buf_len;
                        cmd_eop   <= desc_eop;
                        cmd_meta  <= desc_index;
                        cmd_valid <= 1'b1;
                        ch_state  <= CH_CMD;
                    end
                end

                CH_CMD: begin
                    if (cmd_ready) begin
                        cmd_valid <= 1'b0;
                        ch_state  <= CH_WAIT;
                    end
                end

                CH_WAIT: begin
                    if (done_valid) begin
                        wb_valid <= 1'b1;
                        wb_index <= done_meta;
                        wb_err   <= done_err;
                        if (done_err) begin
                            error <= 1'b1;
                        end
                        ch_state <= CH_WB;
                    end
                end

                CH_WB: begin
                    if (wb_ready) begin
                        wb_valid <= 1'b0;
                        ch_state <= CH_IDLE;
                    end
                end

                default: begin
                    ch_state <= CH_IDLE;
                end
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Soft reset hold: flush FIFOs until the fetch engine drains
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            srst_hold <= 1'b0;
        end else if (soft_reset) begin
            srst_hold <= 1'b1;
        end else if (srst_hold && !fetch_busy) begin
            srst_hold <= 1'b0;
        end
    end

    wire fifo_flush = srst_hold | soft_reset;

    //--------------------------------------------------------------------------
    // Composite status
    //--------------------------------------------------------------------------
    assign busy   = (ch_state != CH_IDLE) | fetch_busy | stream_busy
                    | ~dfifo_empty;
    assign halted = 1'b0;   // Channel never self-halts; desc engine does

    //--------------------------------------------------------------------------
    // Statistics (hard reset only)
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_pkt_cnt  <= 32'd0;
            tx_byte_cnt <= 32'd0;
        end else begin
            if (pkt_sent) begin
                tx_pkt_cnt <= tx_pkt_cnt + 32'd1;
            end
            if (byte_sent) begin
                tx_byte_cnt <= tx_byte_cnt + 32'd1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Fetch engine (AXI read -> byte FIFO)
    //--------------------------------------------------------------------------
    dma_tx_fetch #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .AXI_DATA_W    (AXI_DATA_W),
        .AXI_ID_W      (AXI_ID_W),
        .AXI_ID        (AXI_ID),
        .MAX_BURST_LEN (MAX_BURST_LEN),
        .LEN_W         (LEN_W)
    ) u_fetch (
        .clk              (clk),
        .rst_n            (rst_n),
        .soft_reset       (soft_reset),
        .cmd_valid        (cmd_valid),
        .cmd_ready        (cmd_ready),
        .cmd_addr         (cmd_addr),
        .cmd_len          (cmd_len),
        .cmd_eop          (cmd_eop),
        .cmd_meta         (cmd_meta),
        .done_valid       (done_valid),
        .done_err         (done_err),
        .done_meta        (done_meta),
        .fifo_wr_en       (dfifo_wr_en),
        .fifo_wr_data     (dfifo_wr_data),
        .fifo_afull       (dfifo_afull),
        .fifo_full        (dfifo_full),
        .pkt_meta_wr_en   (mfifo_wr_en),
        .pkt_meta_wr_data (mfifo_wr_data),
        .pkt_meta_full    (mfifo_full),
        .busy             (fetch_busy),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arid       (m_axi_arid),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rid        (m_axi_rid)
    );

    //--------------------------------------------------------------------------
    // TX data FIFO. AFULL_THRESH reserves one max burst of headroom so the
    // fetch engine's !almost_full AR gate guarantees the burst always fits.
    //--------------------------------------------------------------------------
    dma_fifo #(
        .DATA_W        (8),
        .DEPTH         (FIFO_DEPTH),
        .AFULL_THRESH  (FIFO_DEPTH - MAX_BURST_LEN*AXI_BYTES),
        .AEMPTY_THRESH (4),
        .PKT_MODE      (0)
    ) u_data_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .flush        (fifo_flush),
        .wr_en        (dfifo_wr_en),
        .wr_data      (dfifo_wr_data),
        .full         (dfifo_full),
        .almost_full  (dfifo_afull),
        .commit       (1'b0),
        .rewind       (1'b0),
        .rd_en        (dfifo_rd_en),
        .rd_data      (dfifo_rd_data),
        .empty        (dfifo_empty),
        .almost_empty (),
        .count        (),
        .overflow     (),
        .underflow    ()
    );

    //--------------------------------------------------------------------------
    // Packet metadata FIFO ({eop, packet length} per packet)
    //--------------------------------------------------------------------------
    dma_fifo #(
        .DATA_W        (LEN_W + 1),
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
    // Stream endpoint (byte FIFO -> MAC)
    //--------------------------------------------------------------------------
    dma_tx_stream #(
        .AXIS_DATA_W (AXIS_DATA_W),
        .LEN_W       (LEN_W)
    ) u_stream (
        .clk           (clk),
        .rst_n         (rst_n),
        .soft_reset    (fifo_flush),
        .enable        (enable),
        .fifo_rd_en    (dfifo_rd_en),
        .fifo_rd_data  (dfifo_rd_data),
        .fifo_empty    (dfifo_empty),
        .meta_rd_en    (mfifo_rd_en),
        .meta_rd_data  (mfifo_rd_data),
        .meta_empty    (mfifo_empty),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_tuser  (m_axis_tuser),
        .pkt_sent      (pkt_sent),
        .byte_sent     (byte_sent),
        .busy          (stream_busy)
    );

endmodule
