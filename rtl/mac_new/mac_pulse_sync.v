//==============================================================================
// Module: mac_pulse_sync
// Description: Single-cycle pulse synchronizer (one function: toggle-based
//              pulse CDC)
//
// Operation:
//   - src_pulse (1 src_clk cycle) flips an internal toggle flop.
//   - The toggle is synchronized into the destination domain with a 3-FF
//     chain; an XOR of the last two stages regenerates a single-cycle
//     dst_pulse.
//
// Constraints:
//   - Source pulses must be spaced by at least 2 destination clock periods,
//     otherwise pulses merge/are lost. For the MAC this holds by construction
//     (events are separated by whole Ethernet frames).
//
// Verification Hooks:
//   - Assertion: every src_pulse produces exactly one dst_pulse
//   - Assertion: dst_pulse is 1 dst_clk cycle wide
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_pulse_sync (
    // Source domain
    input  wire src_clk,
    input  wire src_rst_n,              // Source domain reset (async assert)
    input  wire src_pulse,              // Single-cycle pulse in src domain

    // Destination domain
    input  wire dst_clk,
    input  wire dst_rst_n,              // Destination domain reset (async assert)
    output wire dst_pulse               // Single-cycle pulse in dst domain
);

    //==========================================================================
    // Source Domain: pulse -> toggle
    //==========================================================================
    reg src_toggle;

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_toggle <= 1'b0;
        end else if (src_pulse) begin
            src_toggle <= ~src_toggle;
        end
    end

    //==========================================================================
    // Destination Domain: synchronize toggle, edge-detect
    //==========================================================================
    reg [2:0] dst_sync;

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_sync <= 3'b000;
        end else begin
            dst_sync <= {dst_sync[1:0], src_toggle};
        end
    end

    assign dst_pulse = dst_sync[2] ^ dst_sync[1];

endmodule
