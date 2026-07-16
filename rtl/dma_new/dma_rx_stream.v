//==============================================================================
// File: dma_rx_stream.v
// Description: RX AXI-Stream Receiver (MAC -> FIFO)
//
// Purpose:
//   Accepts packets from the MAC on an 8-bit AXI-Stream slave and writes
//   them into the RX data FIFO (PKT_MODE). STORE-AND-FORWARD with
//   commit/rewind semantics:
//     - Bytes are pushed as they arrive (uncommitted).
//     - On a clean tlast: 'commit' makes the packet visible downstream and
//       a metadata entry {err_crc, reserved, length} is pushed.
//     - On overflow (data FIFO full) or oversize (> MAX_PKT_LEN): 'rewind'
//       discards everything uncommitted and the rest of the frame is
//       swallowed in ST_DROP. The whole packet is dropped, never truncated
//       at this stage.
//   tuser at tlast carries the MAC's error flag (CRC/RX error) and is
//   recorded in the metadata err_crc bit.
//
// Backpressure: tready deasserts when disabled or the metadata FIFO is
// full; the MAC-side RX FIFO absorbs the latency.
//
// Reset: asynchronous active-low rst_n; soft_reset returns to ST_RECV
// (the channel top flushes the FIFOs).
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_rx_stream #(
    parameter AXIS_DATA_W = 8,          // Stream width
    parameter LEN_W       = 16,         // Packet length field width
    parameter MAX_PKT_LEN = 16383       // Longest accepted packet (bytes)
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   soft_reset,     // Sync channel reset
    input  wire                   enable,         // Channel enable

    // AXI-Stream slave (from MAC)
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tuser,   // Error flag at tlast

    // RX data FIFO write side (PKT_MODE FIFO)
    output wire                   fifo_wr_en,
    output wire [AXIS_DATA_W-1:0] fifo_wr_data,
    input  wire                   fifo_full,
    output wire                   fifo_commit,    // Pulse at accepted tlast
    output wire                   fifo_rewind,    // Pulse on drop decision

    // Packet metadata FIFO write side
    output wire                   meta_wr_en,
    output wire [LEN_W+1:0]       meta_wr_data,   // {err_crc, rsvd, length}
    input  wire                   meta_full,

    // Statistics pulses
    output wire                   pkt_rcvd,       // Packet committed
    output wire                   pkt_dropped,    // Packet discarded
    output wire                   byte_rcvd       // Byte accepted into FIFO
);

    //--------------------------------------------------------------------------
    // FSM states
    //--------------------------------------------------------------------------
    localparam [1:0] ST_RECV = 2'd0,    // Accepting packet bytes
                     ST_DROP = 2'd1;    // Swallowing rest of dropped frame

    reg [1:0]       state;
    reg [LEN_W-1:0] len_cnt;            // Bytes accepted so far this packet

    //--------------------------------------------------------------------------
    // Handshake
    //--------------------------------------------------------------------------
    assign s_axis_tready = (state == ST_DROP) ? 1'b1
                                              : (enable && !meta_full);

    wire beat = s_axis_tvalid && s_axis_tready;

    // Drop decision: byte arrived but cannot be stored, or packet oversize
    wire drop_now = (state == ST_RECV) && beat &&
                    (fifo_full || (len_cnt == MAX_PKT_LEN[LEN_W-1:0]));

    wire accept_byte = (state == ST_RECV) && beat && !drop_now;

    //--------------------------------------------------------------------------
    // FIFO write side
    //--------------------------------------------------------------------------
    assign fifo_wr_en   = accept_byte;
    assign fifo_wr_data = s_axis_tdata;
    assign fifo_commit  = accept_byte && s_axis_tlast;
    assign fifo_rewind  = drop_now;

    //--------------------------------------------------------------------------
    // Metadata push at accepted end-of-packet
    // length = bytes before this beat + the tlast byte itself
    //--------------------------------------------------------------------------
    wire [LEN_W-1:0] pkt_length = len_cnt + {{(LEN_W-1){1'b0}}, 1'b1};

    assign meta_wr_en   = fifo_commit;
    assign meta_wr_data = {s_axis_tuser, 1'b0, pkt_length};

    //--------------------------------------------------------------------------
    // Statistics
    //--------------------------------------------------------------------------
    assign pkt_rcvd    = fifo_commit;
    assign byte_rcvd   = accept_byte;
    assign pkt_dropped = (drop_now       && s_axis_tlast) ||
                         (state == ST_DROP && beat && s_axis_tlast);

    //--------------------------------------------------------------------------
    // FSM
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= ST_RECV;
            len_cnt <= {LEN_W{1'b0}};
        end else if (soft_reset) begin
            state   <= ST_RECV;
            len_cnt <= {LEN_W{1'b0}};
        end else begin
            case (state)
                ST_RECV: begin
                    if (drop_now) begin
                        len_cnt <= {LEN_W{1'b0}};
                        // If the offending byte was also tlast the frame is
                        // over: stay in ST_RECV for the next packet.
                        if (!s_axis_tlast) begin
                            state <= ST_DROP;
                        end
                    end else if (accept_byte) begin
                        if (s_axis_tlast) begin
                            len_cnt <= {LEN_W{1'b0}};
                        end else begin
                            len_cnt <= len_cnt + {{(LEN_W-1){1'b0}}, 1'b1};
                        end
                    end
                end

                ST_DROP: begin
                    if (beat && s_axis_tlast) begin
                        len_cnt <= {LEN_W{1'b0}};
                        state   <= ST_RECV;
                    end
                end

                default: begin
                    state <= ST_RECV;
                end
            endcase
        end
    end

endmodule
