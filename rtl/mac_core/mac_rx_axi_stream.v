//==============================================================================
// Module: mac_rx_axi_stream
// Description: AXI-Stream Master interface for MAC RX path
//
// Purpose:
//   Receives Ethernet frames from MAC RX core and converts to AXI-Stream
//   format. Handles frame boundaries and flow control.
//
// Features:
//   - AXI-Stream master interface (8-bit data)
//   - Frame boundary detection via EOF from MAC
//   - Flow control via tready backpressure
//   - Asynchronous FIFO for clock domain crossing
//   - Frame drop on FIFO overflow (with status)
//
// Interface:
//   - MAC RX input: rx_* (RX clock domain)
//   - AXI-Stream master: m_axis_* (system clock domain)
//
// Frame Protocol:
//   - tlast asserted on last byte of frame
//   - One complete Ethernet frame per AXI-Stream packet
//   - Frame includes: DA + SA + Type + Payload (no preamble, no FCS)
//
// Clock Domains:
//   - rx_clk: MAC RX clock (from PHY, typically 125 MHz)
//   - m_axis_aclk: AXI-Stream clock (system clock)
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_rx_axi_stream #(
    parameter DATA_WIDTH = 8,           // AXI-Stream data width (fixed at 8)
    parameter FIFO_DEPTH = 4            // FIFO address width (2^4 = 16 entries)
) (
    //==========================================================================
    // MAC RX Interface (RX Clock Domain)
    //==========================================================================
    input  wire                     rx_clk,         // MAC RX clock
    input  wire                     rx_rst_n,       // MAC RX reset (active low)
    input  wire                     rx_enable,      // RX path enable
    
    input  wire [DATA_WIDTH-1:0]    rx_data,        // RX data from MAC
    input  wire                     rx_data_valid,  // RX data valid
    input  wire                     rx_sof,         // Start of frame
    input  wire                     rx_eof,         // End of frame
    input  wire                     rx_error,       // Frame error (CRC, etc.)
    output wire                     rx_ready,       // Ready for data

    //==========================================================================
    // AXI-Stream Master Interface (System Clock Domain)
    //==========================================================================
    input  wire                     m_axis_aclk,    // AXI-Stream clock
    input  wire                     m_axis_aresetn, // AXI-Stream reset (active low)
    output wire [DATA_WIDTH-1:0]    m_axis_tdata,   // RX data
    output wire                     m_axis_tvalid,  // RX data valid
    input  wire                     m_axis_tready,  // RX ready (backpressure)
    output wire                     m_axis_tlast,   // RX last (end of frame)
    output wire                     m_axis_tuser,   // RX user (frame error)

    //==========================================================================
    // Status
    //==========================================================================
    output reg                      fifo_overflow   // FIFO overflow occurred
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    // FIFO signals
    wire [DATA_WIDTH+2:0]   fifo_wr_data;   // {error, eof, data}
    wire                    fifo_wr_en;
    wire                    fifo_full;
    wire [DATA_WIDTH+2:0]   fifo_rd_data;
    wire                    fifo_rd_en;
    wire                    fifo_empty;
    
    // Frame tracking
    reg                     frame_in_progress;
    reg                     frame_error_sticky;

    //==========================================================================
    // Write Side Logic (MAC RX Clock Domain)
    //==========================================================================
    
    // Track frame in progress
    always @(posedge rx_clk) begin
        if (!rx_rst_n) begin
            frame_in_progress <= 1'b0;
            frame_error_sticky <= 1'b0;
        end else begin
            if (rx_data_valid && rx_sof) begin
                frame_in_progress <= 1'b1;
                frame_error_sticky <= 1'b0;
            end else if (rx_data_valid && rx_eof) begin
                frame_in_progress <= 1'b0;
            end
            
            // Latch error during frame
            if (rx_error && frame_in_progress) begin
                frame_error_sticky <= 1'b1;
            end
        end
    end
    
    // FIFO write data: {error, eof, data}
    // Error is reported with EOF to mark bad frame
    assign fifo_wr_data = {(rx_error | frame_error_sticky) & rx_eof, rx_eof, rx_data};
    assign fifo_wr_en   = rx_data_valid && rx_enable && !fifo_full;
    
    // Ready when FIFO not full and RX enabled
    assign rx_ready = !fifo_full && rx_enable;
    
    // Track overflow
    always @(posedge rx_clk) begin
        if (!rx_rst_n) begin
            fifo_overflow <= 1'b0;
        end else begin
            if (rx_data_valid && fifo_full) begin
                fifo_overflow <= 1'b1;
            end
        end
    end

    //==========================================================================
    // Async FIFO for Clock Domain Crossing
    //==========================================================================
    
    mac_cdc_fifo #(
        .DATA_WIDTH     (DATA_WIDTH + 3),   // data + eof + error
        .ADDR_WIDTH     (FIFO_DEPTH)
    ) u_rx_fifo (
        // Write side (MAC RX clock)
        .wr_clk         (rx_clk),
        .wr_rst_n       (rx_rst_n),
        .wr_en          (fifo_wr_en),
        .wr_data        (fifo_wr_data),
        .wr_full        (fifo_full),
        .wr_almost_full (),
        
        // Read side (AXI-Stream clock)
        .rd_clk         (m_axis_aclk),
        .rd_rst_n       (m_axis_aresetn),
        .rd_en          (fifo_rd_en),
        .rd_data        (fifo_rd_data),
        .rd_empty       (fifo_empty),
        .rd_almost_empty()
    );

    //==========================================================================
    // Read Side Logic (AXI-Stream Clock Domain)
    //==========================================================================
    
    // Extract fields from FIFO data
    assign m_axis_tdata  = fifo_rd_data[DATA_WIDTH-1:0];
    assign m_axis_tlast  = fifo_rd_data[DATA_WIDTH];
    assign m_axis_tuser  = fifo_rd_data[DATA_WIDTH+1];  // Error indicator
    assign m_axis_tvalid = !fifo_empty;
    
    // Read from FIFO when downstream is ready and FIFO has data
    assign fifo_rd_en    = m_axis_tready && !fifo_empty;

endmodule
