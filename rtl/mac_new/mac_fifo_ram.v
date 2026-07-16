//==============================================================================
// Module: mac_fifo_ram
// Description: Dual-clock simple dual-port RAM (one function: FIFO storage)
//
// Same storage methodology as the DMA subsystem: the RAM is a separate
// module from the FIFO controller so it can be swapped for a compiled
// dual-port SRAM macro at ASIC integration without touching control logic.
//
// Features:
//   - One synchronous write port (wr_clk domain)
//   - One synchronous read port (rd_clk domain, 1-cycle read latency)
//   - No reset on the memory array (SRAM-macro compatible)
//   - Registered read data (maps to SRAM output register / BRAM read reg)
//
// The FIFO controller (mac_cdc_fifo) guarantees by construction that the
// read and write ports never access the same address simultaneously, so no
// collision handling is required here.
//
// Verification Hooks:
//   - Assertion (in controller): no simultaneous same-address rd/wr
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_fifo_ram #(
    parameter DATA_WIDTH = 8,           // Word width in bits
    parameter ADDR_WIDTH = 4            // Address width (depth = 2^ADDR_WIDTH)
) (
    //==========================================================================
    // Write Port (wr_clk domain)
    //==========================================================================
    input  wire                     wr_clk,
    input  wire                     wr_en,
    input  wire [ADDR_WIDTH-1:0]    wr_addr,
    input  wire [DATA_WIDTH-1:0]    wr_data,

    //==========================================================================
    // Read Port (rd_clk domain) - synchronous read, 1-cycle latency
    //==========================================================================
    input  wire                     rd_clk,
    input  wire                     rd_en,
    input  wire [ADDR_WIDTH-1:0]    rd_addr,
    output reg  [DATA_WIDTH-1:0]    rd_data
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Write port
    always @(posedge wr_clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    // Read port (registered output; holds value when rd_en is low)
    always @(posedge rd_clk) begin
        if (rd_en) begin
            rd_data <= mem[rd_addr];
        end
    end

endmodule
