//==============================================================================
// File: dma_regs.v
// Description: DMA Register File (AXI4-Lite slave)
//
// Purpose:
//   Software interface of the DMA subsystem. Implements the register map
//   defined in dma_pkg.vh (offsets are byte addresses within an 8-bit CSR
//   window). Register-map compatible with the previous-generation DMA;
//   VERSION reads 0x0002_0000.
//
// AXI4-Lite behavior:
//   - AW and W are accepted independently (any order); the write applies
//     one cycle after both have arrived, then BVALID.
//   - Reads are two-cycle: address accept, then RVALID with muxed data.
//   - Writes to read-only registers are silently ignored (OKAY response).
//   - Unmapped reads return 0xDEAD_BEEF.
//
// Special registers:
//   - TX_CTRL/RX_CTRL bit[1] (RESET) is self-clearing: it produces a
//     1-cycle soft-reset pulse and always reads back 0.
//   - INT_STATUS is RW1C: writing 1s produces int_clear pulses; the
//     register itself lives in dma_irq and is only read back here.
//   - DESC_LO writes force bits [3:0] to 0 (16-byte ring alignment).
//
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`include "dma_pkg.vh"

module dma_regs #(
    parameter ADDR_WIDTH = 64,      // DMA/system address width (<= 64)
    parameter CSR_ADDR_W = 8        // CSR byte-address width
)(
    input  wire                    clk,
    input  wire                    rst_n,

    //--------------------------------------------------------------------------
    // AXI4-Lite slave
    //--------------------------------------------------------------------------
    input  wire                    s_axil_awvalid,
    output wire                    s_axil_awready,
    input  wire [CSR_ADDR_W-1:0]   s_axil_awaddr,
    input  wire                    s_axil_wvalid,
    output wire                    s_axil_wready,
    input  wire [31:0]             s_axil_wdata,
    input  wire [3:0]              s_axil_wstrb,
    output reg                     s_axil_bvalid,
    input  wire                    s_axil_bready,
    output wire [1:0]              s_axil_bresp,
    input  wire                    s_axil_arvalid,
    output wire                    s_axil_arready,
    input  wire [CSR_ADDR_W-1:0]   s_axil_araddr,
    output reg                     s_axil_rvalid,
    input  wire                    s_axil_rready,
    output reg  [31:0]             s_axil_rdata,
    output wire [1:0]              s_axil_rresp,

    //--------------------------------------------------------------------------
    // TX channel
    //--------------------------------------------------------------------------
    output reg                     tx_enable,
    output reg                     tx_soft_reset,   // 1-cycle pulse
    output reg                     tx_irq_en,
    input  wire                    tx_busy,
    input  wire                    tx_halted,
    input  wire                    tx_error,
    output wire [ADDR_WIDTH-1:0]   tx_ring_base,
    output reg  [15:0]             tx_ring_size,
    output reg  [15:0]             tx_head_ptr,     // SW produce pointer
    input  wire [15:0]             tx_tail_ptr,     // HW consume pointer
    input  wire [31:0]             tx_pkt_cnt,
    input  wire [31:0]             tx_byte_cnt,

    //--------------------------------------------------------------------------
    // RX channel
    //--------------------------------------------------------------------------
    output reg                     rx_enable,
    output reg                     rx_soft_reset,   // 1-cycle pulse
    output reg                     rx_irq_en,
    input  wire                    rx_busy,
    input  wire                    rx_halted,
    input  wire                    rx_error,
    output wire [ADDR_WIDTH-1:0]   rx_ring_base,
    output reg  [15:0]             rx_ring_size,
    input  wire [15:0]             rx_head_ptr,     // HW produce pointer
    output reg  [15:0]             rx_tail_ptr,     // SW reclaim pointer
    input  wire [31:0]             rx_pkt_cnt,
    input  wire [31:0]             rx_byte_cnt,
    input  wire [31:0]             rx_drop_cnt,

    //--------------------------------------------------------------------------
    // Interrupt block
    //--------------------------------------------------------------------------
    input  wire [4:0]              int_status,
    output wire [4:0]              int_clear,       // RW1C pulse
    output reg  [4:0]              int_mask,
    output reg  [15:0]             int_coal_cnt,
    output reg  [15:0]             int_coal_time
);

    //--------------------------------------------------------------------------
    // Ring base registers are kept 64-bit internally so the HI/LO split is
    // width-independent; the channel-facing outputs are sliced.
    //--------------------------------------------------------------------------
    reg [63:0] tx_ring_base_q;
    reg [63:0] rx_ring_base_q;

    assign tx_ring_base = tx_ring_base_q[ADDR_WIDTH-1:0];
    assign rx_ring_base = rx_ring_base_q[ADDR_WIDTH-1:0];

    //--------------------------------------------------------------------------
    // Write channel FSM
    //--------------------------------------------------------------------------
    localparam [1:0] WR_IDLE  = 2'd0,   // Collect AW and W (any order)
                     WR_APPLY = 2'd1,   // Commit the register write
                     WR_RESP  = 2'd2;   // BVALID until BREADY

    reg [1:0]            wr_state;
    reg                  aw_got;
    reg                  w_got;
    reg [CSR_ADDR_W-1:0] awaddr_q;
    reg [31:0]           wdata_q;
    reg [3:0]            wstrb_q;

    assign s_axil_awready = (wr_state == WR_IDLE) && !aw_got;
    assign s_axil_wready  = (wr_state == WR_IDLE) && !w_got;
    assign s_axil_bresp   = 2'b00;

    wire aw_hs = s_axil_awvalid && s_axil_awready;
    wire w_hs  = s_axil_wvalid  && s_axil_wready;

    wire wr_apply = (wr_state == WR_APPLY);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state       <= WR_IDLE;
            aw_got         <= 1'b0;
            w_got          <= 1'b0;
            awaddr_q       <= {CSR_ADDR_W{1'b0}};
            wdata_q        <= 32'd0;
            wstrb_q        <= 4'd0;
            s_axil_bvalid  <= 1'b0;
            tx_enable      <= 1'b0;
            tx_soft_reset  <= 1'b0;
            tx_irq_en      <= 1'b0;
            tx_ring_base_q <= 64'd0;
            tx_ring_size   <= 16'd0;
            tx_head_ptr    <= 16'd0;
            rx_enable      <= 1'b0;
            rx_soft_reset  <= 1'b0;
            rx_irq_en      <= 1'b0;
            rx_ring_base_q <= 64'd0;
            rx_ring_size   <= 16'd0;
            rx_tail_ptr    <= 16'd0;
            int_mask       <= 5'd0;
            int_coal_cnt   <= 16'd0;
            int_coal_time  <= 16'd0;
        end else begin
            // Self-clearing soft-reset pulses
            tx_soft_reset <= 1'b0;
            rx_soft_reset <= 1'b0;

            case (wr_state)
                //--------------------------------------------------------------
                WR_IDLE: begin
                    if (aw_hs) begin
                        awaddr_q <= s_axil_awaddr;
                        aw_got   <= 1'b1;
                    end
                    if (w_hs) begin
                        wdata_q <= s_axil_wdata;
                        wstrb_q <= s_axil_wstrb;
                        w_got   <= 1'b1;
                    end
                    if ((aw_got || aw_hs) && (w_got || w_hs)) begin
                        wr_state <= WR_APPLY;
                    end
                end

                //--------------------------------------------------------------
                WR_APPLY: begin
                    case (awaddr_q)
                        `DMA_TX_CTRL: begin
                            if (wstrb_q[0]) begin
                                tx_enable     <= wdata_q[`DMA_CTRL_ENABLE];
                                tx_soft_reset <= wdata_q[`DMA_CTRL_RESET];
                                tx_irq_en     <= wdata_q[`DMA_CTRL_IRQ_EN];
                            end
                        end
                        `DMA_TX_DESC_LO: begin
                            if (wstrb_q[0]) tx_ring_base_q[7:0]   <= {wdata_q[7:4], 4'b0000};
                            if (wstrb_q[1]) tx_ring_base_q[15:8]  <= wdata_q[15:8];
                            if (wstrb_q[2]) tx_ring_base_q[23:16] <= wdata_q[23:16];
                            if (wstrb_q[3]) tx_ring_base_q[31:24] <= wdata_q[31:24];
                        end
                        `DMA_TX_DESC_HI: begin
                            if (wstrb_q[0]) tx_ring_base_q[39:32] <= wdata_q[7:0];
                            if (wstrb_q[1]) tx_ring_base_q[47:40] <= wdata_q[15:8];
                            if (wstrb_q[2]) tx_ring_base_q[55:48] <= wdata_q[23:16];
                            if (wstrb_q[3]) tx_ring_base_q[63:56] <= wdata_q[31:24];
                        end
                        `DMA_TX_RING_SIZE: begin
                            if (wstrb_q[0]) tx_ring_size[7:0]  <= wdata_q[7:0];
                            if (wstrb_q[1]) tx_ring_size[15:8] <= wdata_q[15:8];
                        end
                        `DMA_TX_HEAD_PTR: begin
                            if (wstrb_q[0]) tx_head_ptr[7:0]  <= wdata_q[7:0];
                            if (wstrb_q[1]) tx_head_ptr[15:8] <= wdata_q[15:8];
                        end
                        `DMA_RX_CTRL: begin
                            if (wstrb_q[0]) begin
                                rx_enable     <= wdata_q[`DMA_CTRL_ENABLE];
                                rx_soft_reset <= wdata_q[`DMA_CTRL_RESET];
                                rx_irq_en     <= wdata_q[`DMA_CTRL_IRQ_EN];
                            end
                        end
                        `DMA_RX_DESC_LO: begin
                            if (wstrb_q[0]) rx_ring_base_q[7:0]   <= {wdata_q[7:4], 4'b0000};
                            if (wstrb_q[1]) rx_ring_base_q[15:8]  <= wdata_q[15:8];
                            if (wstrb_q[2]) rx_ring_base_q[23:16] <= wdata_q[23:16];
                            if (wstrb_q[3]) rx_ring_base_q[31:24] <= wdata_q[31:24];
                        end
                        `DMA_RX_DESC_HI: begin
                            if (wstrb_q[0]) rx_ring_base_q[39:32] <= wdata_q[7:0];
                            if (wstrb_q[1]) rx_ring_base_q[47:40] <= wdata_q[15:8];
                            if (wstrb_q[2]) rx_ring_base_q[55:48] <= wdata_q[23:16];
                            if (wstrb_q[3]) rx_ring_base_q[63:56] <= wdata_q[31:24];
                        end
                        `DMA_RX_RING_SIZE: begin
                            if (wstrb_q[0]) rx_ring_size[7:0]  <= wdata_q[7:0];
                            if (wstrb_q[1]) rx_ring_size[15:8] <= wdata_q[15:8];
                        end
                        `DMA_RX_TAIL_PTR: begin
                            if (wstrb_q[0]) rx_tail_ptr[7:0]  <= wdata_q[7:0];
                            if (wstrb_q[1]) rx_tail_ptr[15:8] <= wdata_q[15:8];
                        end
                        `DMA_INT_MASK: begin
                            if (wstrb_q[0]) int_mask <= wdata_q[4:0];
                        end
                        `DMA_INT_COALESCE: begin
                            if (wstrb_q[0]) int_coal_cnt[7:0]   <= wdata_q[7:0];
                            if (wstrb_q[1]) int_coal_cnt[15:8]  <= wdata_q[15:8];
                            if (wstrb_q[2]) int_coal_time[7:0]  <= wdata_q[23:16];
                            if (wstrb_q[3]) int_coal_time[15:8] <= wdata_q[31:24];
                        end
                        default: begin
                            // INT_STATUS handled via int_clear; RO/unmapped
                            // writes are ignored.
                        end
                    endcase
                    aw_got        <= 1'b0;
                    w_got         <= 1'b0;
                    s_axil_bvalid <= 1'b1;
                    wr_state      <= WR_RESP;
                end

                //--------------------------------------------------------------
                WR_RESP: begin
                    if (s_axil_bready) begin
                        s_axil_bvalid <= 1'b0;
                        wr_state      <= WR_IDLE;
                    end
                end

                //--------------------------------------------------------------
                default: begin
                    wr_state <= WR_IDLE;
                end
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // RW1C pulse for INT_STATUS (lives in dma_irq)
    //--------------------------------------------------------------------------
    assign int_clear = (wr_apply && (awaddr_q == `DMA_INT_STATUS)
                        && wstrb_q[0]) ? wdata_q[4:0] : 5'b00000;

    //--------------------------------------------------------------------------
    // Read channel FSM
    //--------------------------------------------------------------------------
    localparam RD_IDLE = 1'b0,          // Accept read address
               RD_DATA = 1'b1;          // RVALID until RREADY

    reg rd_state;

    assign s_axil_arready = (rd_state == RD_IDLE);
    assign s_axil_rresp   = 2'b00;

    reg [31:0] rdata_mux;
    always @(*) begin
        case (s_axil_araddr)
            `DMA_TX_CTRL:      rdata_mux = {29'd0, tx_irq_en, 1'b0, tx_enable};
            `DMA_TX_STATUS:    rdata_mux = {29'd0, tx_error, tx_halted, tx_busy};
            `DMA_TX_DESC_LO:   rdata_mux = tx_ring_base_q[31:0];
            `DMA_TX_DESC_HI:   rdata_mux = tx_ring_base_q[63:32];
            `DMA_TX_RING_SIZE: rdata_mux = {16'd0, tx_ring_size};
            `DMA_TX_HEAD_PTR:  rdata_mux = {16'd0, tx_head_ptr};
            `DMA_TX_TAIL_PTR:  rdata_mux = {16'd0, tx_tail_ptr};
            `DMA_TX_PKT_CNT:   rdata_mux = tx_pkt_cnt;
            `DMA_RX_CTRL:      rdata_mux = {29'd0, rx_irq_en, 1'b0, rx_enable};
            `DMA_RX_STATUS:    rdata_mux = {29'd0, rx_error, rx_halted, rx_busy};
            `DMA_RX_DESC_LO:   rdata_mux = rx_ring_base_q[31:0];
            `DMA_RX_DESC_HI:   rdata_mux = rx_ring_base_q[63:32];
            `DMA_RX_RING_SIZE: rdata_mux = {16'd0, rx_ring_size};
            `DMA_RX_HEAD_PTR:  rdata_mux = {16'd0, rx_head_ptr};
            `DMA_RX_TAIL_PTR:  rdata_mux = {16'd0, rx_tail_ptr};
            `DMA_RX_PKT_CNT:   rdata_mux = rx_pkt_cnt;
            `DMA_INT_STATUS:   rdata_mux = {27'd0, int_status};
            `DMA_INT_MASK:     rdata_mux = {27'd0, int_mask};
            `DMA_INT_COALESCE: rdata_mux = {int_coal_time, int_coal_cnt};
            `DMA_VERSION:      rdata_mux = `DMA_VERSION_VALUE;
            `DMA_RX_DROP_CNT:  rdata_mux = rx_drop_cnt;
            `DMA_TX_BYTE_CNT:  rdata_mux = tx_byte_cnt;
            `DMA_RX_BYTE_CNT:  rdata_mux = rx_byte_cnt;
            default:           rdata_mux = 32'hDEAD_BEEF;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state     <= RD_IDLE;
            s_axil_rvalid <= 1'b0;
            s_axil_rdata  <= 32'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (s_axil_arvalid) begin
                        s_axil_rdata  <= rdata_mux;
                        s_axil_rvalid <= 1'b1;
                        rd_state      <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (s_axil_rready) begin
                        s_axil_rvalid <= 1'b0;
                        rd_state      <= RD_IDLE;
                    end
                end

                default: begin
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end

endmodule
