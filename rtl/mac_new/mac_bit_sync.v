//==============================================================================
// Module: mac_bit_sync
// Description: Single-bit level synchronizer (one function: 2-FF CDC of a
//              quasi-static level signal)
//
// Usage:
//   For slowly-changing level/control signals only (enables, active flags).
//   NOT for pulses (use mac_pulse_sync) and NOT for multi-bit buses
//   (use mac_cnt_sync / mac_cdc_fifo).
//
// ASIC notes:
//   - Flops should be mapped to synchronizer cells / marked ASYNC_REG.
//
// Verification Hooks:
//   - Assertion: q changes only after d has been stable for STAGES dst cycles
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_bit_sync #(
    parameter STAGES = 2                // Synchronizer depth (>= 2)
) (
    input  wire clk,                    // Destination clock
    input  wire rst_n,                  // Destination domain reset (async assert)
    input  wire d,                      // Input level (source domain)
    output wire q                       // Synchronized level (destination domain)
);

    reg [STAGES-1:0] sync_chain;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_chain <= {STAGES{1'b0}};
        end else begin
            sync_chain <= {sync_chain[STAGES-2:0], d};
        end
    end

    assign q = sync_chain[STAGES-1];

endmodule
