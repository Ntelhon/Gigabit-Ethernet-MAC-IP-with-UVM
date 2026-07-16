//==============================================================================
// File: dma_irq.v
// Description: DMA Interrupt Controller (latch + mask + coalescing)
//
// Purpose:
//   Collects the five event pulses from the descriptor engines, latches
//   them into INT_STATUS (RW1C via int_clear), applies INT_MASK and drives
//   the single dma_irq output.
//
// Interrupt coalescing (DONE interrupts only; errors always fire at once):
//   A small FSM accumulates completion events and asserts the interrupt
//   when EITHER
//     - the event count reaches coal_cnt_thresh, OR
//     - coal_time_thresh prescaled ticks elapse since the first pending
//       event (tick = COAL_PRESCALE clk cycles).
//   A threshold value of 0 disables that dimension of coalescing (the
//   comparison is immediately satisfied), so 0/0 = fire immediately.
//
// Bit map (per dma_pkg.vh):
//   [0] TX_DONE  [1] TX_ERR  [2] RX_DONE  [3] RX_ERR  [4] DESC_ERR
//
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`include "dma_pkg.vh"

module dma_irq #(
    parameter N_INT         = 5,        // Interrupt source count
    parameter COAL_TIMER_W  = 16,       // Coalescing tick counter width
    parameter COAL_PRESCALE = 1000      // clk cycles per coalescing tick
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Event pulses (1 cycle each)
    input  wire                    ev_tx_done,
    input  wire                    ev_tx_err,
    input  wire                    ev_rx_done,
    input  wire                    ev_rx_err,
    input  wire                    ev_desc_err,

    // CSR interface
    input  wire [N_INT-1:0]        int_clear,       // RW1C pulse from regs
    input  wire [N_INT-1:0]        int_mask,        // 1 = interrupt enabled
    input  wire [COAL_TIMER_W-1:0] coal_cnt_thresh, // Packet-count threshold
    input  wire [COAL_TIMER_W-1:0] coal_time_thresh,// Tick threshold

    // Outputs
    output reg  [N_INT-1:0]        int_status,      // Latched, maskable
    output reg                     dma_irq          // Level interrupt
);

    localparam PRESC_W = $clog2(COAL_PRESCALE + 1);

    // Bit-position masks
    localparam [N_INT-1:0] DONE_BITS = 5'b00101;    // TX_DONE | RX_DONE
    localparam [N_INT-1:0] ERR_BITS  = 5'b11010;    // All error sources

    //--------------------------------------------------------------------------
    // Coalescing FSM states
    //--------------------------------------------------------------------------
    localparam [1:0] COAL_IDLE  = 2'd0,     // No completion pending
                     COAL_ACCUM = 2'd1,     // Counting events / time
                     COAL_FIRE  = 2'd2;     // Gate open until SW clears

    //--------------------------------------------------------------------------
    // Event vector, {desc_err, rx_err, rx_done, tx_err, tx_done}
    //--------------------------------------------------------------------------
    wire [N_INT-1:0] ev = {ev_desc_err, ev_rx_err, ev_rx_done,
                           ev_tx_err, ev_tx_done};

    //--------------------------------------------------------------------------
    // Status latch: set wins over a same-cycle clear
    //--------------------------------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_status <= {N_INT{1'b0}};
        end else begin
            for (i = 0; i < N_INT; i = i + 1) begin
                if (ev[i]) begin
                    int_status[i] <= 1'b1;
                end else if (int_clear[i]) begin
                    int_status[i] <= 1'b0;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Coalescing engine
    //--------------------------------------------------------------------------
    reg [1:0]              coal_state;
    reg [COAL_TIMER_W-1:0] coal_cnt;        // Completion events accumulated
    reg [COAL_TIMER_W-1:0] coal_ticks;      // Prescaled time elapsed
    reg [PRESC_W-1:0]      prescale_cnt;

    wire done_ev      = ev_tx_done | ev_rx_done;
    wire done_pending = |(int_status & int_mask & DONE_BITS);
    wire coal_hit     = (coal_cnt   >= coal_cnt_thresh) ||
                        (coal_ticks >= coal_time_thresh);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coal_state   <= COAL_IDLE;
            coal_cnt     <= {COAL_TIMER_W{1'b0}};
            coal_ticks   <= {COAL_TIMER_W{1'b0}};
            prescale_cnt <= {PRESC_W{1'b0}};
        end else begin
            case (coal_state)
                COAL_IDLE: begin
                    coal_cnt     <= {COAL_TIMER_W{1'b0}};
                    coal_ticks   <= {COAL_TIMER_W{1'b0}};
                    prescale_cnt <= {PRESC_W{1'b0}};
                    if (done_ev) begin
                        coal_cnt   <= {{(COAL_TIMER_W-1){1'b0}}, 1'b1};
                        coal_state <= COAL_ACCUM;
                    end
                end

                COAL_ACCUM: begin
                    // Event counting
                    if (done_ev) begin
                        coal_cnt <= coal_cnt + {{(COAL_TIMER_W-1){1'b0}}, 1'b1};
                    end
                    // Prescaled time base
                    if (prescale_cnt == COAL_PRESCALE[PRESC_W-1:0] - {{(PRESC_W-1){1'b0}}, 1'b1}) begin
                        prescale_cnt <= {PRESC_W{1'b0}};
                        coal_ticks   <= coal_ticks + {{(COAL_TIMER_W-1){1'b0}}, 1'b1};
                    end else begin
                        prescale_cnt <= prescale_cnt + {{(PRESC_W-1){1'b0}}, 1'b1};
                    end
                    // Threshold reached (0-thresholds satisfy immediately)
                    if (coal_hit) begin
                        coal_state <= COAL_FIRE;
                    end
                end

                COAL_FIRE: begin
                    // Hold the gate open until SW clears the done statuses
                    if (!done_pending) begin
                        coal_state <= COAL_IDLE;
                    end
                end

                default: begin
                    coal_state <= COAL_IDLE;
                end
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Interrupt output (registered):
    //   errors bypass coalescing; completions pass in COAL_FIRE only
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_irq <= 1'b0;
        end else begin
            dma_irq <= (|(int_status & int_mask & ERR_BITS)) |
                       ((coal_state == COAL_FIRE) && done_pending);
        end
    end

endmodule
