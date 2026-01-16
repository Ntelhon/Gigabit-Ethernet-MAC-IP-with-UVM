//==============================================================================
// Module: mac_tx_axi_stream
// Description: AXI-Stream Slave interface for MAC TX path
//
// Purpose:
//   Receives Ethernet frames from AXI-Stream interface and converts to
//   internal MAC TX format. Handles backpressure and frame boundaries.
//
// Features:
//   - AXI-Stream slave interface (8-bit data)
//   - Frame boundary detection via tlast
//   - Backpressure support via tready
//   - SOF/EOF generation for MAC TX core
//   - Asynchronous FIFO for clock domain crossing
//
// Interface:
//   - AXI-Stream slave: s_axis_* (system clock domain)
//   - MAC TX output: tx_* (GTX clock domain)
//
// Frame Protocol:
//   - First byte of frame has implicit SOF
//   - tlast marks EOF (last byte of frame)
//   - One complete Ethernet frame per AXI-Stream packet
//   - Frame includes: DA + SA + Type + Payload (no preamble, no FCS)
//
// Clock Domains:
//   - s_axis_aclk: AXI-Stream clock (system clock)
//   - tx_clk: MAC TX clock (GTX clock, typically 125 MHz)
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_tx_axi_stream #(
    parameter DATA_WIDTH = 8,           // AXI-Stream data width (fixed at 8)
    parameter FIFO_DEPTH = 4            // FIFO address width (2^4 = 16 entries)
) (
    //==========================================================================
    // AXI-Stream Slave Interface (System Clock Domain)
    //==========================================================================
    input  wire                     s_axis_aclk,    // AXI-Stream clock
    input  wire                     s_axis_aresetn, // AXI-Stream reset (active low)
    input  wire [DATA_WIDTH-1:0]    s_axis_tdata,   // TX data
    input  wire                     s_axis_tvalid,  // TX data valid
    output wire                     s_axis_tready,  // TX ready (backpressure)
    input  wire                     s_axis_tlast,   // TX last (end of frame)

    //==========================================================================
    // MAC TX Interface (GTX Clock Domain)
    //==========================================================================
    input  wire                     tx_clk,         // MAC TX clock
    input  wire                     tx_rst_n,       // MAC TX reset (active low)
    input  wire                     tx_enable,      // TX path enable
    
    output wire [DATA_WIDTH-1:0]    tx_data,        // TX data to MAC
    output wire                     tx_data_valid,  // TX data valid
    output wire                     tx_sof,         // Start of frame
    output wire                     tx_eof,         // End of frame
    input  wire                     tx_ready        // MAC ready for data
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    // FIFO signals
    wire [DATA_WIDTH+1:0]   fifo_wr_data;   // {eof, sof, data}
    wire                    fifo_wr_en;
    wire                    fifo_full;
    wire [DATA_WIDTH+1:0]   fifo_rd_data;
    wire                    fifo_rd_en;
    wire                    fifo_empty;
    
    // Frame tracking (write side)
    reg                     frame_active;
    wire                    sof_flag;
    wire                    eof_flag;

    //==========================================================================
    // Write Side Logic (AXI-Stream Clock Domain)
    //==========================================================================
    
    // Frame tracking - detect start of new frame
    always @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn) begin
            frame_active <= 1'b0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                if (s_axis_tlast) begin
                    frame_active <= 1'b0;  // End of frame
                end else if (!frame_active) begin
                    frame_active <= 1'b1;  // Start of frame
                end
            end
        end
    end
    
    // SOF is first byte of frame (when frame not active and valid data)
    assign sof_flag = s_axis_tvalid && !frame_active;
    
    // EOF from tlast
    assign eof_flag = s_axis_tlast;
    
    // FIFO write data: {eof, sof, data}
    assign fifo_wr_data = {eof_flag, sof_flag, s_axis_tdata};
    assign fifo_wr_en   = s_axis_tvalid && !fifo_full && tx_enable;
    
    // Backpressure when FIFO full or TX disabled
    assign s_axis_tready = !fifo_full && tx_enable;

    //==========================================================================
    // Async FIFO for Clock Domain Crossing
    //==========================================================================
    
    mac_cdc_fifo #(
        .DATA_WIDTH     (DATA_WIDTH + 2),   // data + sof + eof
        .ADDR_WIDTH     (FIFO_DEPTH)
    ) u_tx_fifo (
        // Write side (AXI-Stream clock)
        .wr_clk         (s_axis_aclk),
        .wr_rst_n       (s_axis_aresetn),
        .wr_en          (fifo_wr_en),
        .wr_data        (fifo_wr_data),
        .wr_full        (fifo_full),
        .wr_almost_full (),
        
        // Read side (MAC TX clock)
        .rd_clk         (tx_clk),
        .rd_rst_n       (tx_rst_n),
        .rd_en          (fifo_rd_en),
        .rd_data        (fifo_rd_data),
        .rd_empty       (fifo_empty),
        .rd_almost_empty()
    );

    //==========================================================================
    // Read Side Logic (MAC TX Clock Domain)
    //==========================================================================
    
    // Extract fields from FIFO data
    assign tx_data       = fifo_rd_data[DATA_WIDTH-1:0];
    assign tx_sof        = fifo_rd_data[DATA_WIDTH];
    assign tx_eof        = fifo_rd_data[DATA_WIDTH+1];
    assign tx_data_valid = !fifo_empty;
    
    // Read from FIFO when MAC is ready and FIFO has data
    assign fifo_rd_en    = tx_ready && !fifo_empty;

endmodule
