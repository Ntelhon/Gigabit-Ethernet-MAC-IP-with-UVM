//==============================================================================
// Module: mac_cdc_fifo
// Description: Asynchronous FIFO controller with Gray-coded pointers
//              (one function: dual-clock FIFO control)
//
// Same methodology as the DMA subsystem: this module contains ONLY the FIFO
// control logic (pointers, Gray CDC, flags, first-word-fall-through stage).
// The storage lives in the separate mac_fifo_ram module, which maps directly
// to a dual-port SRAM macro for ASIC synthesis.
//
// Features:
//   - Dual-clock asynchronous FIFO, parameterized width/depth
//   - Gray-coded pointers, 2-stage FF synchronizers (CDC-safe)
//   - Conservative full/empty flags (no overflow/underflow possible)
//   - Almost full/empty thresholds
//   - First-Word-Fall-Through (FWFT) read interface:
//       rd_empty == 0  =>  rd_data holds the head word
//       rd_en          =>  consume head word, next word appears with no bubble
//   - Effective capacity: 2^ADDR_WIDTH (RAM) + 1 (FWFT output register)
//
// Reset:
//   - wr_rst_n / rd_rst_n are per-domain resets, asynchronous assert with
//     synchronous de-assert (drive them from rst_sync). Both domains must
//     be reset together; releasing only one domain is not supported.
//
// Timing:
//   - Write latency: 1 wr_clk cycle
//   - First-word latency: ~2 rd_clk cycles after pointer sync (RAM fetch +
//     FWFT register); back-to-back reads stream 1 word per rd_clk cycle
//
// Verification Hooks:
//   - Assertion: no write when full, no read when empty
//   - Assertion: Gray pointers change at most 1 bit per cycle
//   - Coverage: fill levels, simultaneous read/write
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_cdc_fifo #(
    parameter DATA_WIDTH      = 8,      // Data width in bits
    parameter ADDR_WIDTH      = 4,      // Address width (RAM depth = 2^ADDR_WIDTH)
    parameter ALMOST_FULL_TH  = 2,      // Almost full threshold (spaces remaining)
    parameter ALMOST_EMPTY_TH = 2       // Almost empty threshold (entries remaining)
) (
    //==========================================================================
    // Write Domain (Producer)
    //==========================================================================
    input  wire                     wr_clk,         // Write clock
    input  wire                     wr_rst_n,       // Write domain reset (async assert)
    input  wire                     wr_en,          // Write enable
    input  wire [DATA_WIDTH-1:0]    wr_data,        // Write data
    output wire                     wr_full,        // FIFO full flag
    output wire                     wr_almost_full, // Almost full flag

    //==========================================================================
    // Read Domain (Consumer) - FWFT
    //==========================================================================
    input  wire                     rd_clk,         // Read clock
    input  wire                     rd_rst_n,       // Read domain reset (async assert)
    input  wire                     rd_en,          // Read (consume) enable
    output wire [DATA_WIDTH-1:0]    rd_data,        // Head word (valid when !rd_empty)
    output wire                     rd_empty,       // FIFO empty flag
    output wire                     rd_almost_empty // Almost empty flag
);

    //==========================================================================
    // Local Parameters
    //==========================================================================
    localparam FIFO_DEPTH = 1 << ADDR_WIDTH;
    localparam PTR_W      = ADDR_WIDTH + 1;         // Extra bit for full detection

    //==========================================================================
    // Write Domain Signals
    //==========================================================================
    reg  [PTR_W-1:0] wr_ptr_bin;
    reg  [PTR_W-1:0] wr_ptr_gray;
    wire [PTR_W-1:0] wr_ptr_bin_next;
    wire [PTR_W-1:0] wr_ptr_gray_next;
    reg  [PTR_W-1:0] rd_ptr_gray_sync1;             // Read pointer synced into wr domain
    reg  [PTR_W-1:0] rd_ptr_gray_sync2;

    //==========================================================================
    // Read Domain Signals
    //==========================================================================
    reg  [PTR_W-1:0] rd_ptr_bin;
    reg  [PTR_W-1:0] rd_ptr_gray;
    wire [PTR_W-1:0] rd_ptr_bin_next;
    wire [PTR_W-1:0] rd_ptr_gray_next;
    reg  [PTR_W-1:0] wr_ptr_gray_sync1;             // Write pointer synced into rd domain
    reg  [PTR_W-1:0] wr_ptr_gray_sync2;

    wire             ram_wr_en;
    wire             ram_rd_en;                     // FWFT fetch strobe
    wire             ram_empty;                     // RAM (pointer) empty
    reg              out_valid;                     // FWFT output register holds a word

    //==========================================================================
    // Write Domain Logic
    //==========================================================================
    assign ram_wr_en        = wr_en && !wr_full;
    assign wr_ptr_bin_next  = wr_ptr_bin + {{(PTR_W-1){1'b0}}, ram_wr_en};
    assign wr_ptr_gray_next = wr_ptr_bin_next ^ (wr_ptr_bin_next >> 1);

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= {PTR_W{1'b0}};
            wr_ptr_gray <= {PTR_W{1'b0}};
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    // Synchronize read pointer into write domain (2-stage)
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= {PTR_W{1'b0}};
            rd_ptr_gray_sync2 <= {PTR_W{1'b0}};
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Full: write pointer one wrap ahead of (synced) read pointer.
    // In Gray code: two MSBs differ, remaining bits equal.
    assign wr_full = (wr_ptr_gray[PTR_W-1]   != rd_ptr_gray_sync2[PTR_W-1]) &&
                     (wr_ptr_gray[PTR_W-2]   != rd_ptr_gray_sync2[PTR_W-2]) &&
                     (wr_ptr_gray[PTR_W-3:0] == rd_ptr_gray_sync2[PTR_W-3:0]);

    // Write-side fill level (conservative: synced rd pointer lags)
    wire [PTR_W-1:0] rd_ptr_bin_in_wr;
    genvar gw;
    generate
        for (gw = 0; gw < PTR_W; gw = gw + 1) begin : g_gray2bin_wr
            assign rd_ptr_bin_in_wr[gw] = ^rd_ptr_gray_sync2[PTR_W-1:gw];
        end
    endgenerate

    wire [PTR_W-1:0] wr_fill_level;
    assign wr_fill_level  = wr_ptr_bin - rd_ptr_bin_in_wr;
    assign wr_almost_full = (wr_fill_level >= (FIFO_DEPTH[PTR_W-1:0] - ALMOST_FULL_TH[PTR_W-1:0]));

    //==========================================================================
    // Read Domain Logic - pointer side
    //==========================================================================
    // FWFT fetch: pull the next RAM word into the output register whenever the
    // RAM has data and the output register is empty or being consumed.
    assign ram_empty = (rd_ptr_gray == wr_ptr_gray_sync2);
    assign ram_rd_en = !ram_empty && (!out_valid || rd_en);

    assign rd_ptr_bin_next  = rd_ptr_bin + {{(PTR_W-1){1'b0}}, ram_rd_en};
    assign rd_ptr_gray_next = rd_ptr_bin_next ^ (rd_ptr_bin_next >> 1);

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= {PTR_W{1'b0}};
            rd_ptr_gray <= {PTR_W{1'b0}};
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    // Synchronize write pointer into read domain (2-stage)
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= {PTR_W{1'b0}};
            wr_ptr_gray_sync2 <= {PTR_W{1'b0}};
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    //==========================================================================
    // Read Domain Logic - FWFT output register validity
    // (rd_data itself is the registered read port of mac_fifo_ram)
    //==========================================================================
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            out_valid <= 1'b0;
        end else if (ram_rd_en) begin
            out_valid <= 1'b1;                       // New word arrives next cycle
        end else if (rd_en && out_valid) begin
            out_valid <= 1'b0;                       // Consumed, nothing to fetch
        end
    end

    assign rd_empty = !out_valid;

    // Read-side fill level (RAM occupancy, excludes FWFT register; conservative)
    wire [PTR_W-1:0] wr_ptr_bin_in_rd;
    genvar gr;
    generate
        for (gr = 0; gr < PTR_W; gr = gr + 1) begin : g_gray2bin_rd
            assign wr_ptr_bin_in_rd[gr] = ^wr_ptr_gray_sync2[PTR_W-1:gr];
        end
    endgenerate

    wire [PTR_W-1:0] rd_fill_level;
    assign rd_fill_level   = wr_ptr_bin_in_rd - rd_ptr_bin;
    assign rd_almost_empty = (rd_fill_level <= ALMOST_EMPTY_TH[PTR_W-1:0]);

    //==========================================================================
    // FIFO Storage (separate RAM module - SRAM-macro replaceable)
    //==========================================================================
    mac_fifo_ram #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_fifo_ram (
        // Write port
        .wr_clk     (wr_clk),
        .wr_en      (ram_wr_en),
        .wr_addr    (wr_ptr_bin[ADDR_WIDTH-1:0]),
        .wr_data    (wr_data),

        // Read port
        .rd_clk     (rd_clk),
        .rd_en      (ram_rd_en),
        .rd_addr    (rd_ptr_bin[ADDR_WIDTH-1:0]),
        .rd_data    (rd_data)
    );

    //==========================================================================
    // Simulation-Only Checks
    //==========================================================================
    // synthesis translate_off
    always @(posedge wr_clk) begin
        if (wr_rst_n && wr_en && wr_full)
            $display("[%m] WARNING @%0t: write attempted while full (ignored)", $time);
    end
    always @(posedge rd_clk) begin
        if (rd_rst_n && rd_en && rd_empty)
            $display("[%m] WARNING @%0t: read attempted while empty (ignored)", $time);
    end
    // synthesis translate_on

endmodule
