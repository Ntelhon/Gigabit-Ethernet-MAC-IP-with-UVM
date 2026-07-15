//==============================================================================
// File: dma_sync_cell.v
// Description: 2-Flop Synchronizer Cell (reserved CDC primitive)
//
// Purpose:
//   Blessed clock-domain-crossing primitive for future multi-clock variants
//   of the DMA subsystem. Not instantiated in the single-clock configuration.
//   Registers carry ASYNC_REG attributes so FPGA tools keep them adjacent;
//   for ASIC, replace with library sync cells keeping this port list.
//
// Parameters:
//   WIDTH     - Number of independent single-bit synchronizers (default 1).
//               NOTE: only use >1 for quasi-static or Gray-coded buses.
//   RESET_VAL - Reset value applied to both stages.
//
// Clocking / Reset:
//   dst_clk domain only. Asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_sync_cell #(
    parameter WIDTH     = 1,
    parameter RESET_VAL = 0
)(
    input  wire             dst_clk,    // Destination clock domain
    input  wire             rst_n,      // Async active-low reset (dst domain)
    input  wire [WIDTH-1:0] din,        // Asynchronous input
    output wire [WIDTH-1:0] dout        // Synchronized output
);

    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_ff1;
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_ff2;

    always @(posedge dst_clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= {WIDTH{RESET_VAL[0]}};
            sync_ff2 <= {WIDTH{RESET_VAL[0]}};
        end else begin
            sync_ff1 <= din;
            sync_ff2 <= sync_ff1;
        end
    end

    assign dout = sync_ff2;

endmodule
