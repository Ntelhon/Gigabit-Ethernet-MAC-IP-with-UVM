//==============================================================================
// File: dma_tx_fetch.v
// Description: TX Buffer Fetch Engine (AXI read master -> byte FIFO)
//
// Purpose:
//   Executes one 'fetch command' at a time (one descriptor buffer): reads
//   cmd_len bytes starting at cmd_addr from system memory via AXI bursts
//   and pushes them, one byte per cycle, into the TX data FIFO. When the
//   command carries EOP (last buffer of the packet) it pushes a packet
//   metadata entry {1'b1, total_packet_length} so the streamer can start.
//
// Burst rules:
//   - INCR bursts, full-width beats (arsize = bus width).
//   - Never crosses a 4 KB boundary.
//   - arlen limited so a burst never exceeds MAX_BURST_LEN beats.
//   - Unaligned start supported: araddr is issued unaligned; the bytes
//     below the address offset in the first beat are discarded.
//   - A new burst is only issued when the FIFO's almost_full is low. The
//     channel top sets AFULL_THRESH = DEPTH - MAX_BURST_LEN*(AXI_DATA_W/8),
//     guaranteeing the whole burst fits (no mid-burst overflow possible).
//
// Error handling: any non-OKAY rresp sets an error flag reported with
// done_err; data movement continues so the AXI burst always completes.
//
// Soft reset: a pending flag lets any in-flight AXI burst drain cleanly
// (beats are consumed but bytes are discarded), then the engine idles.
//
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_tx_fetch #(
    parameter ADDR_WIDTH    = 64,       // AXI address width
    parameter AXI_DATA_W    = 64,       // AXI data width (32/64/128/256)
    parameter AXI_ID_W      = 4,        // AXI ID width
    parameter AXI_ID        = 1,        // ID driven on AR
    parameter MAX_BURST_LEN = 16,       // Max beats per burst (<= 256)
    parameter LEN_W         = 16        // Buffer length field width
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     soft_reset,

    // Fetch command (from dma_tx channel FSM)
    input  wire                     cmd_valid,
    output wire                     cmd_ready,
    input  wire [ADDR_WIDTH-1:0]    cmd_addr,       // Buffer address
    input  wire [LEN_W-1:0]         cmd_len,        // Buffer length (bytes)
    input  wire                     cmd_eop,        // Last buffer of packet
    input  wire [15:0]              cmd_meta,       // Opaque (descriptor index)

    // Completion (1-cycle pulse)
    output reg                      done_valid,
    output reg                      done_err,       // AXI error during fetch
    output reg  [15:0]              done_meta,      // cmd_meta echoed

    // TX data FIFO write side
    output wire                     fifo_wr_en,
    output wire [7:0]               fifo_wr_data,
    input  wire                     fifo_afull,     // Reserve-headroom gate
    input  wire                     fifo_full,      // Safety guard only

    // Packet metadata FIFO write side
    output wire                     pkt_meta_wr_en,
    output wire [LEN_W:0]           pkt_meta_wr_data, // {1'b1, packet length}
    input  wire                     pkt_meta_full,

    // Status
    output wire                     busy,

    // AXI read master
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,
    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg  [7:0]               m_axi_arlen,
    output wire [2:0]               m_axi_arsize,
    output wire [1:0]               m_axi_arburst,
    output wire [AXI_ID_W-1:0]      m_axi_arid,
    input  wire                     m_axi_rvalid,
    output wire                     m_axi_rready,
    input  wire [AXI_DATA_W-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire [AXI_ID_W-1:0]      m_axi_rid
);

    localparam AXI_BYTES = AXI_DATA_W / 8;
    localparam OFF_W     = $clog2(AXI_BYTES);
    localparam CHUNK_W   = 14;              // Chunk <= 4096 bytes + margin

    //--------------------------------------------------------------------------
    // FSM states
    //--------------------------------------------------------------------------
    localparam [2:0] ST_IDLE = 3'd0,    // Wait for a fetch command
                     ST_CALC = 3'd1,    // Compute next burst geometry
                     ST_AR   = 3'd2,    // Issue read address
                     ST_R    = 3'd3,    // Receive beats / unpack bytes
                     ST_NEXT = 3'd4,    // More chunks or finish
                     ST_DONE = 3'd5;    // Push meta, pulse completion

    reg [2:0]              state;

    //--------------------------------------------------------------------------
    // Command / progress registers
    //--------------------------------------------------------------------------
    reg [ADDR_WIDTH-1:0]   cur_addr;        // Next byte address to fetch
    reg [LEN_W:0]          bytes_rem;       // Bytes left in this command
    reg                    cmd_eop_q;
    reg [15:0]             cmd_meta_q;
    reg [LEN_W-1:0]        pkt_len_acc;     // Packet length accumulator
    reg                    err_flag;        // Sticky AXI error (per command)
    reg                    srst_pend;       // Soft reset requested

    //--------------------------------------------------------------------------
    // Burst / beat registers
    //--------------------------------------------------------------------------
    reg [CHUNK_W-1:0]      chunk_rem;       // Bytes left in current burst
    reg                    first_beat;      // Next R beat is burst's first
    reg [OFF_W-1:0]        addr_off;        // Byte offset within first beat
    reg [AXI_DATA_W-1:0]   beat_data;       // Unpack shift register
    reg [OFF_W:0]          beat_bytes;      // Valid bytes left in beat_data
    reg                    rlast_seen;      // Final beat of burst captured

    //--------------------------------------------------------------------------
    // Static AXI fields
    //--------------------------------------------------------------------------
    assign m_axi_arsize  = OFF_W[2:0];
    assign m_axi_arburst = 2'b01;                       // INCR
    assign m_axi_arid    = AXI_ID[AXI_ID_W-1:0];

    //--------------------------------------------------------------------------
    // Handshake / status
    //--------------------------------------------------------------------------
    assign cmd_ready = (state == ST_IDLE) && !srst_pend && !soft_reset;
    assign busy      = (state != ST_IDLE);

    // Accept a beat only when the unpack register is drained
    assign m_axi_rready = (state == ST_R) && (beat_bytes == {(OFF_W+1){1'b0}})
                          && !rlast_seen;

    wire r_beat = m_axi_rvalid && m_axi_rready;

    //--------------------------------------------------------------------------
    // Byte push (1 byte/cycle). During soft-reset drain, bytes are discarded.
    //--------------------------------------------------------------------------
    wire push_active = (state == ST_R) && (beat_bytes != {(OFF_W+1){1'b0}});
    wire byte_fire   = push_active && (srst_pend || !fifo_full);

    assign fifo_wr_en   = byte_fire && !srst_pend;
    assign fifo_wr_data = beat_data[7:0];

    //--------------------------------------------------------------------------
    // Packet metadata push (in ST_DONE, EOP commands only)
    //--------------------------------------------------------------------------
    wire done_exit = (state == ST_DONE) &&
                     (!cmd_eop_q || !pkt_meta_full || srst_pend);

    assign pkt_meta_wr_en   = done_exit && cmd_eop_q && !srst_pend;
    assign pkt_meta_wr_data = {1'b1, pkt_len_acc};

    //--------------------------------------------------------------------------
    // Burst geometry (combinational helpers for ST_CALC)
    //--------------------------------------------------------------------------
    wire [12:0] bytes_to_4k = 13'h1000 - {1'b0, cur_addr[11:0]};

    reg [LEN_W:0]     chunk_next;       // min(bytes_rem, to_4k, burst cap)
    reg [CHUNK_W-1:0] mbb;              // Max burst bytes from this offset

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

    // Beat count: ceil((offset + chunk) / AXI_BYTES)
    wire [CHUNK_W:0] off_plus_chunk =
        {{(CHUNK_W+1-OFF_W){1'b0}}, cur_addr[OFF_W-1:0]}
        + {1'b0, chunk_next[CHUNK_W-1:0]}
        + (AXI_BYTES[CHUNK_W:0] - {{CHUNK_W{1'b0}}, 1'b1});
    wire [8:0] beats_next = off_plus_chunk[OFF_W +: 9];

    //--------------------------------------------------------------------------
    // Valid bytes delivered by the incoming beat
    //--------------------------------------------------------------------------
    reg [OFF_W:0] nvalid;
    always @(*) begin
        if (first_beat) begin
            nvalid = AXI_BYTES[OFF_W:0] - {1'b0, addr_off};
        end else begin
            nvalid = AXI_BYTES[OFF_W:0];
        end
        if ({{(CHUNK_W-OFF_W-1){1'b0}}, nvalid} > chunk_rem) begin
            nvalid = chunk_rem[OFF_W:0];
        end
    end

    //--------------------------------------------------------------------------
    // Main FSM
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            cur_addr      <= {ADDR_WIDTH{1'b0}};
            bytes_rem     <= {(LEN_W+1){1'b0}};
            cmd_eop_q     <= 1'b0;
            cmd_meta_q    <= 16'd0;
            pkt_len_acc   <= {LEN_W{1'b0}};
            err_flag      <= 1'b0;
            srst_pend     <= 1'b0;
            chunk_rem     <= {CHUNK_W{1'b0}};
            first_beat    <= 1'b0;
            addr_off      <= {OFF_W{1'b0}};
            beat_data     <= {AXI_DATA_W{1'b0}};
            beat_bytes    <= {(OFF_W+1){1'b0}};
            rlast_seen    <= 1'b0;
            done_valid    <= 1'b0;
            done_err      <= 1'b0;
            done_meta     <= 16'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen   <= 8'd0;
        end else begin
            // Default: completion pulse lasts one cycle
            done_valid <= 1'b0;

            // Latch soft reset; consumed at safe points
            if (soft_reset) begin
                srst_pend <= 1'b1;
            end

            case (state)
                //--------------------------------------------------------------
                ST_IDLE: begin
                    if (srst_pend && !soft_reset) begin
                        srst_pend   <= 1'b0;
                        pkt_len_acc <= {LEN_W{1'b0}};
                        err_flag    <= 1'b0;
                    end else if (cmd_valid && cmd_ready) begin
                        cur_addr   <= cmd_addr;
                        bytes_rem  <= {1'b0, cmd_len};
                        cmd_eop_q  <= cmd_eop;
                        cmd_meta_q <= cmd_meta;
                        err_flag   <= 1'b0;
                        if (cmd_len == {LEN_W{1'b0}}) begin
                            state <= ST_DONE;       // Empty buffer: no AXI
                        end else begin
                            state <= ST_CALC;
                        end
                    end
                end

                //--------------------------------------------------------------
                ST_CALC: begin
                    if (srst_pend) begin
                        state <= ST_IDLE;
                    end else if (!fifo_afull) begin
                        chunk_rem     <= chunk_next[CHUNK_W-1:0];
                        addr_off      <= cur_addr[OFF_W-1:0];
                        first_beat    <= 1'b1;
                        rlast_seen    <= 1'b0;
                        m_axi_araddr  <= cur_addr;
                        m_axi_arlen   <= beats_next[7:0] - 8'd1;
                        m_axi_arvalid <= 1'b1;
                        state         <= ST_AR;
                    end
                end

                //--------------------------------------------------------------
                ST_AR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state         <= ST_R;
                    end
                end

                //--------------------------------------------------------------
                ST_R: begin
                    // Capture a beat (only when unpack register is empty)
                    if (r_beat) begin
                        if (first_beat) begin
                            beat_data <= m_axi_rdata >> {addr_off, 3'b000};
                        end else begin
                            beat_data <= m_axi_rdata;
                        end
                        beat_bytes <= nvalid;
                        first_beat <= 1'b0;
                        if (m_axi_rlast) begin
                            rlast_seen <= 1'b1;
                        end
                        if (m_axi_rresp != 2'b00) begin
                            err_flag <= 1'b1;
                        end
                    end

                    // Unpack one byte per cycle
                    if (byte_fire) begin
                        beat_data  <= beat_data >> 8;
                        beat_bytes <= beat_bytes - {{OFF_W{1'b0}}, 1'b1};
                        chunk_rem  <= chunk_rem  - {{(CHUNK_W-1){1'b0}}, 1'b1};
                        bytes_rem  <= bytes_rem  - {{LEN_W{1'b0}}, 1'b1};
                        cur_addr   <= cur_addr   + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                        if (!srst_pend) begin
                            pkt_len_acc <= pkt_len_acc + {{(LEN_W-1){1'b0}}, 1'b1};
                        end
                    end

                    // Burst complete when final beat captured and drained
                    if (rlast_seen && (beat_bytes == {(OFF_W+1){1'b0}})) begin
                        if (chunk_rem != {CHUNK_W{1'b0}}) begin
                            // Slave ended burst early: protocol error
                            err_flag  <= 1'b1;
                            bytes_rem <= bytes_rem
                                         - {{(LEN_W+1-CHUNK_W){1'b0}}, chunk_rem};
                            chunk_rem <= {CHUNK_W{1'b0}};
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
                    end else begin
                        state <= ST_DONE;
                    end
                end

                //--------------------------------------------------------------
                ST_DONE: begin
                    if (done_exit) begin
                        if (!srst_pend) begin
                            done_valid <= 1'b1;
                            done_err   <= err_flag;
                            done_meta  <= cmd_meta_q;
                        end
                        if (cmd_eop_q) begin
                            pkt_len_acc <= {LEN_W{1'b0}};
                        end
                        state <= ST_IDLE;
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
