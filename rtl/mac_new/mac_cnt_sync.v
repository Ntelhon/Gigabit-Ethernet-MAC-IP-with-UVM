//==============================================================================
// Module: mac_cnt_sync
// Description: Multi-bit counter synchronizer (one function: Gray-coded CDC
//              of a monotonically incrementing counter)
//
// Operation:
//   - src_cnt is Gray-encoded and registered in the source domain.
//   - Because src_cnt changes by at most 1 per src_clk cycle, consecutive
//     Gray values differ in exactly one bit, so a plain 2-FF synchronizer per
//     bit is CDC-safe (the sampled value is always a real, possibly slightly
//     stale, count).
//   - The synchronized Gray value is decoded back to binary and registered in
//     the destination domain.
//
// Constraints:
//   - src_cnt MUST change by at most +/-1 per src_clk cycle (event counters).
//
// Verification Hooks:
//   - Assertion: src_cnt increments by <= 1 per cycle
//   - Assertion: dst_cnt is monotonically non-decreasing (modulo wrap)
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_cnt_sync #(
    parameter WIDTH = 32                // Counter width
) (
    // Source domain
    input  wire             src_clk,
    input  wire             src_rst_n,  // Source domain reset (async assert)
    input  wire [WIDTH-1:0] src_cnt,    // Binary counter (changes by <=1/cycle)

    // Destination domain
    input  wire             dst_clk,
    input  wire             dst_rst_n,  // Destination domain reset (async assert)
    output reg  [WIDTH-1:0] dst_cnt     // Synchronized binary counter
);

    //==========================================================================
    // Source Domain: binary -> Gray, register
    //==========================================================================
    reg [WIDTH-1:0] gray_src;

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            gray_src <= {WIDTH{1'b0}};
        end else begin
            gray_src <= src_cnt ^ (src_cnt >> 1);
        end
    end

    //==========================================================================
    // Destination Domain: 2-FF synchronizer
    //==========================================================================
    reg [WIDTH-1:0] gray_sync1;
    reg [WIDTH-1:0] gray_sync2;

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            gray_sync1 <= {WIDTH{1'b0}};
            gray_sync2 <= {WIDTH{1'b0}};
        end else begin
            gray_sync1 <= gray_src;
            gray_sync2 <= gray_sync1;
        end
    end

    //==========================================================================
    // Destination Domain: Gray -> binary (bin[i] = ^gray[WIDTH-1:i]), register
    //==========================================================================
    wire [WIDTH-1:0] bin_dec;

    genvar gi;
    generate
        for (gi = 0; gi < WIDTH; gi = gi + 1) begin : g_gray2bin
            assign bin_dec[gi] = ^gray_sync2[WIDTH-1:gi];
        end
    endgenerate

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_cnt <= {WIDTH{1'b0}};
        end else begin
            dst_cnt <= bin_dec;
        end
    end

endmodule
