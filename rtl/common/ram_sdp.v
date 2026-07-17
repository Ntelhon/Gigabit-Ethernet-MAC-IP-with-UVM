//==============================================================================
// File: ram_sdp.v
// Description: Simple Dual-Port RAM (technology swap point)
//
// Purpose:
//   All FIFO storage is implemented through this module. 
//   For FPGA flows the array below infers block/distributed RAM;
//   for ASIC flows replace this file with a memory
//   compiler wrapper exposing the identical port list.
//
// Key properties (intentional, do not "fix"):
//   - Synchronous read, 1-cycle latency (2 cycles when OUT_REG = 1).
//     ASIC SRAM macros are synchronous; asynchronous read is forbidden.
//   - NO rst_n port and NO reset on the array or read path. Memory compilers
//     do not reset arrays; the surrounding FIFO control logic guarantees no
//     read-before-write of a valid location.
//
// Parameters:
//   DATA_W  - Word width.
//   DEPTH   - Number of words (power of 2).
//   ADDR_W  - Address width (defaults to $clog2(DEPTH)).
//   OUT_REG - 1 = add an output register stage (2-cycle read latency).
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module ram_sdp #(
    parameter DATA_W  = 8,
    parameter DEPTH   = 2048,
    parameter ADDR_W  = $clog2(DEPTH),
    parameter OUT_REG = 0
)(
    input  wire              clk,       // Single clock (synchronous FIFO use)

    // Write port
    input  wire              wr_en,     // Write enable
    input  wire [ADDR_W-1:0] wr_addr,   // Write address
    input  wire [DATA_W-1:0] wr_data,   // Write data

    // Read port
    input  wire              rd_en,     // Read enable
    input  wire [ADDR_W-1:0] rd_addr,   // Read address
    output wire [DATA_W-1:0] rd_data    // Read data (holds value between reads)
);

    //--------------------------------------------------------------------------
    // Storage array
    //--------------------------------------------------------------------------
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    reg [DATA_W-1:0] rd_data_q;

    always @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    always @(posedge clk) begin
        if (rd_en) begin
            rd_data_q <= mem[rd_addr];
        end
    end

    //--------------------------------------------------------------------------
    // Optional output register
    //--------------------------------------------------------------------------
    generate
        if (OUT_REG != 0) begin : g_oreg
            reg [DATA_W-1:0] rd_data_q2;
            always @(posedge clk) begin
                rd_data_q2 <= rd_data_q;
            end
            assign rd_data = rd_data_q2;
        end else begin : g_noreg
            assign rd_data = rd_data_q;
        end
    endgenerate

endmodule
