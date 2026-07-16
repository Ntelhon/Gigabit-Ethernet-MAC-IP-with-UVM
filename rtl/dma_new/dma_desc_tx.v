//==============================================================================
// File: dma_desc_tx.v
// Description: TX Descriptor Engine (ring walker, consumer side)
//
// Purpose:
//   Walks the TX descriptor ring in system memory. For each descriptor
//   owned by hardware (OWN = 1) between tail_ptr (HW position) and
//   head_ptr (SW position):
//     1. Fetch the 16-byte descriptor over AXI.
//     2. Validate it (OWN, non-zero length); dispatch buffer address,
//        length and SOP/EOP/IRQ_EN flags to the dma_tx channel.
//     3. Wait for the channel's writeback request, then write the CTRL/STS
//        word back (OWN = 0, DONE = 1, ERR as reported).
//     4. Advance tail_ptr (wraps at ring_size) and pulse events.
//
// Descriptor layout (16 B): [0..7] BUF_ADDR, [8..9] BUF_LEN,
// [10..11] reserved, [12..15] CTRL/STS. Bits per dma_pkg.vh.
// Supported AXI_DATA_W: 32 or 64 (descriptor parse/writeback generates).
//
// Fatal errors (AXI error on fetch/writeback, zero-length descriptor):
// desc_err pulses and the engine enters ST_HALT until soft reset.
//
// Soft reset: pending flag; AXI transactions in flight complete first,
// then tail_ptr clears and the engine idles.
//
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`include "dma_pkg.vh"

module dma_desc_tx #(
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
    input  wire [15:0]              head_ptr,       // SW produce pointer
    output reg  [15:0]              tail_ptr,       // HW consume pointer
    output wire                     busy,
    output wire                     halted,
    output reg                      desc_err,       // 1-cycle pulse (fatal)

    // Descriptor dispatch (to dma_tx)
    output reg                      desc_valid,
    input  wire                     desc_ready,
    output reg  [ADDR_WIDTH-1:0]    desc_buf_addr,
    output reg  [LEN_W-1:0]         desc_buf_len,
    output reg                      desc_sop,
    output reg                      desc_eop,
    output reg                      desc_irq_en,
    output reg  [15:0]              desc_index,

    // Writeback request (from dma_tx)
    input  wire                     wb_valid,
    output wire                     wb_ready,
    input  wire [15:0]              wb_index,       // Informational
    input  wire                     wb_err,

    // Event pulses (to dma_irq)
    output reg                      ev_tx_done,     // Writeback done, IRQ_EN set
    output reg                      ev_tx_err,      // Writeback carried an error

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
    output wire                     m_axi_wlast,
    input  wire                     m_axi_bvalid,
    output wire                     m_axi_bready,
    input  wire [1:0]               m_axi_bresp,
    input  wire [AXI_ID_W-1:0]      m_axi_bid
);

    localparam AXI_BYTES  = AXI_DATA_W / 8;
    localparam DESC_WORDS = (DESC_SIZE_B * 8) / AXI_DATA_W;

    //--------------------------------------------------------------------------
    // FSM states
    //--------------------------------------------------------------------------
    localparam [3:0] ST_IDLE     = 4'd0,   // Poll head/tail difference
                     ST_FETCH_AR = 4'd1,   // Issue descriptor read address
                     ST_FETCH_R  = 4'd2,   // Collect descriptor beats
                     ST_CHECK    = 4'd3,   // Validate OWN / length
                     ST_DISPATCH = 4'd4,   // Hand descriptor to channel
                     ST_WAIT_WB  = 4'd5,   // Wait channel completion
                     ST_WB_AW    = 4'd6,   // Issue writeback address
                     ST_WB_W     = 4'd7,   // Send writeback data beat
                     ST_WB_B     = 4'd8,   // Wait write response
                     ST_ADVANCE  = 4'd9,   // Bump tail, pulse events
                     ST_HALT     = 4'd10;  // Fatal error; wait soft reset

    reg [3:0]              state;

    //--------------------------------------------------------------------------
    // Descriptor buffer + working registers
    //--------------------------------------------------------------------------
    reg [AXI_DATA_W-1:0]   desc_buf [0:DESC_WORDS-1];
    reg [1:0]              word_cnt;
    reg                    axi_err;         // Error during descriptor fetch
    reg                    wb_err_q;        // Error carried by the writeback
    reg                    srst_pend;

    //--------------------------------------------------------------------------
    // Ring address math
    //--------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] desc_addr =
        ring_base + {{(ADDR_WIDTH-20){1'b0}}, tail_ptr, 4'b0000};

    wire [15:0] tail_nxt = (tail_ptr == ring_size - 16'd1) ? 16'd0
                                                           : tail_ptr + 16'd1;

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
    wire d_sop    = d_ctrl[`DESC_SOP];
    wire d_eop    = d_ctrl[`DESC_EOP];
    wire d_irq_en = d_ctrl[`DESC_IRQ_EN];

    //--------------------------------------------------------------------------
    // Writeback value: OWN = 0, DONE = 1, ERR = wb_err (evaluated at the
    // writeback handshake so wb_err is sampled directly)
    //--------------------------------------------------------------------------
    wire [31:0] ctrl_new = {16'h0000, 1'b1, wb_err, 14'h0000};

    wire [ADDR_WIDTH-1:0] wb_addr =
        desc_addr + ((AXI_DATA_W == 64) ? 64'd8 : 64'd12);

    wire [AXI_DATA_W-1:0]   wb_data;
    wire [AXI_DATA_W/8-1:0] wb_strb;

    generate
        if (AXI_DATA_W == 64) begin : g_wb64
            assign wb_data = {ctrl_new, 32'h0000_0000};
            assign wb_strb = 8'hF0;
        end else begin : g_wb32
            assign wb_data = ctrl_new;
            assign wb_strb = 4'hF;
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

    assign m_axi_awlen   = 8'd0;                    // Single-beat writeback
    assign m_axi_awsize  = $clog2(AXI_BYTES);
    assign m_axi_awburst = 2'b01;
    assign m_axi_awid    = AXI_ID[AXI_ID_W-1:0];
    assign m_axi_wlast   = 1'b1;
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
            tail_ptr      <= 16'd0;
            word_cnt      <= 2'd0;
            axi_err       <= 1'b0;
            wb_err_q      <= 1'b0;
            srst_pend     <= 1'b0;
            desc_err      <= 1'b0;
            desc_valid    <= 1'b0;
            desc_buf_addr <= {ADDR_WIDTH{1'b0}};
            desc_buf_len  <= {LEN_W{1'b0}};
            desc_sop      <= 1'b0;
            desc_eop      <= 1'b0;
            desc_irq_en   <= 1'b0;
            desc_index    <= 16'd0;
            ev_tx_done    <= 1'b0;
            ev_tx_err     <= 1'b0;
            m_axi_arvalid <= 1'b0;
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= {AXI_DATA_W{1'b0}};
            m_axi_wstrb   <= {AXI_BYTES{1'b0}};
        end else begin
            // Pulse defaults
            desc_err   <= 1'b0;
            ev_tx_done <= 1'b0;
            ev_tx_err  <= 1'b0;

            // Latch soft reset; consumed at safe points
            if (soft_reset) begin
                srst_pend <= 1'b1;
            end

            case (state)
                //--------------------------------------------------------------
                ST_IDLE: begin
                    if (srst_pend && !soft_reset) begin
                        srst_pend <= 1'b0;
                        tail_ptr  <= 16'd0;
                    end else if (enable && (ring_size != 16'd0)
                                 && (head_ptr != tail_ptr)) begin
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
                        desc_sop      <= d_sop;
                        desc_eop      <= d_eop;
                        desc_irq_en   <= d_irq_en;
                        desc_index    <= tail_ptr;
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
                        wb_err_q      <= wb_err;
                        m_axi_awaddr  <= wb_addr;
                        m_axi_wdata   <= wb_data;   // ctrl_new uses live wb_err
                        m_axi_wstrb   <= wb_strb;
                        m_axi_awvalid <= 1'b1;
                        state         <= ST_WB_AW;
                    end
                end

                //--------------------------------------------------------------
                ST_WB_AW: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        state         <= ST_WB_W;
                    end
                end

                //--------------------------------------------------------------
                ST_WB_W: begin
                    if (m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        state        <= ST_WB_B;
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
                    tail_ptr   <= tail_nxt;
                    ev_tx_done <= desc_irq_en && !wb_err_q;
                    ev_tx_err  <= wb_err_q;
                    state      <= ST_IDLE;
                end

                //--------------------------------------------------------------
                ST_HALT: begin
                    if (srst_pend && !soft_reset) begin
                        srst_pend <= 1'b0;
                        tail_ptr  <= 16'd0;
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
