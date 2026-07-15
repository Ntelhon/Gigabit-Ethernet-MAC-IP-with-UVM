//==============================================================================
// File: dma_fifo.v
// Description: Generic Synchronous FIFO (control logic only)
//
// Purpose:
//   Single-clock FIFO used for the TX/RX data paths and packet-metadata
//   queues. Contains ONLY pointer/flag logic; the storage array is an
//   instantiated dma_ram_sdp so ASIC flows can swap the memory.
//
// Read interface: FIRST-WORD-FALL-THROUGH (FWFT).
//   Because dma_ram_sdp has synchronous (1-cycle) read, a small prefetch
//   stage ('pending'/'hold' flags) keeps rd_data valid whenever empty == 0.
//   rd_en pops the presented word in the same cycle. Sustains 1 word/cycle.
//
// Packet mode (PKT_MODE = 1):
//   The writer streams words in, then either:
//     commit -> makes everything written so far (incl. a same-cycle write)
//               visible to the reader, or
//     rewind -> discards all uncommitted words (write pointer restored).
//   Readers only ever see committed data. Used by the RX path to drop
//   packets that overflow the FIFO. commit and rewind must never be
//   asserted in the same cycle.
//
// Occupancy reporting:
//   'count' reports RAM occupancy (what the WRITER cares about for space
//   checks). Up to 2 additional words may live in the FWFT stage and are
//   not included. 'almost_empty' is computed from the READER-visible
//   occupancy (committed words + FWFT stage).
//
// Reset: asynchronous active-low rst_n. 'flush' is a synchronous clear of
// pointers, FWFT stage and sticky flags (hold >= 1 cycle).
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_fifo #(
    parameter DATA_W        = 8,                // Word width
    parameter DEPTH         = 2048,             // Depth in words (power of 2)
    parameter ADDR_W        = $clog2(DEPTH),    // Address width (derived)
    parameter AFULL_THRESH  = DEPTH - 4,        // almost_full assertion level
    parameter AEMPTY_THRESH = 4,                // almost_empty assertion level
    parameter PKT_MODE      = 0                 // 1 = enable commit/rewind
)(
    input  wire              clk,
    input  wire              rst_n,          // Async active-low reset
    input  wire              flush,          // Sync clear (pointers + flags)

    // Write side
    input  wire              wr_en,          // Push (ignored when full)
    input  wire [DATA_W-1:0] wr_data,        // Push data
    output wire              full,           // Storage full (writer view)
    output wire              almost_full,    // count >= AFULL_THRESH

    // Packet mode controls (tie 0 when PKT_MODE = 0)
    input  wire              commit,         // Commit written words to reader
    input  wire              rewind,         // Restore wr_ptr to last commit

    // Read side (FWFT)
    input  wire              rd_en,          // Pop (ignored when empty)
    output wire [DATA_W-1:0] rd_data,        // Valid whenever !empty
    output wire              empty,          // No word available to reader
    output wire              almost_empty,   // Reader-visible occ <= AEMPTY

    // Status
    output wire [ADDR_W:0]   count,          // RAM occupancy in words
    output reg               overflow,       // Sticky: write attempted when full
    output reg               underflow       // Sticky: read attempted when empty
);

    localparam CNT_W = ADDR_W + 1;

    //--------------------------------------------------------------------------
    // Pointers (extra MSB scheme)
    //--------------------------------------------------------------------------
    reg  [CNT_W-1:0] wr_ptr;
    reg  [CNT_W-1:0] rd_ptr;
    wire [CNT_W-1:0] wr_ptr_c;              // Committed write pointer

    //--------------------------------------------------------------------------
    // Writer-side status (real storage occupancy)
    //--------------------------------------------------------------------------
    wire [CNT_W-1:0] ram_count = wr_ptr - rd_ptr;

    assign full        = (ram_count == DEPTH[CNT_W-1:0]);
    assign almost_full = (ram_count >= AFULL_THRESH[CNT_W-1:0]);
    assign count       = ram_count;

    wire wr_fire = wr_en & ~full & ~rewind; // rewind suppresses same-cycle write

    //--------------------------------------------------------------------------
    // Committed pointer (packet mode) - reader only sees committed words
    //--------------------------------------------------------------------------
    generate
        if (PKT_MODE != 0) begin : g_pkt
            reg [CNT_W-1:0] wr_ptr_c_q;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    wr_ptr_c_q <= {CNT_W{1'b0}};
                end else if (flush) begin
                    wr_ptr_c_q <= {CNT_W{1'b0}};
                end else if (commit) begin
                    // Include a write happening in the same cycle as commit
                    wr_ptr_c_q <= wr_ptr + {{(CNT_W-1){1'b0}}, wr_fire};
                end
            end
            assign wr_ptr_c = wr_ptr_c_q;
        end else begin : g_nopkt
            assign wr_ptr_c = wr_ptr;
        end
    endgenerate

    //--------------------------------------------------------------------------
    // FWFT read stage
    //   pending = RAM read issued last cycle, rd_data fresh this cycle
    //   hold    = rd_data holds a previously fetched, unconsumed word
    //   Invariant: pending and hold are never both 1 (stage depth = 1)
    //--------------------------------------------------------------------------
    reg pending;
    reg hold;

    wire [CNT_W-1:0] rd_avail = wr_ptr_c - rd_ptr;         // Committed, in RAM
    wire             ram_ne   = (rd_avail != {CNT_W{1'b0}});

    assign empty = ~(pending | hold);

    wire pop       = rd_en & ~empty;
    wire ram_rd_en = ram_ne & (empty | pop);               // Never clobbers held data

    // Reader-visible occupancy (RAM committed + FWFT stage)
    wire [CNT_W-1:0] rd_occ = rd_avail
                            + {{(CNT_W-1){1'b0}}, pending}
                            + {{(CNT_W-1){1'b0}}, hold};
    assign almost_empty = (rd_occ <= AEMPTY_THRESH[CNT_W-1:0]);

    //--------------------------------------------------------------------------
    // Sequential control
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr    <= {CNT_W{1'b0}};
            rd_ptr    <= {CNT_W{1'b0}};
            pending   <= 1'b0;
            hold      <= 1'b0;
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else if (flush) begin
            wr_ptr    <= {CNT_W{1'b0}};
            rd_ptr    <= {CNT_W{1'b0}};
            pending   <= 1'b0;
            hold      <= 1'b0;
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else begin
            // Write pointer (rewind has priority over a same-cycle push)
            if (rewind) begin
                wr_ptr <= wr_ptr_c;
            end else if (wr_fire) begin
                wr_ptr <= wr_ptr + {{(CNT_W-1){1'b0}}, 1'b1};
            end

            // Read pointer / FWFT stage
            if (ram_rd_en) begin
                rd_ptr <= rd_ptr + {{(CNT_W-1){1'b0}}, 1'b1};
            end
            pending <= ram_rd_en;
            hold    <= (pending | hold) & ~pop;

            // Sticky error flags
            if (wr_en & full)  overflow  <= 1'b1;
            if (rd_en & empty) underflow <= 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // Storage (the ONLY memory in the FIFO)
    //--------------------------------------------------------------------------
    dma_ram_sdp #(
        .DATA_W  (DATA_W),
        .DEPTH   (DEPTH),
        .ADDR_W  (ADDR_W),
        .OUT_REG (0)
    ) u_ram (
        .clk     (clk),
        .wr_en   (wr_fire),
        .wr_addr (wr_ptr[ADDR_W-1:0]),
        .wr_data (wr_data),
        .rd_en   (ram_rd_en),
        .rd_addr (rd_ptr[ADDR_W-1:0]),
        .rd_data (rd_data)
    );

endmodule
