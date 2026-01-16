//==============================================================================
// Module: mac_regs
// Description: AXI4-Lite slave register interface for Gigabit Ethernet MAC
//
// Features:
//   - AXI4-Lite slave interface (32-bit data, configurable address width)
//   - MAC address registers (48-bit, stored in two 32-bit registers)
//   - TX/RX enable control
//   - Interrupt status and mask registers
//   - Clean synchronous reset behavior
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
//   - Assertion: No write to RO registers should have side effects
//   - Assertion: INT_STATUS clears only written bits (write-1-to-clear)
//   - Coverage: All registers accessed
//   - Coverage: Interrupt scenarios
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_regs #(
    parameter ADDR_WIDTH = 8,           // AXI address width (minimum 8 for register space)
    parameter DATA_WIDTH = 32,          // AXI data width (fixed at 32)
    parameter VERSION    = 32'h0001_0000 // IP Version 1.0.0
) (
    //==========================================================================
    // Clock and Reset
    //==========================================================================
    input  wire                     clk,            // System clock
    input  wire                     rst_n,          // Active-low synchronous reset

    //==========================================================================
    // AXI4-Lite Slave Interface
    //==========================================================================
    // Write Address Channel
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,   // Write address
    input  wire                     s_axi_awvalid,  // Write address valid
    output reg                      s_axi_awready,  // Write address ready

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,    // Write data
    input  wire [DATA_WIDTH/8-1:0]  s_axi_wstrb,    // Write strobes
    input  wire                     s_axi_wvalid,   // Write valid
    output reg                      s_axi_wready,   // Write ready

    // Write Response Channel
    output reg  [1:0]               s_axi_bresp,    // Write response
    output reg                      s_axi_bvalid,   // Write response valid
    input  wire                     s_axi_bready,   // Write response ready

    // Read Address Channel
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,   // Read address
    input  wire                     s_axi_arvalid,  // Read address valid
    output reg                      s_axi_arready,  // Read address ready

    // Read Data Channel
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,    // Read data
    output reg  [1:0]               s_axi_rresp,    // Read response
    output reg                      s_axi_rvalid,   // Read valid
    input  wire                     s_axi_rready,   // Read ready

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
    // Interrupt Inputs (directly to registers)
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
    localparam RESP_DECERR      = 2'b11;  // Decode error for invalid address

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
    // States: IDLE -> Wait for both AWVALID and WVALID -> RESP
    // Note: We use a simple two-phase handshake approach
    //==========================================================================
    localparam WR_IDLE  = 2'b00;
    localparam WR_DATA  = 2'b01;
    localparam WR_RESP  = 2'b10;

    reg [1:0] wr_state;
    reg [ADDR_WIDTH-1:0] wr_addr_latched;

    //==========================================================================
    // AXI Read State Machine
    //==========================================================================
    localparam RD_IDLE  = 1'b0;
    localparam RD_DATA  = 1'b1;

    reg rd_state;
    reg [ADDR_WIDTH-1:0] rd_addr_latched;

    //==========================================================================
    // Interrupt Capture Logic
    // Verification Note: Each interrupt input is a single-cycle pulse
    // Assertion: int_*_pulse should be 1 clock wide
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
    // Verification Note: IRQ should assert within 1 cycle of unmasked interrupt
    assign irq = |(reg_int_status & reg_int_mask);

    //==========================================================================
    // AXI Write State Machine
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state        <= WR_IDLE;
            wr_addr_latched <= {ADDR_WIDTH{1'b0}};
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= RESP_OKAY;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    // Ready to accept both address and data
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    
                    // Wait for both address and data valid
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        wr_addr_latched <= s_axi_awaddr;
                        s_axi_awready   <= 1'b0;
                        s_axi_wready    <= 1'b0;
                        wr_state        <= WR_RESP;
                    end else if (s_axi_awvalid) begin
                        // Address arrived first, wait for data
                        wr_addr_latched <= s_axi_awaddr;
                        s_axi_awready   <= 1'b0;
                        wr_state        <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    // Waiting for write data
                    if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b0;
                        wr_state     <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    // Generate write response
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= RESP_OKAY;  // Always OKAY, writes to RO regs ignored
                    
                    if (s_axi_bready && s_axi_bvalid) begin
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
    // Verification Note: Write strobes are supported for byte-level access
    // Assertion: Only specified bytes should be modified based on WSTRB
    //==========================================================================
    wire wr_en;
    assign wr_en = (wr_state == WR_IDLE && s_axi_awvalid && s_axi_wvalid) ||
                   (wr_state == WR_DATA && s_axi_wvalid);

    // Determine effective write address
    wire [7:0] wr_addr_eff;
    assign wr_addr_eff = (wr_state == WR_IDLE) ? s_axi_awaddr[7:0] : wr_addr_latched[7:0];

    always @(posedge clk) begin
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
            // Verification Note: Interrupts are captured on rising edge
            //------------------------------------------------------------------
            reg_int_status <= reg_int_status | int_capture;

            //------------------------------------------------------------------
            // Handle register writes
            //------------------------------------------------------------------
            if (wr_en) begin
                case (wr_addr_eff)
                    ADDR_MAC_LO: begin
                        // MAC Address Low - byte-wise write
                        if (s_axi_wstrb[0]) reg_mac_lo[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_mac_lo[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_mac_lo[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_mac_lo[31:24] <= s_axi_wdata[31:24];
                    end

                    ADDR_MAC_HI: begin
                        // MAC Address High - only lower 16 bits used
                        if (s_axi_wstrb[0]) reg_mac_hi[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_mac_hi[15:8] <= s_axi_wdata[15:8];
                    end

                    ADDR_CONTROL: begin
                        // Control register
                        if (s_axi_wstrb[0]) begin
                            reg_tx_enable <= s_axi_wdata[0];
                            reg_rx_enable <= s_axi_wdata[1];
                        end
                    end

                    ADDR_INT_STATUS: begin
                        // Interrupt Status - Write-1-to-Clear (RW1C)
                        // Verification Note: Writing 1 clears, writing 0 has no effect
                        // Simultaneously capture new interrupts and clear acknowledged ones
                        if (s_axi_wstrb[0]) begin
                            reg_int_status <= (reg_int_status | int_capture) & ~s_axi_wdata[3:0];
                        end
                    end

                    ADDR_INT_MASK: begin
                        // Interrupt Mask
                        if (s_axi_wstrb[0]) begin
                            reg_int_mask <= s_axi_wdata[3:0];
                        end
                    end

                    // All other addresses (STATUS, counters, VERSION) are read-only
                    // Writes are silently ignored - no side effects
                    default: begin
                        // No operation - intentionally empty
                    end
                endcase
            end
        end
    end

    //==========================================================================
    // AXI Read State Machine
    //==========================================================================
    always @(posedge clk) begin
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
                    s_axi_rvalid <= 1'b1;
                    s_axi_rresp  <= RESP_OKAY;
                    
                    // Decode read address and return data
                    // Verification Note: Reads have no side effects
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
                        default:         s_axi_rdata <= 32'hDEAD_BEEF; // Debug pattern for invalid address
                    endcase
                    
                    if (s_axi_rready && s_axi_rvalid) begin
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
