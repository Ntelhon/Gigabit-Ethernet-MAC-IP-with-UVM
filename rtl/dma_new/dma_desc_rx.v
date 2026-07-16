//==============================================================================
// File: dma_desc_rx.v
// Description: RX Descriptor Engine (ring walker, producer side)
//
// Purpose:
//   Walks the RX descriptor ring in system memory. Whenever free
//   descriptors are available (head_nxt != tail_ptr, where tail_ptr is the
//   SW reclaim pointer) it prefetches the descriptor at head_ptr, checks
//   OWN = 1, and offers the buffer to the dma_rx write engine. When the
//   engine reports a stored packet, the descriptor is written back:
//     bytes  8..9  : stored packet length
//     bytes 10..11 : zeros (reserved)
//     bytes 12..15 : CTRL/STS (OWN = 0, DONE = 1, ERR_CRC/TRUNC/AXI)
//   then head_ptr advances (wraps at ring_size) and events pulse.
//
// The prefetch runs in parallel with packet reception, so a buffer is
// usually already staged when a packet completes.
//
// wb_status[3:0] = {err_axi, err_trunc, err_crc, done}.
// Supported AXI_DATA_W: 32 (two-beat writeback) or 64 (single beat).
//
// Fatal errors (AXI error on fetch/writeback, zero-length descriptor):
// desc_err pulses and the engine enters ST_HALT until soft reset.
//
// Reset: asynchronous active-low rst_n; soft reset semantics identical
// to dma_desc_tx (head_ptr clears).
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`include "dma_pkg.vh"

module dma_desc_rx #(
    parameter ADDR_WIDTH  = 64,     // AXI address width
    parameter AXI_DATA_W  = 64,     // 32 or 64 (descriptor engine limit)
    parameter AXI_ID_W    = 4,      // AXI ID width
    parameter AXI_ID      = 0,      // ID for descriptor traffic
    parameter LEN_W       = 16,     // Buffer length field width
    parameter DESC_SIZE_B = 16      // Descriptor size in bytes (fixed 16)
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Control / status
    input  wire                     enable,
    input  wire                     soft_reset,     // 1-cycle pulse
    input  wire [ADDR_WIDTH-1:0]    ring_base,      // 16-byte aligned
    input  wire [15:0]              ring_size,      // Descriptor count
    output reg  [15:0]              head_ptr,       // HW produce pointer
    input  wire [15:0]              tail_ptr,       // SW reclaim pointer
    output wire                     busy,
    output wire                     halted,
    output reg                      desc_err,       // 1-cycle pulse (fatal)

    // Descriptor dispatch (to dma_rx / dma_rx_write)
    output reg                      desc_valid,
    input  wire                     desc_ready,
    output reg  [ADDR_WIDTH-1:0]    desc_buf_addr,
    output reg  [LEN_W-1:0]         desc_buf_len,
    output reg                      desc_irq_en,
    output reg  [15:0]              desc_index,

    // Writeback request (from dma_rx / dma_rx_write)
    input  wire                     wb_valid,
    output wire                     wb_ready,
    input  wire [15:0]              wb_index,       // Informational
    input  wire [LEN_W-1:0]         wb_length,      // Bytes stored
    input  wire [3:0]               wb_status,      // {axi,trunc,crc,done}
    input  wire                     wb_irq_en,

    // Event pulses (to dma_irq)
    output reg                      ev_rx_done,     // Packet stored, IRQ_EN set
    output reg                      ev_rx_err,      // Packet stored with error

    // AXI read master (descriptor fetch)
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,
    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
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

    // AXI write master (descriptor writeback)
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,
    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output wire [7:0]               m_axi_awlen,
    output wire [2:0]               m_axi_awsize,
    output wire [1:0]               m_axi_awburst,
    output wire [AXI_ID_W-1:0]      m_axi_awid,
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,
    output reg  [AXI_DATA_W-1:0]    m_axi_wdata,
    output reg  [AXI_DATA_W/8-1:0]  m_axi_wstrb,
    output reg                      m_axi_wlast,
    input  wire                     m_axi_bvalid,
    output wire                     m_axi_bready,
    input  wire [1:0]               m_axi_bresp,
    input  wire [AXI_ID_W-1:0]      m_axi_bid
);

    localparam AXI_BYTES  = AXI_DATA_W / 8;
    localparam DESC_WORDS = (DESC_SIZE_B * 8) / AXI_DATA_W;
    localparam WB_BEATS   = (AXI_DATA_W == 64) ? 1 : 2;

    //--------------------------------------------------------------------------
    // FSM states
    //--------------------------------------------------------------------------
    localparam [3:0] ST_IDLE     = 4'd0,   // Poll for a free descriptor
                     ST_FETCH_AR = 4'd1,   // Issue descriptor read address
                     ST_FETCH_R  = 4'd2,   // Collect descriptor beats
                     ST_CHECK    = 4'd3,   // Validate OWN / length
                     ST_DISPATCH = 4'd4,   // Offer buffer to write engine
                     ST_WAIT_WB  = 4'd5,   // Wait packet completion
                     ST_WB_AW    = 4'd6,   // Issue writeback address
                     ST_WB_W     = 4'd7,   // Send writeback beat(s)
                     ST_WB_B     = 4'd8,   // Wait write response
                     ST_ADVANCE  = 4'd9,   // Bump head, pulse events
                     ST_HALT     = 4'd10;  // Fatal error; wait soft reset

    reg [3:0]              state;

    //--------------------------------------------------------------------------
    // Descriptor buffer + working registers
    //--------------------------------------------------------------------------
    reg [AXI_DATA_W-1:0]   desc_buf [0:DESC_WORDS-1];
    reg [1:0]              word_cnt;
    reg                    axi_err;         // Error during descriptor fetch
    reg                    srst_pend;
    reg                    wb_beat_idx;     // 0/1 for 32-bit writeback
    reg [LEN_W-1:0]        wb_length_q;
    reg [3:0]              wb_status_q;
    reg                    wb_irq_en_q;

    //--------------------------------------------------------------------------
    // Ring address math
    //--------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] desc_addr =
        ring_base + {{(ADDR_WIDTH-20){1'b0}}, head_ptr, 4'b0000};

    wire [15:0] head_nxt = (head_ptr == ring_size - 16'd1) ? 16'd0
                                                           : head_ptr + 16'd1;

    // Ring-full rule: HW must not consume the descriptor that would make
    // head catch tail (one-slot-open convention shared with software)
    wire ring_avail = (head_nxt != tail_ptr);

    //--------------------------------------------------------------------------
    // Descriptor field parse (width-specific)
    //--------------------------------------------------------------------------
    wire [63:0] d_addr64;
    wire [15:0] d_len;
    wire [31:0] d_ctrl;

    generate
        if (AXI_DATA_W == 64) begin : g_parse64
            assign d_addr64 = desc_buf[0];
            assign d_len    = desc_buf[1][15:0];
            assign d_ctrl   = desc_buf[1][63:32];
        end else begin : g_parse32
            assign d_addr64 = {desc_buf[1], desc_buf[0]};
            assign d_len    = desc_buf[2][15:0];
            assign d_ctrl   = desc_buf[3];
        end
    endgenerate

    wire d_own    = d_ctrl[`DESC_OWN];
    wire d_irq_en = d_ctrl[`DESC_IRQ_EN];

    //--------------------------------------------------------------------------
    // Writeback value: OWN = 0, DONE = 1, error bits from wb_status
    //   sts[15] = DONE, sts[14] = ERR_CRC, sts[13] = ERR_TRUNC,
    //   sts[12] = ERR_AXI (positions per dma_pkg.vh)
    //--------------------------------------------------------------------------
    wire [31:0] ctrl_new = {16'h0000,
                            1'b1,               // DESC_DONE
                            wb_status_q[1],     // DESC_ERR_CRC
                            wb_status_q[2],     // DESC_ERR_TRUNC
                            wb_status_q[3],     // DESC_ERR_AXI
                            12'h000};

    // Writeback targets descriptor bytes 8..15
    wire [ADDR_WIDTH-1:0] wb_addr = desc_addr + 64'd8;

    wire [AXI_DATA_W-1:0]   wb_data_b0;
    wire [AXI_DATA_W-1:0]   wb_data_b1;
    wire [AXI_DATA_W/8-1:0] wb_strb_b0;
    wire [AXI_DATA_W/8-1:0] wb_strb_b1;

    generate
        if (AXI_DATA_W == 64) begin : g_wb64
            // Single beat covers bytes 8..15
            assign wb_data_b0 = {ctrl_new, 16'h0000, wb_length_q};
            assign wb_strb_b0 = 8'hFF;
            assign wb_data_b1 = {AXI_DATA_W{1'b0}};     // Unused
            assign wb_strb_b1 = {AXI_BYTES{1'b0}};      // Unused
        end else begin : g_wb32
            // Beat 0: bytes 8..11 (length + reserved), beat 1: CTRL/STS
            assign wb_data_b0 = {16'h0000, wb_length_q};
            assign wb_strb_b0 = 4'hF;
            assign wb_data_b1 = ctrl_new;
            assign wb_strb_b1 = 4'hF;
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Static AXI fields
    //--------------------------------------------------------------------------
    assign m_axi_arlen   = DESC_WORDS[7:0] - 8'd1;
    assign m_axi_arsize  = $clog2(AXI_BYTES);
    assign m_axi_arburst = 2'b01;                   // INCR
    assign m_axi_arid    = AXI_ID[AXI_ID_W-1:0];
    assign m_axi_rready  = (state == ST_FETCH_R);

    assign m_axi_awlen   = WB_BEATS[7:0] - 8'd1;
    assign m_axi_awsize  = $clog2(AXI_BYTES);
    assign m_axi_awburst = 2'b01;
    assign m_axi_awid    = AXI_ID[AXI_ID_W-1:0];
    assign m_axi_bready  = (state == ST_WB_B);

    //--------------------------------------------------------------------------
    // Handshake / status
    //--------------------------------------------------------------------------
    assign wb_ready = (state == ST_WAIT_WB);
    assign busy     = (state != ST_IDLE) && (state != ST_HALT);
    assign halted   = (state == ST_HALT);

    //--------------------------------------------------------------------------
    // Main FSM
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            head_ptr      <= 16'd0;
            word_cnt      <= 2'd0;
            axi_err       <= 1'b0;
            srst_pend     <= 1'b0;
            wb_beat_idx   <= 1'b0;
            wb_length_q   <= {LEN_W{1'b0}};
            wb_status_q   <= 4'd0;
            wb_irq_en_q   <= 1'b0;
            desc_err      <= 1'b0;
            desc_valid    <= 1'b0;
            desc_buf_addr <= {ADDR_WIDTH{1'b0}};
            desc_buf_len  <= {LEN_W{1'b0}};
            desc_irq_en   <= 1'b0;
            desc_index    <= 16'd0;
            ev_rx_done    <= 1'b0;
            ev_rx_err     <= 1'b0;
            m_axi_arvalid <= 1'b0;
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= {AXI_DATA_W{1'b0}};
            m_axi_wstrb   <= {AXI_BYTES{1'b0}};
            m_axi_wlast   <= 1'b0;
        end else begin
            // Pulse defaults
            desc_err   <= 1'b0;
            ev_rx_done <= 1'b0;
            ev_rx_err  <= 1'b0;

            // Latch soft reset; consumed at safe points
            if (soft_reset) begin
                srst_pend <= 1'b1;
            end

            case (state)
                //--------------------------------------------------------------
                ST_IDLE: begin
                    if (srst_pend && !soft_reset) begin
                        srst_pend <= 1'b0;
                        head_ptr  <= 16'd0;
                    end else if (enable && (ring_size != 16'd0)
                                 && ring_avail) begin
                        m_axi_araddr  <= desc_addr;
                        m_axi_arvalid <= 1'b1;
                        word_cnt      <= 2'd0;
                        axi_err       <= 1'b0;
                        state         <= ST_FETCH_AR;
                    end
                end

                //--------------------------------------------------------------
                ST_FETCH_AR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state         <= ST_FETCH_R;
                    end
                end

                //--------------------------------------------------------------
                ST_FETCH_R: begin
                    if (m_axi_rvalid) begin
                        desc_buf[word_cnt] <= m_axi_rdata;
                        word_cnt           <= word_cnt + 2'd1;
                        if (m_axi_rresp != 2'b00) begin
                            axi_err <= 1'b1;
                        end
                        if (m_axi_rlast) begin
                            state <= ST_CHECK;
                        end
                    end
                end

                //--------------------------------------------------------------
                ST_CHECK: begin
                    if (srst_pend) begin
                        state <= ST_IDLE;
                    end else if (axi_err) begin
                        desc_err <= 1'b1;
                        state    <= ST_HALT;
                    end else if (!d_own) begin
                        state <= ST_IDLE;           // SW not ready: retry later
                    end else if (d_len == 16'd0) begin
                        desc_err <= 1'b1;           // Malformed descriptor
                        state    <= ST_HALT;
                    end else begin
                        desc_buf_addr <= d_addr64[ADDR_WIDTH-1:0];
                        desc_buf_len  <= d_len[LEN_W-1:0];
                        desc_irq_en   <= d_irq_en;
                        desc_index    <= head_ptr;
                        desc_valid    <= 1'b1;
                        state         <= ST_DISPATCH;
                    end
                end

                //--------------------------------------------------------------
                ST_DISPATCH: begin
                    if (srst_pend) begin
                        desc_valid <= 1'b0;
                        state      <= ST_IDLE;
                    end else if (desc_ready) begin
                        desc_valid <= 1'b0;
                        state      <= ST_WAIT_WB;
                    end
                end

                //--------------------------------------------------------------
                ST_WAIT_WB: begin
                    if (srst_pend) begin
                        state <= ST_IDLE;
                    end else if (wb_valid) begin
                        wb_length_q   <= wb_length;
                        wb_status_q   <= wb_status;
                        wb_irq_en_q   <= wb_irq_en;
                        m_axi_awaddr  <= wb_addr;
                        m_axi_awvalid <= 1'b1;
                        wb_beat_idx   <= 1'b0;
                        state         <= ST_WB_AW;
                    end
                end

                //--------------------------------------------------------------
                ST_WB_AW: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wdata   <= wb_data_b0;
                        m_axi_wstrb   <= wb_strb_b0;
                        m_axi_wlast   <= (WB_BEATS == 1);
                        m_axi_wvalid  <= 1'b1;
                        state         <= ST_WB_W;
                    end
                end

                //--------------------------------------------------------------
                ST_WB_W: begin
                    if (m_axi_wready) begin
                        if (m_axi_wlast) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                            state        <= ST_WB_B;
                        end else begin
                            m_axi_wdata  <= wb_data_b1;
                            m_axi_wstrb  <= wb_strb_b1;
                            m_axi_wlast  <= 1'b1;
                            wb_beat_idx  <= 1'b1;
                        end
                    end
                end

                //--------------------------------------------------------------
                ST_WB_B: begin
                    if (m_axi_bvalid) begin
                        if (m_axi_bresp != 2'b00) begin
                            desc_err <= 1'b1;
                            state    <= ST_HALT;
                        end else begin
                            state <= ST_ADVANCE;
                        end
                    end
                end

                //--------------------------------------------------------------
                ST_ADVANCE: begin
                    head_ptr   <= head_nxt;
                    ev_rx_done <= wb_irq_en_q;
                    ev_rx_err  <= |wb_status_q[3:1];
                    state      <= ST_IDLE;
                end

                //--------------------------------------------------------------
                ST_HALT: begin
                    if (srst_pend && !soft_reset) begin
                        srst_pend <= 1'b0;
                        head_ptr  <= 16'd0;
                        state     <= ST_IDLE;
                    end
                end

                //--------------------------------------------------------------
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
