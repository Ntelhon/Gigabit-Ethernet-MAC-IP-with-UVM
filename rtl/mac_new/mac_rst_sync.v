//==============================================================================
// Module: mac_rst_sync
// Description: Reset synchronizer - asynchronous assertion, synchronous
//              de-assertion (one function: reset synchronization)
//
// Operation:
//   - When async_rst_n goes LOW, rst_n goes LOW immediately (async assert).
//     All downstream flops using "posedge clk or negedge rst_n" reset at once,
//     even if the clock is not running.
//   - When async_rst_n goes HIGH, the release propagates through a
//     STAGES-deep flop chain, so rst_n de-asserts synchronously to clk and
//     free of metastability. Every clock domain therefore leaves reset on a
//     clean clock edge.
//
// Usage:
//   One instance per clock domain. The output rst_n must be used as the
//   asynchronous active-low reset of every flop in that domain:
//     always @(posedge clk or negedge rst_n) ...
//
// ASIC notes:
//   - The synchronizer flops should be marked with a "don't touch"/sync-cell
//     attribute in synthesis and excluded from reset-domain-crossing checks.
//   - STAGES >= 2. Use 3 for very high clock frequencies if required.
//
// Verification Hooks:
//   - Assertion: rst_n falls combinationally with async_rst_n
//   - Assertion: rst_n rises only synchronous to clk, STAGES cycles after
//                async_rst_n rises
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_rst_sync #(
    parameter STAGES = 2                // Synchronizer depth (>= 2)
) (
    input  wire clk,                    // Destination clock domain
    input  wire async_rst_n,            // Asynchronous reset input (active low)
    output wire rst_n                   // Synchronized reset output (active low)
);

    reg [STAGES-1:0] sync_chain;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            sync_chain <= {STAGES{1'b0}};               // Async assert
        end else begin
            sync_chain <= {sync_chain[STAGES-2:0], 1'b1}; // Sync de-assert
        end
    end

    assign rst_n = sync_chain[STAGES-1];

endmodule
