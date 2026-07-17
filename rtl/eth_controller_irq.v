//==============================================================================
// File: eth_controller_irq.v
// Description: Unified Interrupt Controller for Ethernet Controller
//
// Purpose:
//   Aggregates interrupt sources from MAC and DMA subsystems into two
//   separate interrupt outputs: mac_irq and dma_irq.
//
// Interrupt Philosophy:
//   - Each subsystem manages its own interrupt status and mask registers
//   - This module registers the pre-masked interrupt levels onto the sys_clk
//     domain so the external interrupt pins are driven by flops (glitch-free)
//     and are cleanly de-asserted during reset.
//   - mac_irq: Registered copy of the MAC's interrupt output
//   - dma_irq: Registered copy of the DMA's interrupt output (tied low if
//     DMA disabled)
//
// Reset:
//   rst_n is asynchronous at this boundary; it is synchronized here with a
//   rst_sync (async assert, sync de-assert) so the interrupt flops leave
//   reset on a clean sys_clk edge.
//
// Note: The actual interrupt status/mask registers are in mac_regs and
// dma_regs respectively. This module provides the external interrupt pins.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_controller_irq #(
    parameter DMA_ENABLE = 1            // Enable DMA subsystem
)(
    // Clock and Reset
    input  wire         clk,
    input  wire         rst_n,          // Asynchronous active-low reset

    //--------------------------------------------------------------------------
    // MAC Interrupt Source
    //--------------------------------------------------------------------------
    input  wire         mac_irq_in,     // Pre-masked MAC interrupt level

    //--------------------------------------------------------------------------
    // DMA Interrupt Source
    //--------------------------------------------------------------------------
    input  wire         dma_irq_in,     // Pre-masked DMA interrupt level

    //--------------------------------------------------------------------------
    // Interrupt Outputs
    //--------------------------------------------------------------------------
    output wire         mac_irq,        // MAC interrupt output (registered)
    output wire         dma_irq         // DMA interrupt output (registered)
);

    //--------------------------------------------------------------------------
    // Reset synchronizer (async assert, sync de-assert) for the sys_clk domain
    //--------------------------------------------------------------------------
    wire rst_sync_n;
    rst_sync u_rst_sync (
        .clk         (clk),
        .async_rst_n (rst_n),
        .rst_n       (rst_sync_n)
    );

    //--------------------------------------------------------------------------
    // MAC Interrupt Output Register
    //--------------------------------------------------------------------------
    reg mac_irq_q;
    always @(posedge clk or negedge rst_sync_n) begin
        if (!rst_sync_n)
            mac_irq_q <= 1'b0;
        else
            mac_irq_q <= mac_irq_in;
    end
    assign mac_irq = mac_irq_q;

    //--------------------------------------------------------------------------
    // DMA Interrupt Output Register (tied low when DMA is disabled)
    //--------------------------------------------------------------------------
    generate
        if (DMA_ENABLE) begin : gen_dma_irq
            reg dma_irq_q;
            always @(posedge clk or negedge rst_sync_n) begin
                if (!rst_sync_n)
                    dma_irq_q <= 1'b0;
                else
                    dma_irq_q <= dma_irq_in;
            end
            assign dma_irq = dma_irq_q;
        end else begin : gen_no_dma_irq
            assign dma_irq = 1'b0;
        end
    endgenerate

endmodule
