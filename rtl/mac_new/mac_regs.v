//==============================================================================
// Module: mac_regs
// Description: AXI4-Lite slave register interface for Gigabit Ethernet MAC
//              (one function: register access)
//
// Features:
//   - AXI4-Lite slave interface (32-bit data, configurable address width)
//   - MAC address registers (48-bit, stored in two 32-bit registers)
//   - TX/RX enable control
//   - Interrupt status (W1C) and mask registers
//   - DECERR response for unmapped addresses (reads and writes)
//   - No side effects on read operations
//
// Register Map (byte addresses):
//   0x00: MAC_ADDR_LO   [31:0]  - MAC Address bits [31:0]  (RW)
//   0x04: MAC_ADDR_HI   [15:0]  - MAC Address bits [47:32] (RW)
//   0x08: CONTROL       [1:0]   - {rx_enable, tx_enable}   (RW)
//   0x0C: STATUS        [1:0]   - {rx_active, tx_active}   (RO)
//   0x10: INT_STATUS    [3:0]   - Interrupt status         (RW1C)
//   0x14: INT_MASK      [3:0]   - Interrupt mask           (RW)
//   0x18: TX_FRAME_CNT  [31:0]  - Transmitted frame count  (RO)
//   0x1C: RX_FRAME_CNT  [31:0]  - Received frame count     (RO)
//   0x20: RX_ERR_CNT    [31:0]  - RX error count           (RO)
//   0x24: VERSION       [31:0]  - IP Version (fixed)       (RO)
//
// Interrupt Bits:
//   [0] - TX frame complete
//   [1] - RX frame received
//   [2] - RX CRC error
//   [3] - RX runt frame
//
// Verification Hooks:
//   - Assertion: AXI handshake protocol compliance
//   - Assertion: Writes to RO registers have no side effects
//   - Assertion: INT_STATUS clears only written bits (write-1-to-clear)
//   - Assertion: DECERR returned for unmapped addresses
//   - Coverage: All registers accessed, interrupt scenarios
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_regs #(
    parameter ADDR_WIDTH = 8,           // AXI address width (minimum 8)
    parameter DATA_WIDTH = 32,          // AXI data width (fixed at 32)
    parameter VERSION    = 32'h0001_0000 // IP Version 1.0.0
) (
    //==========================================================================
    // Clock and Reset
    //==========================================================================
    input  wire                     clk,            // System clock
    input  wire                     rst_n,          // Active-low reset (async assert, sync deassert)

    //==========================================================================
    // AXI4-Lite Slave Interface
    //==========================================================================
    // Write Address Channel
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,

    // Write Response Channel
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    // Read Address Channel
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,

    // Read Data Channel
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    //==========================================================================
    // MAC Control Outputs (directly from registers)
    //==========================================================================
    output wire [47:0]              mac_addr,       // MAC address
    output wire                     tx_enable,      // TX path enable
    output wire                     rx_enable,      // RX path enable
    output wire [3:0]               int_mask,       // Interrupt mask

    //==========================================================================
    // MAC Status Inputs (directly to registers)
    //==========================================================================
    input  wire                     tx_active,      // TX currently active
    input  wire                     rx_active,      // RX currently active
    input  wire [31:0]              tx_frame_cnt,   // TX frame counter
    input  wire [31:0]              rx_frame_cnt,   // RX frame counter
    input  wire [31:0]              rx_err_cnt,     // RX error counter

    //==========================================================================
    // Interrupt Inputs (single-cycle pulses in clk domain)
    //==========================================================================
    input  wire                     int_tx_complete,// TX frame complete pulse
    input  wire                     int_rx_received,// RX frame received pulse
    input  wire                     int_rx_crc_err, // RX CRC error pulse
    input  wire                     int_rx_runt,    // RX runt frame pulse

    //==========================================================================
    // Interrupt Output
    //==========================================================================
    output wire                     irq             // Masked interrupt output
);

    //==========================================================================
    // Local Parameters - Register Addresses (word-aligned)
    //==========================================================================
    localparam ADDR_MAC_LO      = 8'h00;
    localparam ADDR_MAC_HI      = 8'h04;
    localparam ADDR_CONTROL     = 8'h08;
    localparam ADDR_STATUS      = 8'h0C;
    localparam ADDR_INT_STATUS  = 8'h10;
    localparam ADDR_INT_MASK    = 8'h14;
    localparam ADDR_TX_FRAME    = 8'h18;
    localparam ADDR_RX_FRAME    = 8'h1C;
    localparam ADDR_RX_ERR      = 8'h20;
    localparam ADDR_VERSION     = 8'h24;

    //==========================================================================
    // AXI Response Codes
    //==========================================================================
    localparam RESP_OKAY        = 2'b00;
    localparam RESP_DECERR      = 2'b11;  // Decode error for unmapped address

    //==========================================================================
    // Register Storage
    //==========================================================================
    reg  [31:0] reg_mac_lo;         // MAC address [31:0]
    reg  [15:0] reg_mac_hi;         // MAC address [47:32]
    reg         reg_tx_enable;      // TX enable
    reg         reg_rx_enable;      // RX enable
    reg  [3:0]  reg_int_status;     // Interrupt status (RW1C)
    reg  [3:0]  reg_int_mask;       // Interrupt mask

    //==========================================================================
    // AXI Write State Machine
    //==========================================================================
    localparam WR_IDLE  = 1'b0;
    localparam WR_RESP  = 1'b1;

    reg wr_state;
    reg [ADDR_WIDTH-1:0] wr_addr_latched;
    reg [DATA_WIDTH-1:0] wr_data_latched;
    reg [DATA_WIDTH/8-1:0] wr_strb_latched;
    reg wr_addr_valid;
    reg wr_data_valid;

    //==========================================================================
    // AXI Read State Machine
    //==========================================================================
    localparam RD_IDLE  = 1'b0;
    localparam RD_DATA  = 1'b1;

    reg rd_state;
    reg [ADDR_WIDTH-1:0] rd_addr_latched;

    //==========================================================================
    // Interrupt Capture Logic
    // Verification Note: each interrupt input is a single-cycle pulse
    //==========================================================================
    wire [3:0] int_capture;
    assign int_capture = {int_rx_runt, int_rx_crc_err, int_rx_received, int_tx_complete};

    //==========================================================================
    // Output Assignments
    //==========================================================================
    assign mac_addr  = {reg_mac_hi, reg_mac_lo};
    assign tx_enable = reg_tx_enable;
    assign rx_enable = reg_rx_enable;
    assign int_mask  = reg_int_mask;

    // Masked interrupt output - asserted when any unmasked interrupt is pending
    assign irq = |(reg_int_status & reg_int_mask);

    //==========================================================================
    // Write Address Decode (shared by write logic and response generation)
    //==========================================================================
    wire wr_en;
    wire [DATA_WIDTH-1:0] wr_data_eff;
    wire [DATA_WIDTH/8-1:0] wr_strb_eff;
    wire [ADDR_WIDTH-1:0] wr_addr_eff;
    wire wr_addr_mapped;

    // Write enable when we have both address and data in IDLE state
    assign wr_en = (wr_state == WR_IDLE) &&
                   (s_axi_awvalid || wr_addr_valid) &&
                   (s_axi_wvalid || wr_data_valid);

    // Use current signals if valid, otherwise use latched values
    assign wr_addr_eff = (s_axi_awvalid) ? s_axi_awaddr : wr_addr_latched;
    assign wr_data_eff = (s_axi_wvalid) ? s_axi_wdata : wr_data_latched;
    assign wr_strb_eff = (s_axi_wvalid) ? s_axi_wstrb : wr_strb_latched;

    // Writable-register decode: RO registers accept (and ignore) writes with
    // OKAY; only addresses outside the register map return DECERR.
    assign wr_addr_mapped = (wr_addr_eff[7:0] == ADDR_MAC_LO)     ||
                            (wr_addr_eff[7:0] == ADDR_MAC_HI)     ||
                            (wr_addr_eff[7:0] == ADDR_CONTROL)    ||
                            (wr_addr_eff[7:0] == ADDR_STATUS)     ||
                            (wr_addr_eff[7:0] == ADDR_INT_STATUS) ||
                            (wr_addr_eff[7:0] == ADDR_INT_MASK)   ||
                            (wr_addr_eff[7:0] == ADDR_TX_FRAME)   ||
                            (wr_addr_eff[7:0] == ADDR_RX_FRAME)   ||
                            (wr_addr_eff[7:0] == ADDR_RX_ERR)     ||
                            (wr_addr_eff[7:0] == ADDR_VERSION);

    //==========================================================================
    // AXI Write State Machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state        <= WR_IDLE;
            wr_addr_latched <= {ADDR_WIDTH{1'b0}};
            wr_data_latched <= {DATA_WIDTH{1'b0}};
            wr_strb_latched <= {DATA_WIDTH/8{1'b0}};
            wr_addr_valid   <= 1'b0;
            wr_data_valid   <= 1'b0;
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= RESP_OKAY;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    // Clear response
                    s_axi_bvalid  <= 1'b0;
                    wr_addr_valid <= 1'b0;
                    wr_data_valid <= 1'b0;

                    // Assert ready for both channels
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;

                    // Capture address if present
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr_latched <= s_axi_awaddr;
                        wr_addr_valid   <= 1'b1;
                    end

                    // Capture data if present
                    if (s_axi_wvalid && s_axi_wready) begin
                        wr_data_latched <= s_axi_wdata;
                        wr_strb_latched <= s_axi_wstrb;
                        wr_data_valid   <= 1'b1;
                    end

                    // Transition when both are available; latch the response
                    // code for this transaction (OKAY or DECERR)
                    if (((s_axi_awvalid && s_axi_awready) || wr_addr_valid)) begin
                        if ((s_axi_wvalid && s_axi_wready) || wr_data_valid) begin
                            s_axi_awready <= 1'b0;
                            s_axi_wready  <= 1'b0;
                            wr_addr_valid <= 1'b0;
                            wr_data_valid <= 1'b0;
                            s_axi_bresp   <= wr_addr_mapped ? RESP_OKAY : RESP_DECERR;
                            wr_state      <= WR_RESP;
                        end
                    end
                end

                WR_RESP: begin
                    // Generate write response (bresp latched on entry)
                    if (!s_axi_bvalid) begin
                        s_axi_bvalid <= 1'b1;
                    end

                    // Wait for response acceptance
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: begin
                    wr_state <= WR_IDLE;
                end
            endcase
        end
    end

    //==========================================================================
    // Register Write Logic
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all writeable registers
            reg_mac_lo     <= 32'h0000_0000;
            reg_mac_hi     <= 16'h0000;
            reg_tx_enable  <= 1'b0;
            reg_rx_enable  <= 1'b0;
            reg_int_status <= 4'b0000;
            reg_int_mask   <= 4'b0000;
        end else begin
            //------------------------------------------------------------------
            // Capture incoming interrupts (sticky bits)
            //------------------------------------------------------------------
            reg_int_status <= reg_int_status | int_capture;

            //------------------------------------------------------------------
            // Handle register writes (wr_en is a single-cycle event; the FSM
            // leaves WR_IDLE on the same edge, so no double write can occur)
            //------------------------------------------------------------------
            if (wr_en) begin
                case (wr_addr_eff[7:0])
                    ADDR_MAC_LO: begin
                        if (wr_strb_eff[0]) reg_mac_lo[7:0]   <= wr_data_eff[7:0];
                        if (wr_strb_eff[1]) reg_mac_lo[15:8]  <= wr_data_eff[15:8];
                        if (wr_strb_eff[2]) reg_mac_lo[23:16] <= wr_data_eff[23:16];
                        if (wr_strb_eff[3]) reg_mac_lo[31:24] <= wr_data_eff[31:24];
                    end

                    ADDR_MAC_HI: begin
                        if (wr_strb_eff[0]) reg_mac_hi[7:0]  <= wr_data_eff[7:0];
                        if (wr_strb_eff[1]) reg_mac_hi[15:8] <= wr_data_eff[15:8];
                    end

                    ADDR_CONTROL: begin
                        if (wr_strb_eff[0]) begin
                            reg_tx_enable <= wr_data_eff[0];
                            reg_rx_enable <= wr_data_eff[1];
                        end
                    end

                    ADDR_INT_STATUS: begin
                        // Write-1-to-Clear with simultaneous interrupt capture:
                        // a pulse arriving in the same cycle is not lost
                        if (wr_strb_eff[0]) begin
                            reg_int_status <= (reg_int_status | int_capture) & ~wr_data_eff[3:0];
                        end
                    end

                    ADDR_INT_MASK: begin
                        if (wr_strb_eff[0]) begin
                            reg_int_mask <= wr_data_eff[3:0];
                        end
                    end

                    // STATUS, counters, VERSION are read-only:
                    // writes are silently ignored - no side effects
                    default: begin
                        // Read-only or unmapped - no register change
                        // (unmapped addresses get DECERR via s_axi_bresp)
                    end
                endcase
            end
        end
    end

    //==========================================================================
    // AXI Read State Machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state        <= RD_IDLE;
            rd_addr_latched <= {ADDR_WIDTH{1'b0}};
            s_axi_arready   <= 1'b0;
            s_axi_rvalid    <= 1'b0;
            s_axi_rdata     <= {DATA_WIDTH{1'b0}};
            s_axi_rresp     <= RESP_OKAY;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready <= 1'b1;
                    s_axi_rvalid  <= 1'b0;

                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_addr_latched <= s_axi_araddr;
                        s_axi_arready   <= 1'b0;
                        rd_state        <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    // Generate read response
                    if (!s_axi_rvalid) begin
                        s_axi_rvalid <= 1'b1;
                        s_axi_rresp  <= RESP_OKAY;

                        // Decode read address and return data
                        case (rd_addr_latched[7:0])
                            ADDR_MAC_LO:     s_axi_rdata <= reg_mac_lo;
                            ADDR_MAC_HI:     s_axi_rdata <= {16'h0000, reg_mac_hi};
                            ADDR_CONTROL:    s_axi_rdata <= {30'b0, reg_rx_enable, reg_tx_enable};
                            ADDR_STATUS:     s_axi_rdata <= {30'b0, rx_active, tx_active};
                            ADDR_INT_STATUS: s_axi_rdata <= {28'b0, reg_int_status};
                            ADDR_INT_MASK:   s_axi_rdata <= {28'b0, reg_int_mask};
                            ADDR_TX_FRAME:   s_axi_rdata <= tx_frame_cnt;
                            ADDR_RX_FRAME:   s_axi_rdata <= rx_frame_cnt;
                            ADDR_RX_ERR:     s_axi_rdata <= rx_err_cnt;
                            ADDR_VERSION:    s_axi_rdata <= VERSION;
                            default: begin
                                // Unmapped address: decode error
                                s_axi_rdata <= 32'h0000_0000;
                                s_axi_rresp <= RESP_DECERR;
                            end
                        endcase
                    end

                    // Wait for response acceptance
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end

                default: begin
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end

endmodule
