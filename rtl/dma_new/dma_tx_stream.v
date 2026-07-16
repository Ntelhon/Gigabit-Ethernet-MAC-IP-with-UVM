//==============================================================================
// File: dma_tx_stream.v
// Description: TX AXI-Stream Transmitter (FIFO -> MAC)
//
// Purpose:
//   Streams fully buffered packets from the TX data FIFO to the MAC over an
//   8-bit AXI-Stream master. STORE-AND-FORWARD: a packet is only started
//   once its metadata entry appears in the packet-metadata FIFO, which the
//   fetch engine pushes after the packet's last byte is in the data FIFO.
//   This guarantees no mid-packet underrun toward the MAC.
//
// Metadata format: meta_rd_data = {eop_flag(1), length[LEN_W-1:0]}.
//   eop_flag is always 1 in the current design (one entry per full packet).
//
// FSM: ST_IDLE -> ST_STREAM -> ST_GAP -> ST_IDLE
//   ST_GAP inserts one idle cycle between packets (clean tlast separation).
//
// Reset: asynchronous active-low rst_n; soft_reset returns to ST_IDLE
// (the channel top flushes the FIFOs).
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_tx_stream #(
    parameter AXIS_DATA_W = 8,      // Stream width (8 for GMII-rate MAC)
    parameter LEN_W       = 16      // Packet length field width
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   soft_reset,     // Sync channel reset
    input  wire                   enable,         // Channel enable

    // TX data FIFO read side (FWFT)
    output wire                   fifo_rd_en,
    input  wire [AXIS_DATA_W-1:0] fifo_rd_data,
    input  wire                   fifo_empty,

    // Packet metadata FIFO read side (FWFT)
    output wire                   meta_rd_en,
    input  wire [LEN_W:0]         meta_rd_data,   // {eop, length}
    input  wire                   meta_empty,

    // AXI-Stream master (to MAC)
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire [AXIS_DATA_W-1:0] m_axis_tdata,
    output wire                   m_axis_tlast,
    output wire                   m_axis_tuser,   // Tied 0 (no TX error inject)

    // Statistics pulses
    output wire                   pkt_sent,       // 1-cycle: tlast beat accepted
    output wire                   byte_sent,      // 1-cycle per accepted byte

    // Status
    output wire                   busy            // Mid-packet or work queued
);

    //--------------------------------------------------------------------------
    // FSM states
    //--------------------------------------------------------------------------
    localparam [1:0] ST_IDLE   = 2'd0,  // Wait for a packet metadata entry
                     ST_STREAM = 2'd1,  // Stream length bytes to the MAC
                     ST_GAP    = 2'd2;  // One-cycle inter-packet gap

    reg [1:0]       state;
    reg [LEN_W-1:0] byte_cnt;           // Bytes remaining in current packet

    wire [LEN_W-1:0] meta_length = meta_rd_data[LEN_W-1:0];

    //--------------------------------------------------------------------------
    // Metadata pop: take one entry when idle and enabled.
    // Zero-length guard: entry consumed, no packet streamed.
    //--------------------------------------------------------------------------
    assign meta_rd_en = (state == ST_IDLE) && enable && !meta_empty
                        && !soft_reset;

    //--------------------------------------------------------------------------
    // AXI-Stream datapath (data FIFO is FWFT: rd_data valid when !empty)
    //--------------------------------------------------------------------------
    assign m_axis_tvalid = (state == ST_STREAM) && !fifo_empty;
    assign m_axis_tdata  = fifo_rd_data;
    assign m_axis_tlast  = (byte_cnt == {{(LEN_W-1){1'b0}}, 1'b1});
    assign m_axis_tuser  = 1'b0;

    wire beat = m_axis_tvalid && m_axis_tready;

    assign fifo_rd_en = beat;

    assign byte_sent = beat;
    assign pkt_sent  = beat && m_axis_tlast;

    assign busy = (state != ST_IDLE) || !meta_empty;

    //--------------------------------------------------------------------------
    // FSM
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= ST_IDLE;
            byte_cnt <= {LEN_W{1'b0}};
        end else if (soft_reset) begin
            state    <= ST_IDLE;
            byte_cnt <= {LEN_W{1'b0}};
        end else begin
            case (state)
                ST_IDLE: begin
                    if (meta_rd_en) begin
                        if (meta_length != {LEN_W{1'b0}}) begin
                            byte_cnt <= meta_length;
                            state    <= ST_STREAM;
                        end
                        // length == 0: metadata consumed, stay idle
                    end
                end

                ST_STREAM: begin
                    if (beat) begin
                        byte_cnt <= byte_cnt - {{(LEN_W-1){1'b0}}, 1'b1};
                        if (m_axis_tlast) begin
                            state <= ST_GAP;
                        end
                    end
                end

                ST_GAP: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
