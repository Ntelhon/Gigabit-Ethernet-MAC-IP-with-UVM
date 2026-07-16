//==============================================================================
// File: dma_rx_write.v
// Description: RX Buffer Write Engine (byte FIFO -> AXI write master)
//
// Purpose:
//   Pops one committed packet at a time from the RX data FIFO (guided by a
//   metadata entry {err_crc, rsvd, pkt_len}), pairs it with an RX
//   descriptor from the descriptor engine, and writes the payload to the
//   descriptor's buffer via AXI bursts. When done, it issues a writeback
//   request carrying the stored length and status flags.
//
// Behavior:
//   - Bytes are packed one per cycle into a beat register; write strobes
//     are set only for real payload lanes (unaligned start supported).
//   - Packets longer than the buffer are TRUNCATED: buf_len bytes are
//     written, the remainder is discarded from the FIFO, err_trunc is set.
//   - Burst rules identical to dma_tx_fetch (INCR, 4 KB, MAX_BURST_LEN).
//   - Any non-OKAY bresp sets err_axi in the writeback status.
//
// wb_status[3:0] = {err_axi, err_trunc, err_crc, done(=1)}.
//
// Soft reset: pending flag; an in-flight burst is completed with zero
// strobes (no FIFO dependency) so the AXI fabric is never left hanging,
// then the engine idles without a writeback.
//
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_rx_write #(
    parameter ADDR_WIDTH    = 64,       // AXI address width
    parameter AXI_DATA_W    = 64,       // AXI data width
    parameter AXI_ID_W      = 4,        // AXI ID width
    parameter AXI_ID        = 2,        // ID driven on AW
    parameter MAX_BURST_LEN = 16,       // Max beats per burst (<= 256)
    parameter LEN_W         = 16        // Length field width
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     soft_reset,

    // Packet metadata FIFO read side (FWFT)
    output wire                     meta_rd_en,
    input  wire [LEN_W+1:0]         meta_rd_data,   // {err_crc, rsvd, len}
    input  wire                     meta_empty,

    // RX data FIFO read side (FWFT)
    output wire                     fifo_rd_en,
    input  wire [7:0]               fifo_rd_data,
    input  wire                     fifo_empty,

    // Descriptor dispatch (from dma_desc_rx)
    input  wire                     desc_valid,
    output wire                     desc_ready,
    input  wire [ADDR_WIDTH-1:0]    desc_buf_addr,
    input  wire [LEN_W-1:0]         desc_buf_len,
    input  wire                     desc_irq_en,
    input  wire [15:0]              desc_index,

    // Writeback request (to dma_desc_rx)
    output reg                      wb_valid,
    input  wire                     wb_ready,
    output reg  [15:0]              wb_index,
    output reg  [LEN_W-1:0]         wb_length,      // Bytes stored
    output reg  [3:0]               wb_status,      // {axi,trunc,crc,done}
    output reg                      wb_irq_en,

    // Statistics
    output wire                     pkt_written,    // 1-cycle pulse
    output wire                     busy,

    // AXI write master
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,
    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output reg  [7:0]               m_axi_awlen,
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

    localparam AXI_BYTES = AXI_DATA_W / 8;
    localparam OFF_W     = $clog2(AXI_BYTES);
    localparam CHUNK_W   = 14;              // Chunk <= 4096 bytes + margin

    //--------------------------------------------------------------------------
    // FSM states
    //--------------------------------------------------------------------------
    localparam [3:0] ST_IDLE    = 4'd0, // Wait for a packet metadata entry
                     ST_GETDESC = 4'd1, // Wait for an RX descriptor
                     ST_CALC    = 4'd2, // Compute next burst geometry
                     ST_AW      = 4'd3, // Issue write address
                     ST_W       = 4'd4, // Pack bytes / send beats
                     ST_B       = 4'd5, // Wait write response
                     ST_NEXT    = 4'd6, // More chunks / discard / writeback
                     ST_DISCARD = 4'd7, // Drop truncated tail from FIFO
                     ST_WB      = 4'd8; // Writeback handshake

    reg [3:0]            state;

    //--------------------------------------------------------------------------
    // Packet / descriptor registers
    //--------------------------------------------------------------------------
    reg [LEN_W-1:0]      pkt_len;         // Packet length from metadata
    reg                  err_crc;         // MAC error flag from metadata
    reg                  err_trunc;       // Packet exceeded buffer
    reg                  err_axi;         // Non-OKAY write response
    reg [ADDR_WIDTH-1:0] cur_addr;        // Next byte address to write
    reg [LEN_W:0]        bytes_rem;       // Payload bytes left to write
    reg [LEN_W:0]        discard_rem;     // Truncated bytes left to drop
    reg [15:0]           index_q;
    reg                  irq_en_q;
    reg [LEN_W-1:0]      wr_len_q;        // min(pkt_len, buf_len)
    reg                  srst_pend;

    //--------------------------------------------------------------------------
    // Burst / beat registers
    //--------------------------------------------------------------------------
    reg [CHUNK_W-1:0]    chunk_rem;       // Bytes left to pack in this burst
    reg [8:0]            beats_left;      // W beats left in this burst
    reg [OFF_W-1:0]      lane;            // Current byte lane being filled

    //--------------------------------------------------------------------------
    // Static AXI fields
    //--------------------------------------------------------------------------
    assign m_axi_awsize  = OFF_W[2:0];
    assign m_axi_awburst = 2'b01;                       // INCR
    assign m_axi_awid    = AXI_ID[AXI_ID_W-1:0];
    assign m_axi_bready  = (state == ST_B);

    //--------------------------------------------------------------------------
    // Handshakes / status
    //--------------------------------------------------------------------------
    assign meta_rd_en = (state == ST_IDLE) && !meta_empty
                        && !srst_pend && !soft_reset;
    assign desc_ready = (state == ST_GETDESC) && !srst_pend;
    assign busy       = (state != ST_IDLE);

    // Byte pull: pack while no beat is pending and chunk bytes remain.
    // During soft-reset drain the FIFO is bypassed (zero fill, no strobes).
    wire fill_active = (state == ST_W) && !m_axi_wvalid
                       && (chunk_rem != {CHUNK_W{1'b0}});
    wire fill_fire   = fill_active && (srst_pend || !fifo_empty);

    assign fifo_rd_en = (fill_fire && !srst_pend) ||
                        ((state == ST_DISCARD) && !fifo_empty);

    wire last_byte_of_chunk = (chunk_rem == {{(CHUNK_W-1){1'b0}}, 1'b1});
    wire beat_complete      = fill_fire &&
                              ((lane == AXI_BYTES[OFF_W-1:0] - {{(OFF_W-1){1'b0}}, 1'b1})
                               || last_byte_of_chunk);

    assign pkt_written = (state == ST_WB) && wb_valid && wb_ready;

    //--------------------------------------------------------------------------
    // Burst geometry (same rules as dma_tx_fetch)
    //--------------------------------------------------------------------------
    wire [12:0] bytes_to_4k = 13'h1000 - {1'b0, cur_addr[11:0]};

    reg [LEN_W:0]     chunk_next;
    reg [CHUNK_W-1:0] mbb;

    always @(*) begin
        mbb        = MAX_BURST_LEN[CHUNK_W-1:0] * AXI_BYTES[CHUNK_W-1:0]
                     - {{(CHUNK_W-OFF_W){1'b0}}, cur_addr[OFF_W-1:0]};
        chunk_next = bytes_rem;
        if ({{(LEN_W-12){1'b0}}, bytes_to_4k} < chunk_next) begin
            chunk_next = {{(LEN_W-12){1'b0}}, bytes_to_4k};
        end
        if ({{(LEN_W+1-CHUNK_W){1'b0}}, mbb} < chunk_next) begin
            chunk_next = {{(LEN_W+1-CHUNK_W){1'b0}}, mbb};
        end
    end

    wire [CHUNK_W:0] off_plus_chunk =
        {{(CHUNK_W+1-OFF_W){1'b0}}, cur_addr[OFF_W-1:0]}
        + {1'b0, chunk_next[CHUNK_W-1:0]}
        + (AXI_BYTES[CHUNK_W:0] - {{CHUNK_W{1'b0}}, 1'b1});
    wire [8:0] beats_next = off_plus_chunk[OFF_W +: 9];

    //--------------------------------------------------------------------------
    // Truncation math at descriptor acceptance
    //--------------------------------------------------------------------------
    wire            trunc_next  = (pkt_len > desc_buf_len);
    wire [LEN_W-1:0] wr_len_next = trunc_next ? desc_buf_len : pkt_len;

    //--------------------------------------------------------------------------
    // Main FSM
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            pkt_len       <= {LEN_W{1'b0}};
            err_crc       <= 1'b0;
            err_trunc     <= 1'b0;
            err_axi       <= 1'b0;
            cur_addr      <= {ADDR_WIDTH{1'b0}};
            bytes_rem     <= {(LEN_W+1){1'b0}};
            discard_rem   <= {(LEN_W+1){1'b0}};
            index_q       <= 16'd0;
            irq_en_q      <= 1'b0;
            wr_len_q      <= {LEN_W{1'b0}};
            srst_pend     <= 1'b0;
            chunk_rem     <= {CHUNK_W{1'b0}};
            beats_left    <= 9'd0;
            lane          <= {OFF_W{1'b0}};
            wb_valid      <= 1'b0;
            wb_index      <= 16'd0;
            wb_length     <= {LEN_W{1'b0}};
            wb_status     <= 4'd0;
            wb_irq_en     <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= {AXI_DATA_W{1'b0}};
            m_axi_wstrb   <= {AXI_BYTES{1'b0}};
            m_axi_wlast   <= 1'b0;
        end else begin
            // Latch soft reset; consumed at safe points
            if (soft_reset) begin
                srst_pend <= 1'b1;
            end

            case (state)
                //--------------------------------------------------------------
                ST_IDLE: begin
                    err_crc   <= 1'b0;
                    err_trunc <= 1'b0;
                    err_axi   <= 1'b0;
                    if (srst_pend && !soft_reset) begin
                        srst_pend <= 1'b0;
                    end else if (meta_rd_en && !meta_empty) begin
                        err_crc <= meta_rd_data[LEN_W+1];
                        pkt_len <= meta_rd_data[LEN_W-1:0];
                        state   <= ST_GETDESC;
                    end
                end

                //--------------------------------------------------------------
                ST_GETDESC: begin
                    if (srst_pend) begin
                        // Packet data stays in the FIFO; the channel-level
                        // flush clears it during soft reset.
                        state <= ST_IDLE;
                    end else if (desc_valid && desc_ready) begin
                        cur_addr    <= desc_buf_addr;
                        index_q     <= desc_index;
                        irq_en_q    <= desc_irq_en;
                        err_trunc   <= trunc_next;
                        wr_len_q    <= wr_len_next;
                        bytes_rem   <= {1'b0, wr_len_next};
                        discard_rem <= {1'b0, pkt_len} - {1'b0, wr_len_next};
                        if (wr_len_next == {LEN_W{1'b0}}) begin
                            state <= ST_NEXT;   // Zero-length: skip writes
                        end else begin
                            state <= ST_CALC;
                        end
                    end
                end

                //--------------------------------------------------------------
                ST_CALC: begin
                    chunk_rem     <= chunk_next[CHUNK_W-1:0];
                    beats_left    <= beats_next;
                    lane          <= cur_addr[OFF_W-1:0];
                    m_axi_awaddr  <= cur_addr;
                    m_axi_awlen   <= beats_next[7:0] - 8'd1;
                    m_axi_awvalid <= 1'b1;
                    m_axi_wdata   <= {AXI_DATA_W{1'b0}};
                    m_axi_wstrb   <= {AXI_BYTES{1'b0}};
                    state         <= ST_AW;
                end

                //--------------------------------------------------------------
                ST_AW: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        state         <= ST_W;
                    end
                end

                //--------------------------------------------------------------
                ST_W: begin
                    // Pack one byte per cycle into the beat register
                    if (fill_fire) begin
                        m_axi_wdata[lane*8 +: 8] <= srst_pend ? 8'h00
                                                              : fifo_rd_data;
                        if (!srst_pend) begin
                            m_axi_wstrb[lane] <= 1'b1;
                        end
                        chunk_rem <= chunk_rem - {{(CHUNK_W-1){1'b0}}, 1'b1};
                        bytes_rem <= bytes_rem - {{LEN_W{1'b0}}, 1'b1};
                        cur_addr  <= cur_addr  + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                        if (beat_complete) begin
                            m_axi_wvalid <= 1'b1;
                            m_axi_wlast  <= (beats_left == 9'd1);
                        end else begin
                            lane <= lane + {{(OFF_W-1){1'b0}}, 1'b1};
                        end
                    end

                    // Beat accepted by the fabric
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wdata  <= {AXI_DATA_W{1'b0}};
                        m_axi_wstrb  <= {AXI_BYTES{1'b0}};
                        lane         <= {OFF_W{1'b0}};
                        beats_left   <= beats_left - 9'd1;
                        if (m_axi_wlast) begin
                            m_axi_wlast <= 1'b0;
                            state       <= ST_B;
                        end
                    end
                end

                //--------------------------------------------------------------
                ST_B: begin
                    if (m_axi_bvalid) begin
                        if (m_axi_bresp != 2'b00) begin
                            err_axi <= 1'b1;
                        end
                        state <= ST_NEXT;
                    end
                end

                //--------------------------------------------------------------
                ST_NEXT: begin
                    if (srst_pend) begin
                        state <= ST_IDLE;
                    end else if (bytes_rem != {(LEN_W+1){1'b0}}) begin
                        state <= ST_CALC;
                    end else if (discard_rem != {(LEN_W+1){1'b0}}) begin
                        state <= ST_DISCARD;
                    end else begin
                        wb_valid  <= 1'b1;
                        wb_index  <= index_q;
                        wb_length <= wr_len_q;
                        wb_status <= {err_axi, err_trunc, err_crc, 1'b1};
                        wb_irq_en <= irq_en_q;
                        state     <= ST_WB;
                    end
                end

                //--------------------------------------------------------------
                ST_DISCARD: begin
                    if (srst_pend) begin
                        state <= ST_IDLE;
                    end else if (!fifo_empty) begin
                        discard_rem <= discard_rem - {{LEN_W{1'b0}}, 1'b1};
                        if (discard_rem == {{LEN_W{1'b0}}, 1'b1}) begin
                            wb_valid  <= 1'b1;
                            wb_index  <= index_q;
                            wb_length <= wr_len_q;
                            wb_status <= {err_axi, err_trunc, err_crc, 1'b1};
                            wb_irq_en <= irq_en_q;
                            state     <= ST_WB;
                        end
                    end
                end

                //--------------------------------------------------------------
                ST_WB: begin
                    if (wb_ready) begin
                        wb_valid <= 1'b0;
                        state    <= ST_IDLE;
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
