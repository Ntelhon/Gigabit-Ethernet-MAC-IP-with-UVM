//==============================================================================
// Module: mac_rx
// Description: Ethernet RX state machine for Gigabit MAC
//              (one function: GMII frame reception)
//
// Features:
//   - Complete Ethernet frame reception
//   - Preamble and SFD detection
//   - Frame delimiting based on RX_DV
//   - CRC32 verification (via external mac_crc32)
//   - Runt frame detection (< MIN_FRAME_SIZE bytes)
//   - Oversize frame detection (> MAX_FRAME_SIZE bytes)
//   - CRC error detection
//   - Frame and error counters
//
// Frame Structure (received order):
//   [Preamble: 0x55 x N][SFD: 0xD5][Dest MAC][Src MAC][Type/Len][Payload][FCS]
//
// State Machine:
//   IDLE -> PREAMBLE -> DATA -> CHECK -> (COMMIT or DISCARD) -> IDLE
//
// Error Handling:
//   - CRC error: frame discarded, error counter incremented, IRQ pulse
//   - Runt frame: frame discarded, error counter incremented, IRQ pulse
//   - Oversize frame: frame discarded, error counter incremented (no
//     dedicated IRQ in Phase 0)
//   - RX_ER during frame: frame discarded
//
// Verification Hooks:
//   - Assertion: Frame size validated (runt and oversize)
//   - Assertion: CRC residue check
//   - Assertion: Proper preamble/SFD sequence
//   - Coverage: All error conditions, various frame sizes
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_rx #(
    parameter MIN_FRAME_SIZE = 64,      // Minimum frame size (including FCS)
    parameter MAX_FRAME_SIZE = 1518     // Maximum frame size (including FCS, no jumbo)
) (
    //==========================================================================
    // Clock and Reset
    //==========================================================================
    input  wire        clk,             // GMII RX clock (125 MHz)
    input  wire        rst_n,           // Active-low reset (async assert, sync deassert)

    //==========================================================================
    // Control Interface
    //==========================================================================
    input  wire        rx_enable,       // RX path enable (from registers)

    //==========================================================================
    // GMII RX Input Interface
    //==========================================================================
    input  wire [7:0]  gmii_rxd,        // RX data from GMII
    input  wire        gmii_rx_dv,      // RX data valid from GMII
    input  wire        gmii_rx_er,      // RX error from GMII

    //==========================================================================
    // RX Data Output Interface (to FIFO/upper layer)
    //==========================================================================
    output reg  [7:0]  rx_data,         // RX data byte
    output reg         rx_data_valid,   // RX data valid
    output reg         rx_sof,          // Start of frame
    output reg         rx_eof,          // End of frame
    output reg         rx_frame_good,   // Frame passed CRC check
    output reg         rx_frame_bad,    // Frame failed (CRC, runt, oversize, RX_ER)

    //==========================================================================
    // CRC Interface (directly to mac_crc32)
    //==========================================================================
    output wire        crc_init,        // Initialize CRC
    output wire        crc_enable,      // Enable CRC calculation
    output wire [7:0]  crc_data,        // Data to CRC
    input  wire [31:0] crc_out,         // Current CRC value

    //==========================================================================
    // Status Interface
    //==========================================================================
    output reg         rx_active,       // RX currently active
    output reg  [31:0] rx_frame_cnt,    // Received frame counter (good frames)
    output reg  [31:0] rx_err_cnt,      // Error frame counter

    //==========================================================================
    // Interrupt Pulses
    //==========================================================================
    output reg         int_rx_received, // Good frame received (pulse)
    output reg         int_rx_crc_err,  // CRC error detected (pulse)
    output reg         int_rx_runt      // Runt frame detected (pulse)
);

    //==========================================================================
    // Local Parameters
    //==========================================================================
    localparam PREAMBLE_BYTE = 8'h55;
    localparam SFD_BYTE      = 8'hD5;

    // Magic CRC residue after processing a valid frame + FCS through the
    // reflected CRC32 algorithm (poly 0xEDB88320): the raw CRC register equals
    // 0xDEBB20E3. Since mac_crc32 outputs the complemented value (~crc_reg),
    // we compare against CRC_RESIDUE = ~0xDEBB20E3 = 0x2144DF1C.
    localparam CRC_RESIDUE   = 32'h2144DF1C;

    //==========================================================================
    // State Machine Encoding
    //==========================================================================
    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_PREAMBLE = 3'd1;
    localparam [2:0] ST_DATA     = 3'd2;
    localparam [2:0] ST_CHECK    = 3'd3;
    localparam [2:0] ST_COMMIT   = 3'd4;
    localparam [2:0] ST_DISCARD  = 3'd5;

    //==========================================================================
    // State and Counter Registers
    //==========================================================================
    reg [2:0]  state;
    reg [2:0]  next_state;
    reg [15:0] frame_byte_cnt;          // Counts received frame bytes
    reg        rx_er_detected;          // Error detected during frame
    reg        first_data_byte;         // Flag for SOF generation

    //==========================================================================
    // RX Data Latching (pipeline stage for EOF detection)
    //==========================================================================
    reg [7:0]  rx_data_latched;
    reg        rx_data_valid_latched;
    reg        rx_sof_latched;

    //==========================================================================
    // Frame Classification (shared by CHECK transition, flags, and IRQs)
    //==========================================================================
    wire is_runt;
    wire is_oversize;
    wire is_crc_err;

    assign is_runt     = (frame_byte_cnt < MIN_FRAME_SIZE[15:0]);
    assign is_oversize = (frame_byte_cnt > MAX_FRAME_SIZE[15:0]);
    assign is_crc_err  = (crc_out != CRC_RESIDUE);

    wire frame_failed;
    assign frame_failed = rx_er_detected || is_runt || is_oversize || is_crc_err;

    //==========================================================================
    // CRC Interface
    //==========================================================================
    // CRC init when idle or when in PREAMBLE and about to transition to DATA
    assign crc_init   = (state == ST_IDLE) ||
                        ((state == ST_PREAMBLE) && gmii_rx_dv && (gmii_rxd == SFD_BYTE));
    assign crc_enable = (state == ST_DATA) && gmii_rx_dv;
    assign crc_data   = gmii_rxd;

    //==========================================================================
    // State Machine - Sequential
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end

    //==========================================================================
    // State Machine - Combinational Next State
    //==========================================================================
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (rx_enable && gmii_rx_dv) begin
                    if (gmii_rxd == PREAMBLE_BYTE) begin
                        next_state = ST_PREAMBLE;
                    end else if (gmii_rxd == SFD_BYTE) begin
                        // Short preamble, immediate SFD
                        next_state = ST_DATA;
                    end
                end
            end

            ST_PREAMBLE: begin
                if (!gmii_rx_dv) begin
                    // Premature end
                    next_state = ST_IDLE;
                end else if (gmii_rxd == SFD_BYTE) begin
                    // SFD detected - the next byte is the first data byte
                    next_state = ST_DATA;
                end else if (gmii_rxd != PREAMBLE_BYTE) begin
                    // Invalid preamble pattern
                    next_state = ST_IDLE;
                end
            end

            ST_DATA: begin
                if (!gmii_rx_dv) begin
                    // End of frame - go to check
                    next_state = ST_CHECK;
                end
            end

            ST_CHECK: begin
                // Evaluate error flags, frame size, and CRC residue
                if (frame_failed) begin
                    next_state = ST_DISCARD;
                end else begin
                    next_state = ST_COMMIT;
                end
            end

            ST_COMMIT: begin
                next_state = ST_IDLE;
            end

            ST_DISCARD: begin
                next_state = ST_IDLE;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    //==========================================================================
    // Frame Byte Counter
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_byte_cnt <= 16'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    frame_byte_cnt <= 16'd0;
                end

                ST_DATA: begin
                    if (gmii_rx_dv) begin
                        frame_byte_cnt <= frame_byte_cnt + 1'b1;
                    end
                end

                default: begin
                    // Hold value for CHECK state
                end
            endcase
        end
    end

    //==========================================================================
    // Error Detection During Frame
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_er_detected <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    rx_er_detected <= 1'b0;
                end

                ST_PREAMBLE, ST_DATA: begin
                    if (gmii_rx_er) begin
                        rx_er_detected <= 1'b1;
                    end
                end

                default: begin
                    // Hold value
                end
            endcase
        end
    end

    //==========================================================================
    // First Data Byte Flag (for SOF)
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            first_data_byte <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    // Short preamble case - immediate SFD
                    if (rx_enable && gmii_rx_dv && (gmii_rxd == SFD_BYTE)) begin
                        first_data_byte <= 1'b1;
                    end else begin
                        first_data_byte <= 1'b0;
                    end
                end

                ST_PREAMBLE: begin
                    // Set when SFD detected and transitioning to ST_DATA
                    if (gmii_rx_dv && (gmii_rxd == SFD_BYTE)) begin
                        first_data_byte <= 1'b1;
                    end
                end

                ST_DATA: begin
                    if (first_data_byte && gmii_rx_dv) begin
                        first_data_byte <= 1'b0;
                    end
                end

                default: begin
                    // Hold value
                end
            endcase
        end
    end

    //==========================================================================
    // RX Data Pipeline
    // The *_latched signals are delayed one cycle so EOF can be generated on
    // the last byte. This block owns ONLY the *_latched signals and rx_eof;
    // rx_data / rx_data_valid / rx_sof are driven exclusively by the
    // "Latch Outputs" block below (single driver per register).
    // Data is output as received, FCS included; the upper layer strips FCS.
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data_latched       <= 8'h00;
            rx_data_valid_latched <= 1'b0;
            rx_sof_latched        <= 1'b0;
            rx_eof                <= 1'b0;
        end else begin
            // Default: clear the single-cycle EOF pulse
            rx_eof <= 1'b0;

            case (state)
                ST_DATA: begin
                    if (gmii_rx_dv) begin
                        rx_data_latched       <= gmii_rxd;
                        rx_data_valid_latched <= 1'b1;
                        rx_sof_latched        <= first_data_byte;
                    end else begin
                        // Signal end of frame on transition to CHECK
                        // (one cycle after last data)
                        rx_eof                <= 1'b1;
                        rx_data_valid_latched <= 1'b0;
                    end
                end

                default: begin
                    // No output; *_latched signals hold outside ST_DATA
                end
            endcase
        end
    end

    //==========================================================================
    // Latch Outputs (single driver for rx_data / rx_data_valid / rx_sof)
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data       <= 8'h00;
            rx_data_valid <= 1'b0;
            rx_sof        <= 1'b0;
        end else begin
            rx_data       <= rx_data_latched;
            rx_data_valid <= rx_data_valid_latched;
            rx_sof        <= rx_sof_latched;
        end
    end

    //==========================================================================
    // Frame Good/Bad Signals
    // Asserted on the DATA->CHECK transition, aligned with rx_eof
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_frame_good <= 1'b0;
            rx_frame_bad  <= 1'b0;
        end else begin
            if ((state == ST_DATA) && !gmii_rx_dv) begin
                rx_frame_bad  <= frame_failed;
                rx_frame_good <= !frame_failed;
            end
            if (state == ST_IDLE) begin
                // Clear flags when idle
                rx_frame_good <= 1'b0;
                rx_frame_bad  <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Status Output Generation
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_active    <= 1'b0;
            rx_frame_cnt <= 32'd0;
            rx_err_cnt   <= 32'd0;
        end else begin
            // RX active when receiving frame
            rx_active <= (state != ST_IDLE);

            // Increment good frame counter (COMMIT lasts exactly one cycle)
            if (state == ST_COMMIT) begin
                rx_frame_cnt <= rx_frame_cnt + 1'b1;
            end

            // Increment error counter (DISCARD lasts exactly one cycle)
            if (state == ST_DISCARD) begin
                rx_err_cnt <= rx_err_cnt + 1'b1;
            end
        end
    end

    //==========================================================================
    // Interrupt Pulse Generation
    //==========================================================================
    reg [2:0] state_d;  // Delayed state for edge detection

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_d <= ST_IDLE;
        end else begin
            state_d <= state;
        end
    end

    // Discard cause priority: RX_ER > runt > oversize > CRC.
    // Oversize raises no dedicated IRQ in Phase 0 (error counter only).
    wire irq_is_runt;
    wire irq_is_crc_err;

    assign irq_is_runt    = is_runt && !rx_er_detected;
    assign irq_is_crc_err = is_crc_err && !is_runt && !is_oversize && !rx_er_detected;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_rx_received <= 1'b0;
            int_rx_crc_err  <= 1'b0;
            int_rx_runt     <= 1'b0;
        end else begin
            // Generate pulses on state transitions
            int_rx_received <= (state == ST_COMMIT)  && (state_d != ST_COMMIT);
            int_rx_crc_err  <= (state == ST_DISCARD) && (state_d != ST_DISCARD) && irq_is_crc_err;
            int_rx_runt     <= (state == ST_DISCARD) && (state_d != ST_DISCARD) && irq_is_runt;
        end
    end

endmodule
