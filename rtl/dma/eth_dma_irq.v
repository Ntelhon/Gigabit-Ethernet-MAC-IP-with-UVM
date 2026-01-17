//==============================================================================
// Module: eth_dma_irq
// Description: Interrupt controller for Ethernet DMA
//
// Features:
//   - Combines multiple interrupt sources
//   - Maskable interrupts
//   - Separate outputs for each interrupt type
//   - Combined interrupt output (OR of all enabled interrupts)
//
// Interrupt Sources:
//   [0] - TX_DONE:  TX descriptor complete
//   [1] - RX_DONE:  RX descriptor complete
//   [2] - TX_ERROR: TX DMA error
//   [3] - RX_ERROR: RX DMA error
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_dma_irq (
    input  wire         clk,
    input  wire         rst_n,
    
    // Raw interrupt inputs
    input  wire         int_tx_done_raw,
    input  wire         int_rx_done_raw,
    input  wire         int_tx_err_raw,
    input  wire         int_rx_err_raw,
    
    // Interrupt mask
    input  wire [3:0]   irq_mask,
    
    // Interrupt outputs
    output reg          irq_tx_done,
    output reg          irq_rx_done,
    output reg          irq_tx_error,
    output reg          irq_rx_error,
    output reg          irq_combined
);

    //==========================================================================
    // Mask and Generate Interrupts
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            irq_tx_done   <= 1'b0;
            irq_rx_done   <= 1'b0;
            irq_tx_error  <= 1'b0;
            irq_rx_error  <= 1'b0;
            irq_combined  <= 1'b0;
        end else begin
            // Apply mask to each interrupt
            irq_tx_done  <= int_tx_done_raw & irq_mask[0];
            irq_rx_done  <= int_rx_done_raw & irq_mask[1];
            irq_tx_error <= int_tx_err_raw  & irq_mask[2];
            irq_rx_error <= int_rx_err_raw  & irq_mask[3];
            
            // Combined interrupt (OR of all enabled interrupts)
            irq_combined <= (int_tx_done_raw & irq_mask[0]) |
                           (int_rx_done_raw & irq_mask[1]) |
                           (int_tx_err_raw  & irq_mask[2]) |
                           (int_rx_err_raw  & irq_mask[3]);
        end
    end

endmodule
