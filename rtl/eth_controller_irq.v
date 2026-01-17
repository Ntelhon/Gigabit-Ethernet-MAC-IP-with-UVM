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
//   - This module simply combines the pre-masked interrupts
//   - mac_irq: Derived from MAC's interrupt output
//   - dma_irq: Derived from DMA's interrupt output (tied low if DMA disabled)
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
    input  wire         rst_n,
    
    //--------------------------------------------------------------------------
    // MAC Interrupt Source
    //--------------------------------------------------------------------------
    input  wire         mac_irq_in,     // Pre-masked MAC interrupt
    
    //--------------------------------------------------------------------------
    // DMA Interrupt Source
    //--------------------------------------------------------------------------
    input  wire         dma_irq_in,     // Pre-masked DMA interrupt
    
    //--------------------------------------------------------------------------
    // Interrupt Outputs
    //--------------------------------------------------------------------------
    output wire         mac_irq,        // MAC interrupt output
    output wire         dma_irq         // DMA interrupt output
);

    //--------------------------------------------------------------------------
    // Interrupt Output Logic
    //--------------------------------------------------------------------------
    // Directly pass through the masked interrupts from each subsystem
    // The subsystems handle status/mask logic internally
    
    assign mac_irq = mac_irq_in;
    
    // DMA interrupt is tied low when DMA is disabled
    generate
        if (DMA_ENABLE) begin : gen_dma_irq
            assign dma_irq = dma_irq_in;
        end else begin : gen_no_dma_irq
            assign dma_irq = 1'b0;
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Optional: Interrupt synchronization/edge detection
    //--------------------------------------------------------------------------
    // If level-sensitive interrupts need edge detection for certain systems,
    // add synchronizers here. Currently assumes level-sensitive interrupts.

endmodule
