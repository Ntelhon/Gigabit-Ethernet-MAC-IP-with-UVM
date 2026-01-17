//==============================================================================
// Module: eth_regs
// Description: Unified AXI4-Lite slave register interface for Ethernet Controller
//
// Features:
//   - Single AXI4-Lite slave interface for both MAC and DMA
//   - MAC registers (0x000-0x0FF)
//   - DMA registers (0x200-0x2FF) - optional via DMA_ENABLE parameter
//   - Separate interrupt outputs for MAC and DMA
//   - Clean synchronous reset behavior
//   - No side effects on read operations
//
// Register Map (byte addresses):
//   MAC Registers (0x000-0x0FF):
//     0x000: MAC_ADDR_LO     [31:0]  - MAC Address bits [31:0]  (RW)
//     0x004: MAC_ADDR_HI     [15:0]  - MAC Address bits [47:32] (RW)
//     0x008: MAC_CONTROL     [1:0]   - {rx_enable, tx_enable}   (RW)
//     0x00C: MAC_STATUS      [1:0]   - {rx_active, tx_active}   (RO)
//     0x010: MAC_INT_STATUS  [3:0]   - MAC Interrupt status     (RW1C)
//     0x014: MAC_INT_MASK    [3:0]   - MAC Interrupt mask       (RW)
//     0x018: MAC_TX_FRAME_CNT[31:0]  - Transmitted frame count  (RO)
//     0x01C: MAC_RX_FRAME_CNT[31:0]  - Received frame count     (RO)
//     0x020: MAC_RX_ERR_CNT  [31:0]  - RX error count           (RO)
//     0x024: MAC_VERSION     [31:0]  - MAC Version (fixed)      (RO)
//
//   DMA Registers (0x200-0x2FF) - only if DMA_ENABLE=1:
//     0x200: DMA_CONTROL         [2:0]   - {reset, rx_en, tx_en}    (RW)
//     0x204: DMA_STATUS          [1:0]   - {rx_busy, tx_busy}       (RO)
//     0x208: TX_DESC_BASE_LO     [31:0]  - TX descriptor base [31:0](RW)
//     0x20C: TX_DESC_BASE_HI     [31:0]  - TX descriptor base [63:32](RW)
//     0x210: TX_DESC_RING_SIZE   [7:0]   - Log2(TX ring size)       (RW)
//     0x214: RX_DESC_BASE_LO     [31:0]  - RX descriptor base [31:0](RW)
//     0x218: RX_DESC_BASE_HI     [31:0]  - RX descriptor base [63:32](RW)
//     0x21C: RX_DESC_RING_SIZE   [7:0]   - Log2(RX ring size)       (RW)
//     0x220: DMA_INT_STATUS      [3:0]   - DMA Interrupt status     (RW1C)
//     0x224: DMA_INT_MASK        [3:0]   - DMA Interrupt mask       (RW)
//     0x228: DMA_TX_PKT_COUNT    [31:0]  - TX packet count          (RO)
//     0x22C: DMA_RX_PKT_COUNT    [31:0]  - RX packet count          (RO)
//     0x230: DMA_TX_ERR_COUNT    [31:0]  - TX error count           (RO)
//     0x234: DMA_RX_ERR_COUNT    [31:0]  - RX error count           (RO)
//     0x238: DMA_VERSION         [31:0]  - DMA Version (fixed)      (RO)
//
// MAC Interrupt Bits:
//   [0] - TX frame complete
//   [1] - RX frame received
//   [2] - RX CRC error
//   [3] - RX runt frame
//
// DMA Interrupt Bits:
//   [0] - TX complete
//   [1] - RX complete
//   [2] - TX error
//   [3] - RX error
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_regs #(
    parameter ADDR_WIDTH     = 10,           // AXI address width (min 10 for DMA space)
    parameter DATA_WIDTH     = 32,           // AXI data width (fixed at 32)
    parameter DMA_ENABLE     = 1,            // 1=DMA registers present, 0=MAC only
    parameter DESC_ADDR_WIDTH= 32,           // Descriptor address width (32 or 64)
    parameter MAC_VERSION    = 32'h0001_0000,// MAC IP Version 1.0.0
    parameter DMA_VERSION    = 32'h0001_0000 // DMA IP Version 1.0.0
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
    // MAC Control Outputs
    //==========================================================================
    output wire [47:0]              mac_addr,       // MAC address
    output wire                     mac_tx_enable,  // MAC TX enable
    output wire                     mac_rx_enable,  // MAC RX enable

    //==========================================================================
    // MAC Status Inputs
    //==========================================================================
    input  wire                     mac_tx_active,  // MAC TX active
    input  wire                     mac_rx_active,  // MAC RX active
    input  wire [31:0]              mac_tx_frame_cnt, // TX frame count
    input  wire [31:0]              mac_rx_frame_cnt, // RX frame count
    input  wire [31:0]              mac_rx_err_cnt,   // RX error count

    //==========================================================================
    // MAC Interrupt Inputs
    //==========================================================================
    input  wire                     mac_int_tx_complete, // TX complete pulse
    input  wire                     mac_int_rx_received, // RX received pulse
    input  wire                     mac_int_rx_crc_err,  // RX CRC error pulse
    input  wire                     mac_int_rx_runt,     // RX runt pulse

    //==========================================================================
    // MAC Interrupt Output
    //==========================================================================
    output wire                     mac_irq,        // MAC interrupt output

    //==========================================================================
    // DMA Control Outputs (only if DMA_ENABLE=1)
    //==========================================================================
    output wire                     dma_tx_enable,  // DMA TX enable
    output wire                     dma_rx_enable,  // DMA RX enable
    output wire                     dma_reset,      // DMA reset
    output wire [DESC_ADDR_WIDTH-1:0] tx_desc_base, // TX descriptor base
    output wire [7:0]               tx_ring_size,   // TX ring size
    output wire [DESC_ADDR_WIDTH-1:0] rx_desc_base, // RX descriptor base
    output wire [7:0]               rx_ring_size,   // RX ring size

    //==========================================================================
    // DMA Status Inputs (only if DMA_ENABLE=1)
    //==========================================================================
    input  wire                     dma_tx_busy,    // DMA TX busy
    input  wire                     dma_rx_busy,    // DMA RX busy
    input  wire [31:0]              dma_tx_pkt_cnt, // TX packet count
    input  wire [31:0]              dma_rx_pkt_cnt, // RX packet count
    input  wire [31:0]              dma_tx_err_cnt, // TX error count
    input  wire [31:0]              dma_rx_err_cnt, // RX error count

    //==========================================================================
    // DMA Interrupt Inputs (only if DMA_ENABLE=1)
    //==========================================================================
    input  wire                     dma_int_tx_complete, // TX complete pulse
    input  wire                     dma_int_rx_complete, // RX complete pulse
    input  wire                     dma_int_tx_error,    // TX error pulse
    input  wire                     dma_int_rx_error,    // RX error pulse

    //==========================================================================
    // DMA Interrupt Output
    //==========================================================================
    output wire                     dma_irq         // DMA interrupt output
);

    //==========================================================================
    // Local Parameters - Register Addresses (byte-aligned)
    //==========================================================================
    // MAC Registers
    localparam ADDR_MAC_LO           = 10'h000;
    localparam ADDR_MAC_HI           = 10'h004;
    localparam ADDR_MAC_CONTROL      = 10'h008;
    localparam ADDR_MAC_STATUS       = 10'h00C;
    localparam ADDR_MAC_INT_STATUS   = 10'h010;
    localparam ADDR_MAC_INT_MASK     = 10'h014;
    localparam ADDR_MAC_TX_FRAME     = 10'h018;
    localparam ADDR_MAC_RX_FRAME     = 10'h01C;
    localparam ADDR_MAC_RX_ERR       = 10'h020;
    localparam ADDR_MAC_VERSION      = 10'h024;

    // DMA Registers (base = 0x200)
    localparam ADDR_DMA_CONTROL      = 10'h200;
    localparam ADDR_DMA_STATUS       = 10'h204;
    localparam ADDR_TX_DESC_BASE_LO  = 10'h208;
    localparam ADDR_TX_DESC_BASE_HI  = 10'h20C;
    localparam ADDR_TX_RING_SIZE     = 10'h210;
    localparam ADDR_RX_DESC_BASE_LO  = 10'h214;
    localparam ADDR_RX_DESC_BASE_HI  = 10'h218;
    localparam ADDR_RX_RING_SIZE     = 10'h21C;
    localparam ADDR_DMA_INT_STATUS   = 10'h220;
    localparam ADDR_DMA_INT_MASK     = 10'h224;
    localparam ADDR_DMA_TX_PKT       = 10'h228;
    localparam ADDR_DMA_RX_PKT       = 10'h22C;
    localparam ADDR_DMA_TX_ERR       = 10'h230;
    localparam ADDR_DMA_RX_ERR       = 10'h234;
    localparam ADDR_DMA_VERSION      = 10'h238;

    //==========================================================================
    // AXI Response Codes
    //==========================================================================
    localparam RESP_OKAY        = 2'b00;
    localparam RESP_DECERR      = 2'b11;

    //==========================================================================
    // MAC Register Storage
    //==========================================================================
    reg  [31:0] reg_mac_lo;
    reg  [15:0] reg_mac_hi;
    reg         reg_mac_tx_enable;
    reg         reg_mac_rx_enable;
    reg  [3:0]  reg_mac_int_status;
    reg  [3:0]  reg_mac_int_mask;

    //==========================================================================
    // DMA Register Storage (conditional based on DMA_ENABLE)
    //==========================================================================
    generate
        if (DMA_ENABLE) begin : gen_dma_regs
            reg         reg_dma_tx_enable;
            reg         reg_dma_rx_enable;
            reg         reg_dma_reset;
            reg  [31:0] reg_tx_desc_base_lo;
            reg  [31:0] reg_tx_desc_base_hi;
            reg  [7:0]  reg_tx_ring_size;
            reg  [31:0] reg_rx_desc_base_lo;
            reg  [31:0] reg_rx_desc_base_hi;
            reg  [7:0]  reg_rx_ring_size;
            reg  [3:0]  reg_dma_int_status;
            reg  [3:0]  reg_dma_int_mask;
        end
    endgenerate

    //==========================================================================
    // AXI Write State Machine
    //==========================================================================
    localparam WR_IDLE  = 2'b00;
    localparam WR_DATA  = 2'b01;
    localparam WR_RESP  = 2'b10;

    reg [1:0] wr_state;
    reg [ADDR_WIDTH-1:0] wr_addr_latched;
    reg       wr_is_dma;  // Track if accessing DMA space

    //==========================================================================
    // AXI Read State Machine
    //==========================================================================
    localparam RD_IDLE  = 1'b0;
    localparam RD_DATA  = 1'b1;

    reg rd_state;
    reg [ADDR_WIDTH-1:0] rd_addr_latched;
    reg       rd_is_dma;  // Track if accessing DMA space

    //==========================================================================
    // Interrupt Capture Logic
    //==========================================================================
    wire [3:0] mac_int_capture;
    assign mac_int_capture = {mac_int_rx_runt, mac_int_rx_crc_err, 
                              mac_int_rx_received, mac_int_tx_complete};

    wire [3:0] dma_int_capture;
    generate
        if (DMA_ENABLE) begin : gen_dma_int_capture
            assign dma_int_capture = {dma_int_rx_error, dma_int_tx_error,
                                      dma_int_rx_complete, dma_int_tx_complete};
        end else begin : gen_no_dma_int
            assign dma_int_capture = 4'b0000;
        end
    endgenerate

    //==========================================================================
    // MAC Output Assignments
    //==========================================================================
    assign mac_addr      = {reg_mac_hi, reg_mac_lo};
    assign mac_tx_enable = reg_mac_tx_enable;
    assign mac_rx_enable = reg_mac_rx_enable;
    assign mac_irq       = |(reg_mac_int_status & reg_mac_int_mask);

    //==========================================================================
    // DMA Output Assignments
    //==========================================================================
    generate
        if (DMA_ENABLE) begin : gen_dma_outputs
            assign dma_tx_enable = gen_dma_regs.reg_dma_tx_enable;
            assign dma_rx_enable = gen_dma_regs.reg_dma_rx_enable;
            assign dma_reset     = gen_dma_regs.reg_dma_reset;
            
            // Handle 32-bit or 64-bit descriptor addressing
            if (DESC_ADDR_WIDTH == 64) begin : gen_desc64
                assign tx_desc_base = {gen_dma_regs.reg_tx_desc_base_hi, 
                                       gen_dma_regs.reg_tx_desc_base_lo};
                assign rx_desc_base = {gen_dma_regs.reg_rx_desc_base_hi, 
                                       gen_dma_regs.reg_rx_desc_base_lo};
            end else begin : gen_desc32
                assign tx_desc_base = gen_dma_regs.reg_tx_desc_base_lo[DESC_ADDR_WIDTH-1:0];
                assign rx_desc_base = gen_dma_regs.reg_rx_desc_base_lo[DESC_ADDR_WIDTH-1:0];
            end
            
            assign tx_ring_size = gen_dma_regs.reg_tx_ring_size;
            assign rx_ring_size = gen_dma_regs.reg_rx_ring_size;
            assign dma_irq      = |(gen_dma_regs.reg_dma_int_status & 
                                    gen_dma_regs.reg_dma_int_mask);
        end else begin : gen_no_dma_outputs
            assign dma_tx_enable = 1'b0;
            assign dma_rx_enable = 1'b0;
            assign dma_reset     = 1'b0;
            assign tx_desc_base  = {DESC_ADDR_WIDTH{1'b0}};
            assign rx_desc_base  = {DESC_ADDR_WIDTH{1'b0}};
            assign tx_ring_size  = 8'h00;
            assign rx_ring_size  = 8'h00;
            assign dma_irq       = 1'b0;
        end
    endgenerate

    //==========================================================================
    // Reset and Register Updates
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // MAC Registers
            reg_mac_lo          <= 32'h00000000;
            reg_mac_hi          <= 16'h0000;
            reg_mac_tx_enable   <= 1'b0;
            reg_mac_rx_enable   <= 1'b0;
            reg_mac_int_status  <= 4'b0000;
            reg_mac_int_mask    <= 4'b0000;

            // AXI Write State
            wr_state            <= WR_IDLE;
            wr_addr_latched     <= {ADDR_WIDTH{1'b0}};
            wr_is_dma           <= 1'b0;
            s_axi_awready       <= 1'b0;
            s_axi_wready        <= 1'b0;
            s_axi_bresp         <= RESP_OKAY;
            s_axi_bvalid        <= 1'b0;

            // AXI Read State
            rd_state            <= RD_IDLE;
            rd_addr_latched     <= {ADDR_WIDTH{1'b0}};
            rd_is_dma           <= 1'b0;
            s_axi_arready       <= 1'b0;
            s_axi_rdata         <= 32'h00000000;
            s_axi_rresp         <= RESP_OKAY;
            s_axi_rvalid        <= 1'b0;

        end else begin
            //=================================================================
            // MAC Interrupt Status Updates (write-1-to-clear or capture)
            //=================================================================
            if (wr_state == WR_DATA && !wr_is_dma && 
                wr_addr_latched[9:0] == ADDR_MAC_INT_STATUS && s_axi_wvalid) begin
                // Write-1-to-clear
                reg_mac_int_status <= reg_mac_int_status & ~s_axi_wdata[3:0];
            end else begin
                // Capture new interrupts
                reg_mac_int_status <= reg_mac_int_status | mac_int_capture;
            end

            //=================================================================
            // AXI Write Transaction
            //=================================================================
            case (wr_state)
                WR_IDLE: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b0;
                    
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        // Both address and data valid
                        s_axi_awready   <= 1'b1;
                        s_axi_wready    <= 1'b1;
                        wr_addr_latched <= s_axi_awaddr;
                        wr_is_dma       <= (s_axi_awaddr[9:8] == 2'b10); // 0x200-0x3FF
                        wr_state        <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    
                    // Perform write to MAC registers
                    if (!wr_is_dma) begin
                        case (wr_addr_latched[9:0])
                            ADDR_MAC_LO: begin
                                if (s_axi_wstrb[0]) reg_mac_lo[7:0]   <= s_axi_wdata[7:0];
                                if (s_axi_wstrb[1]) reg_mac_lo[15:8]  <= s_axi_wdata[15:8];
                                if (s_axi_wstrb[2]) reg_mac_lo[23:16] <= s_axi_wdata[23:16];
                                if (s_axi_wstrb[3]) reg_mac_lo[31:24] <= s_axi_wdata[31:24];
                            end
                            ADDR_MAC_HI: begin
                                if (s_axi_wstrb[0]) reg_mac_hi[7:0]  <= s_axi_wdata[7:0];
                                if (s_axi_wstrb[1]) reg_mac_hi[15:8] <= s_axi_wdata[15:8];
                            end
                            ADDR_MAC_CONTROL: begin
                                if (s_axi_wstrb[0]) begin
                                    reg_mac_tx_enable <= s_axi_wdata[0];
                                    reg_mac_rx_enable <= s_axi_wdata[1];
                                end
                            end
                            ADDR_MAC_INT_STATUS: begin
                                // Handled above (write-1-to-clear)
                            end
                            ADDR_MAC_INT_MASK: begin
                                if (s_axi_wstrb[0]) reg_mac_int_mask <= s_axi_wdata[3:0];
                            end
                            default: begin
                                // Read-only or invalid address
                            end
                        endcase
                        s_axi_bresp <= RESP_OKAY;
                    end

                    s_axi_bvalid <= 1'b1;
                    wr_state     <= WR_RESP;
                end

                WR_RESP: begin
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase

            //=================================================================
            // AXI Read Transaction
            //=================================================================
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready <= 1'b0;
                    s_axi_rvalid  <= 1'b0;
                    
                    if (s_axi_arvalid) begin
                        s_axi_arready   <= 1'b1;
                        rd_addr_latched <= s_axi_araddr;
                        rd_is_dma       <= (s_axi_araddr[9:8] == 2'b10); // 0x200-0x3FF
                        rd_state        <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    s_axi_arready <= 1'b0;
                    
                    // Perform read from MAC registers
                    if (!rd_is_dma) begin
                        case (rd_addr_latched[9:0])
                            ADDR_MAC_LO:         s_axi_rdata <= reg_mac_lo;
                            ADDR_MAC_HI:         s_axi_rdata <= {16'h0000, reg_mac_hi};
                            ADDR_MAC_CONTROL:    s_axi_rdata <= {30'h0, reg_mac_rx_enable, reg_mac_tx_enable};
                            ADDR_MAC_STATUS:     s_axi_rdata <= {30'h0, mac_rx_active, mac_tx_active};
                            ADDR_MAC_INT_STATUS: s_axi_rdata <= {28'h0, reg_mac_int_status};
                            ADDR_MAC_INT_MASK:   s_axi_rdata <= {28'h0, reg_mac_int_mask};
                            ADDR_MAC_TX_FRAME:   s_axi_rdata <= mac_tx_frame_cnt;
                            ADDR_MAC_RX_FRAME:   s_axi_rdata <= mac_rx_frame_cnt;
                            ADDR_MAC_RX_ERR:     s_axi_rdata <= mac_rx_err_cnt;
                            ADDR_MAC_VERSION:    s_axi_rdata <= MAC_VERSION;
                            default:             s_axi_rdata <= 32'h00000000;
                        endcase
                        s_axi_rresp <= RESP_OKAY;
                    end else begin
                        // DMA register space - return 0 if DMA disabled
                        s_axi_rdata <= 32'h00000000;
                        s_axi_rresp <= DMA_ENABLE ? RESP_OKAY : RESP_DECERR;
                    end

                    s_axi_rvalid <= 1'b1;
                    rd_state     <= RD_IDLE;
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    //==========================================================================
    // DMA Registers (Conditional Generation)
    //==========================================================================
    generate
        if (DMA_ENABLE) begin : gen_dma_logic
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    gen_dma_regs.reg_dma_tx_enable    <= 1'b0;
                    gen_dma_regs.reg_dma_rx_enable    <= 1'b0;
                    gen_dma_regs.reg_dma_reset        <= 1'b0;
                    gen_dma_regs.reg_tx_desc_base_lo  <= 32'h00000000;
                    gen_dma_regs.reg_tx_desc_base_hi  <= 32'h00000000;
                    gen_dma_regs.reg_tx_ring_size     <= 8'h00;
                    gen_dma_regs.reg_rx_desc_base_lo  <= 32'h00000000;
                    gen_dma_regs.reg_rx_desc_base_hi  <= 32'h00000000;
                    gen_dma_regs.reg_rx_ring_size     <= 8'h00;
                    gen_dma_regs.reg_dma_int_status   <= 4'b0000;
                    gen_dma_regs.reg_dma_int_mask     <= 4'b0000;
                end else begin
                    // Self-clearing reset bit
                    if (gen_dma_regs.reg_dma_reset)
                        gen_dma_regs.reg_dma_reset <= 1'b0;

                    // Interrupt status updates
                    if (wr_state == WR_DATA && wr_is_dma && 
                        wr_addr_latched[9:0] == ADDR_DMA_INT_STATUS && s_axi_wvalid) begin
                        gen_dma_regs.reg_dma_int_status <= gen_dma_regs.reg_dma_int_status & ~s_axi_wdata[3:0];
                    end else begin
                        gen_dma_regs.reg_dma_int_status <= gen_dma_regs.reg_dma_int_status | dma_int_capture;
                    end

                    // DMA register writes
                    if (wr_state == WR_DATA && wr_is_dma) begin
                        case (wr_addr_latched[9:0])
                            ADDR_DMA_CONTROL: begin
                                if (s_axi_wstrb[0]) begin
                                    gen_dma_regs.reg_dma_tx_enable <= s_axi_wdata[0];
                                    gen_dma_regs.reg_dma_rx_enable <= s_axi_wdata[1];
                                    gen_dma_regs.reg_dma_reset     <= s_axi_wdata[2];
                                end
                            end
                            ADDR_TX_DESC_BASE_LO: begin
                                if (s_axi_wstrb[0]) gen_dma_regs.reg_tx_desc_base_lo[7:0]   <= s_axi_wdata[7:0];
                                if (s_axi_wstrb[1]) gen_dma_regs.reg_tx_desc_base_lo[15:8]  <= s_axi_wdata[15:8];
                                if (s_axi_wstrb[2]) gen_dma_regs.reg_tx_desc_base_lo[23:16] <= s_axi_wdata[23:16];
                                if (s_axi_wstrb[3]) gen_dma_regs.reg_tx_desc_base_lo[31:24] <= s_axi_wdata[31:24];
                            end
                            ADDR_TX_DESC_BASE_HI: begin
                                if (s_axi_wstrb[0]) gen_dma_regs.reg_tx_desc_base_hi[7:0]   <= s_axi_wdata[7:0];
                                if (s_axi_wstrb[1]) gen_dma_regs.reg_tx_desc_base_hi[15:8]  <= s_axi_wdata[15:8];
                                if (s_axi_wstrb[2]) gen_dma_regs.reg_tx_desc_base_hi[23:16] <= s_axi_wdata[23:16];
                                if (s_axi_wstrb[3]) gen_dma_regs.reg_tx_desc_base_hi[31:24] <= s_axi_wdata[31:24];
                            end
                            ADDR_TX_RING_SIZE: begin
                                if (s_axi_wstrb[0]) gen_dma_regs.reg_tx_ring_size <= s_axi_wdata[7:0];
                            end
                            ADDR_RX_DESC_BASE_LO: begin
                                if (s_axi_wstrb[0]) gen_dma_regs.reg_rx_desc_base_lo[7:0]   <= s_axi_wdata[7:0];
                                if (s_axi_wstrb[1]) gen_dma_regs.reg_rx_desc_base_lo[15:8]  <= s_axi_wdata[15:8];
                                if (s_axi_wstrb[2]) gen_dma_regs.reg_rx_desc_base_lo[23:16] <= s_axi_wdata[23:16];
                                if (s_axi_wstrb[3]) gen_dma_regs.reg_rx_desc_base_lo[31:24] <= s_axi_wdata[31:24];
                            end
                            ADDR_RX_DESC_BASE_HI: begin
                                if (s_axi_wstrb[0]) gen_dma_regs.reg_rx_desc_base_hi[7:0]   <= s_axi_wdata[7:0];
                                if (s_axi_wstrb[1]) gen_dma_regs.reg_rx_desc_base_hi[15:8]  <= s_axi_wdata[15:8];
                                if (s_axi_wstrb[2]) gen_dma_regs.reg_rx_desc_base_hi[23:16] <= s_axi_wdata[23:16];
                                if (s_axi_wstrb[3]) gen_dma_regs.reg_rx_desc_base_hi[31:24] <= s_axi_wdata[31:24];
                            end
                            ADDR_RX_RING_SIZE: begin
                                if (s_axi_wstrb[0]) gen_dma_regs.reg_rx_ring_size <= s_axi_wdata[7:0];
                            end
                            ADDR_DMA_INT_STATUS: begin
                                // Handled above (write-1-to-clear)
                            end
                            ADDR_DMA_INT_MASK: begin
                                if (s_axi_wstrb[0]) gen_dma_regs.reg_dma_int_mask <= s_axi_wdata[3:0];
                            end
                            default: begin
                                // Read-only or invalid
                            end
                        endcase
                    end

                    // DMA register reads (update the read mux in main logic)
                end
            end

            // Add DMA read data to the read mux
            always @(*) begin
                if (rd_state == RD_DATA && rd_is_dma) begin
                    case (rd_addr_latched[9:0])
                        ADDR_DMA_CONTROL: begin
                            s_axi_rdata = {29'h0, gen_dma_regs.reg_dma_reset,
                                          gen_dma_regs.reg_dma_rx_enable, 
                                          gen_dma_regs.reg_dma_tx_enable};
                        end
                        ADDR_DMA_STATUS: begin
                            s_axi_rdata = {30'h0, dma_rx_busy, dma_tx_busy};
                        end
                        ADDR_TX_DESC_BASE_LO: s_axi_rdata = gen_dma_regs.reg_tx_desc_base_lo;
                        ADDR_TX_DESC_BASE_HI: s_axi_rdata = gen_dma_regs.reg_tx_desc_base_hi;
                        ADDR_TX_RING_SIZE:    s_axi_rdata = {24'h0, gen_dma_regs.reg_tx_ring_size};
                        ADDR_RX_DESC_BASE_LO: s_axi_rdata = gen_dma_regs.reg_rx_desc_base_lo;
                        ADDR_RX_DESC_BASE_HI: s_axi_rdata = gen_dma_regs.reg_rx_desc_base_hi;
                        ADDR_RX_RING_SIZE:    s_axi_rdata = {24'h0, gen_dma_regs.reg_rx_ring_size};
                        ADDR_DMA_INT_STATUS:  s_axi_rdata = {28'h0, gen_dma_regs.reg_dma_int_status};
                        ADDR_DMA_INT_MASK:    s_axi_rdata = {28'h0, gen_dma_regs.reg_dma_int_mask};
                        ADDR_DMA_TX_PKT:      s_axi_rdata = dma_tx_pkt_cnt;
                        ADDR_DMA_RX_PKT:      s_axi_rdata = dma_rx_pkt_cnt;
                        ADDR_DMA_TX_ERR:      s_axi_rdata = dma_tx_err_cnt;
                        ADDR_DMA_RX_ERR:      s_axi_rdata = dma_rx_err_cnt;
                        ADDR_DMA_VERSION:     s_axi_rdata = DMA_VERSION;
                        default:              s_axi_rdata = 32'h00000000;
                    endcase
                end
            end
        end
    endgenerate

endmodule
