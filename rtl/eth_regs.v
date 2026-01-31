//==============================================================================
// File: eth_regs.v
// Description: Unified Ethernet Register Block (MAC + DMA)
//
// Purpose:
//   Provides a unified AXI4-Lite slave interface for both Gigabit Ethernet MAC
//   and DMA configuration/status registers. This module combines mac_regs and
//   dma_regs functionality into a single, cohesive register interface with
//   address decoding.
//
//==============================================================================
// ADDRESS SPACE LAYOUT (AXI4-Lite, 32-bit data width)
//==============================================================================
//
// Total Address Space: 0x000 - 0x3FF (1KB)
//   - MAC Register Space:  0x000 - 0x1FF (512 bytes)
//   - DMA Register Space:  0x200 - 0x3FF (512 bytes)
//
//------------------------------------------------------------------------------
// MAC REGISTER MAP (0x000 - 0x1FF)
//------------------------------------------------------------------------------
//   Offset   Name              Width   Access  Description
//   ------   ----              -----   ------  -----------
//   0x000    MAC_ADDR_LO       [31:0]  RW      MAC Address bits [31:0]
//   0x004    MAC_ADDR_HI       [15:0]  RW      MAC Address bits [47:32]
//   0x008    MAC_CONTROL       [1:0]   RW      {rx_enable, tx_enable}
//   0x00C    MAC_STATUS        [1:0]   RO      {rx_active, tx_active}
//   0x010    MAC_INT_STATUS    [3:0]   RW1C    Interrupt status (Write-1-to-Clear)
//                                              [0] TX frame complete
//                                              [1] RX frame received
//                                              [2] RX CRC error
//                                              [3] RX runt frame
//   0x014    MAC_INT_MASK      [3:0]   RW      Interrupt mask (1=enabled)
//   0x018    MAC_TX_FRAME_CNT  [31:0]  RO      Transmitted frame counter
//   0x01C    MAC_RX_FRAME_CNT  [31:0]  RO      Received frame counter
//   0x020    MAC_RX_ERR_CNT    [31:0]  RO      RX error counter
//   0x024    MAC_VERSION       [31:0]  RO      MAC IP Version (0x0001_0000)
//
//------------------------------------------------------------------------------
// DMA REGISTER MAP (0x200 - 0x3FF) - Optional, controlled by DMA_ENABLE
//------------------------------------------------------------------------------
//   Offset   Name              Width   Access  Description
//   ------   ----              -----   ------  -----------
//
//   --- TX DMA Registers (0x200 - 0x23F) ---
//   0x200    DMA_TX_CTRL       [2:0]   RW      TX DMA Control
//                                              [0] tx_enable
//                                              [1] tx_reset (auto-clear)
//                                              [2] tx_irq_en
//   0x204    DMA_TX_STATUS     [2:0]   RO      TX DMA Status
//                                              [0] tx_busy
//                                              [1] tx_halted
//                                              [2] tx_error
//   0x208    DMA_TX_DESC_LO    [31:0]  RW      TX Descriptor Ring Base [31:0]
//   0x20C    DMA_TX_DESC_HI    [31:0]  RW      TX Descriptor Ring Base [63:32]
//   0x210    DMA_TX_RING_SIZE  [15:0]  RW      TX Ring Size (number of descriptors)
//   0x214    DMA_TX_HEAD_PTR   [15:0]  RW      TX Head Pointer (SW writes)
//   0x218    DMA_TX_TAIL_PTR   [15:0]  RO      TX Tail Pointer (HW updates)
//   0x21C    DMA_TX_PKT_CNT    [31:0]  RO      TX Packet Counter
//
//   --- RX DMA Registers (0x240 - 0x27F) ---
//   0x240    DMA_RX_CTRL       [2:0]   RW      RX DMA Control
//                                              [0] rx_enable
//                                              [1] rx_reset (auto-clear)
//                                              [2] rx_irq_en
//   0x244    DMA_RX_STATUS     [2:0]   RO      RX DMA Status
//                                              [0] rx_busy
//                                              [1] rx_halted
//                                              [2] rx_error
//   0x248    DMA_RX_DESC_LO    [31:0]  RW      RX Descriptor Ring Base [31:0]
//   0x24C    DMA_RX_DESC_HI    [31:0]  RW      RX Descriptor Ring Base [63:32]
//   0x250    DMA_RX_RING_SIZE  [15:0]  RW      RX Ring Size (number of descriptors)
//   0x254    DMA_RX_HEAD_PTR   [15:0]  RO      RX Head Pointer (HW updates)
//   0x258    DMA_RX_TAIL_PTR   [15:0]  RW      RX Tail Pointer (SW writes)
//   0x25C    DMA_RX_PKT_CNT    [31:0]  RO      RX Packet Counter
//
//   --- DMA Interrupt Registers (0x280 - 0x28F) ---
//   0x280    DMA_INT_STATUS    [4:0]   RW1C    DMA Interrupt Status (Write-1-to-Clear)
//                                              [0] TX done
//                                              [1] TX error
//                                              [2] RX done
//                                              [3] RX error
//                                              [4] Descriptor error
//   0x284    DMA_INT_MASK      [4:0]   RW      DMA Interrupt Mask (1=enabled)
//   0x288    DMA_INT_COALESCE  [31:0]  RW      Interrupt Coalescing Config
//                                              [15:0]  Packet count threshold
//                                              [31:16] Time threshold
//   0x28C    DMA_VERSION       [31:0]  RO      DMA IP Version (0x0001_0000)
//
//==============================================================================
// PARAMETERS
//==============================================================================
//   DMA_ENABLE    : Enable DMA register space (1=enabled, 0=disabled)
//   DMA_ADDR_WIDTH : System address width for DMA descriptor pointers (32/64)
//   MAC_VERSION   : MAC IP version identifier
//   DMA_VERSION   : DMA IP version identifier
//
//==============================================================================
// FEATURES
//==============================================================================
//   - Single unified AXI4-Lite slave interface
//   - Address decoding for MAC (0x000-0x1FF) and DMA (0x200-0x3FF) spaces
//   - Optional DMA registers controlled by DMA_ENABLE parameter
//   - State machine based AXI4-Lite protocol handling
//   - Write strobes support for byte-level register access
//   - Read-only registers protected from write side effects
//   - Write-1-to-Clear (RW1C) interrupt status registers
//   - Auto-clearing control bits (e.g., reset)
//   - Clean synchronous reset behavior
//   - Separate interrupt outputs for MAC and DMA
//
//==============================================================================
// VERIFICATION NOTES
//==============================================================================
//   - AXI4-Lite protocol compliance required
//   - Test address decode boundary at 0x1FF/0x200
//   - Verify DMA registers inaccessible when DMA_ENABLE=0
//   - Test RW1C behavior (write 1 clears, write 0 no effect)
//   - Verify auto-clear bits return to 0 after 1 cycle
//   - Test byte-level writes with WSTRB
//   - Verify no side effects on RO register writes
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_regs #(
    //==========================================================================
    // Parameters
    //==========================================================================
    parameter DMA_ENABLE      = 1,                // Enable DMA register space
    parameter DMA_ADDR_WIDTH  = 64,               // System address width (for DMA)
    parameter AXI_ADDR_WIDTH  = 10,               // AXI address width
    parameter MAC_VERSION     = 32'h0001_0000,    // MAC IP Version 1.0.0
    parameter DMA_VERSION     = 32'h0001_0000     // DMA IP Version 1.0.0
)(
    //==========================================================================
    // Clock and Reset
    //==========================================================================
    input  wire                     clk,        // System clock
    input  wire                     rst_n,      // Active-low synchronous reset

    //==========================================================================
    // AXI4-Lite Slave Interface (Unified)
    //==========================================================================
    // Write Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,   // Write address (10-bit: 0x000-0x3FF)
    input  wire                     s_axi_awvalid,  // Write address valid
    output reg                      s_axi_awready,  // Write address ready

    // Write Data Channel
    input  wire [31:0]              s_axi_wdata,    // Write data (32-bit)
    input  wire [3:0]               s_axi_wstrb,    // Write strobes (byte enables)
    input  wire                     s_axi_wvalid,   // Write valid
    output reg                      s_axi_wready,   // Write ready

    // Write Response Channel
    output reg  [1:0]               s_axi_bresp,    // Write response
    output reg                      s_axi_bvalid,   // Write response valid
    input  wire                     s_axi_bready,   // Write response ready

    // Read Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,   // Read address (10-bit: 0x000-0x3FF)
    input  wire                     s_axi_arvalid,  // Read address valid
    output reg                      s_axi_arready,  // Read address ready

    // Read Data Channel
    output reg  [31:0]              s_axi_rdata,    // Read data (32-bit)
    output reg  [1:0]               s_axi_rresp,    // Read response
    output reg                      s_axi_rvalid,   // Read valid
    input  wire                     s_axi_rready,   // Read ready

    //==========================================================================
    // MAC Control Outputs
    //==========================================================================
    output wire [47:0]              mac_addr,       // MAC address
    output wire                     mac_tx_enable,  // MAC TX path enable
    output wire                     mac_rx_enable,  // MAC RX path enable
    output wire [3:0]               mac_int_mask,   // MAC interrupt mask

    //==========================================================================
    // MAC Status Inputs
    //==========================================================================
    input  wire                     mac_tx_active,  // MAC TX currently active
    input  wire                     mac_rx_active,  // MAC RX currently active
    input  wire [31:0]              mac_tx_frame_cnt, // MAC TX frame counter
    input  wire [31:0]              mac_rx_frame_cnt, // MAC RX frame counter
    input  wire [31:0]              mac_rx_err_cnt,   // MAC RX error counter

    //==========================================================================
    // MAC Interrupt Inputs
    //==========================================================================
    input  wire                     mac_int_tx_complete, // MAC TX complete pulse
    input  wire                     mac_int_rx_received, // MAC RX received pulse
    input  wire                     mac_int_rx_crc_err,  // MAC RX CRC error pulse
    input  wire                     mac_int_rx_runt,     // MAC RX runt frame pulse

    //==========================================================================
    // MAC Interrupt Output
    //==========================================================================
    output wire                     mac_irq,        // MAC interrupt output

    //==========================================================================
    // DMA TX Control Outputs
    //==========================================================================
    output wire                     dma_tx_enable,      // DMA TX enable
    output reg                      dma_tx_reset,       // DMA TX reset (auto-clear)
    output wire                     dma_tx_irq_en,      // DMA TX interrupt enable
    output wire [DMA_ADDR_WIDTH-1:0] dma_tx_ring_base,   // DMA TX ring base address
    output wire [15:0]              dma_tx_ring_size,   // DMA TX ring size
    output wire [15:0]              dma_tx_head_ptr,    // DMA TX head pointer

    //==========================================================================
    // DMA TX Status Inputs
    //==========================================================================
    input  wire                     dma_tx_busy,        // DMA TX busy
    input  wire                     dma_tx_halted,      // DMA TX halted
    input  wire                     dma_tx_error,       // DMA TX error
    input  wire [15:0]              dma_tx_tail_ptr,    // DMA TX tail pointer
    input  wire [31:0]              dma_tx_pkt_cnt,     // DMA TX packet counter

    //==========================================================================
    // DMA RX Control Outputs
    //==========================================================================
    output wire                     dma_rx_enable,      // DMA RX enable
    output reg                      dma_rx_reset,       // DMA RX reset (auto-clear)
    output wire                     dma_rx_irq_en,      // DMA RX interrupt enable
    output wire [DMA_ADDR_WIDTH-1:0] dma_rx_ring_base,   // DMA RX ring base address
    output wire [15:0]              dma_rx_ring_size,   // DMA RX ring size
    output wire [15:0]              dma_rx_tail_ptr,    // DMA RX tail pointer

    //==========================================================================
    // DMA RX Status Inputs
    //==========================================================================
    input  wire                     dma_rx_busy,        // DMA RX busy
    input  wire                     dma_rx_halted,      // DMA RX halted
    input  wire                     dma_rx_error,       // DMA RX error
    input  wire [15:0]              dma_rx_head_ptr,    // DMA RX head pointer
    input  wire [31:0]              dma_rx_pkt_cnt,     // DMA RX packet counter

    //==========================================================================
    // DMA Interrupt Inputs
    //==========================================================================
    input  wire                     dma_int_tx_done,    // DMA TX done pulse
    input  wire                     dma_int_tx_err,     // DMA TX error pulse
    input  wire                     dma_int_rx_done,    // DMA RX done pulse
    input  wire                     dma_int_rx_err,     // DMA RX error pulse
    input  wire                     dma_int_desc_err,   // DMA descriptor error pulse

    //==========================================================================
    // DMA Interrupt Output
    //==========================================================================
    output wire                     dma_irq             // DMA interrupt output
);

    //==========================================================================
    // Local Parameters
    //==========================================================================
    
    // AXI Response Codes
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_DECERR = 2'b11;     // Decode error for invalid/disabled addresses
    
    // Address Space Boundaries
    localparam [9:0] MAC_BASE  = 10'h000;
    localparam [9:0] MAC_END   = 10'h1FF;
    localparam [9:0] DMA_BASE  = 10'h200;
    localparam [9:0] DMA_END   = 10'h3FF;

    //--------------------------------------------------------------------------
    // MAC Register Addresses (relative to MAC_BASE = 0x000)
    //--------------------------------------------------------------------------
    localparam [9:0]
        ADDR_MAC_ADDR_LO      = 10'h000,
        ADDR_MAC_ADDR_HI      = 10'h004,
        ADDR_MAC_CONTROL      = 10'h008,
        ADDR_MAC_STATUS       = 10'h00C,
        ADDR_MAC_INT_STATUS   = 10'h010,
        ADDR_MAC_INT_MASK     = 10'h014,
        ADDR_MAC_TX_FRAME_CNT = 10'h018,
        ADDR_MAC_RX_FRAME_CNT = 10'h01C,
        ADDR_MAC_RX_ERR_CNT   = 10'h020,
        ADDR_MAC_VERSION      = 10'h024;

    //--------------------------------------------------------------------------
    // DMA Register Addresses (relative to DMA_BASE = 0x200)
    //--------------------------------------------------------------------------
    localparam [9:0]
        // TX DMA Registers
        ADDR_DMA_TX_CTRL      = 10'h200,
        ADDR_DMA_TX_STATUS    = 10'h204,
        ADDR_DMA_TX_DESC_LO   = 10'h208,
        ADDR_DMA_TX_DESC_HI   = 10'h20C,
        ADDR_DMA_TX_RING_SIZE = 10'h210,
        ADDR_DMA_TX_HEAD_PTR  = 10'h214,
        ADDR_DMA_TX_TAIL_PTR  = 10'h218,
        ADDR_DMA_TX_PKT_CNT   = 10'h21C,
        
        // RX DMA Registers
        ADDR_DMA_RX_CTRL      = 10'h240,
        ADDR_DMA_RX_STATUS    = 10'h244,
        ADDR_DMA_RX_DESC_LO   = 10'h248,
        ADDR_DMA_RX_DESC_HI   = 10'h24C,
        ADDR_DMA_RX_RING_SIZE = 10'h250,
        ADDR_DMA_RX_HEAD_PTR  = 10'h254,
        ADDR_DMA_RX_TAIL_PTR  = 10'h258,
        ADDR_DMA_RX_PKT_CNT   = 10'h25C,
        
        // DMA Interrupt Registers
        ADDR_DMA_INT_STATUS   = 10'h280,
        ADDR_DMA_INT_MASK     = 10'h284,
        ADDR_DMA_INT_COALESCE = 10'h288;

        ADDR_DMA_VERSION      = 10'h28C;

    //==========================================================================
    // AXI State Machine States
    //==========================================================================
    // Write States
    localparam [1:0]
        WR_IDLE = 2'b00,
        WR_DATA = 2'b01,
        WR_RESP = 2'b10;
    
    // Read States
    localparam
        RD_IDLE = 1'b0,
        RD_DATA = 1'b1;

    //==========================================================================
    // Register Storage - MAC Registers
    //==========================================================================
    reg [31:0] mac_reg_addr_lo;         // MAC address [31:0]
    reg [15:0] mac_reg_addr_hi;         // MAC address [47:32]
    reg        mac_reg_tx_enable;       // MAC TX enable
    reg        mac_reg_rx_enable;       // MAC RX enable
    reg [3:0]  mac_reg_int_status;      // MAC interrupt status (RW1C)
    reg [3:0]  mac_reg_int_mask;        // MAC interrupt mask

    //==========================================================================
    // Register Storage - DMA Registers (only if DMA_ENABLE == 1)
    //==========================================================================
    reg                       dma_reg_tx_enable;       // DMA TX enable
    reg                       dma_reg_tx_irq_en;       // DMA TX IRQ enable
    reg [DMA_ADDR_WIDTH-1:0]   dma_reg_tx_ring_base;    // DMA TX ring base
    reg [15:0]                dma_reg_tx_ring_size;    // DMA TX ring size
    reg [15:0]                dma_reg_tx_head_ptr;     // DMA TX head pointer
    
    reg                       dma_reg_rx_enable;       // DMA RX enable
    reg                       dma_reg_rx_irq_en;       // DMA RX IRQ enable
    reg [DMA_ADDR_WIDTH-1:0]   dma_reg_rx_ring_base;    // DMA RX ring base
    reg [15:0]                dma_reg_rx_ring_size;    // DMA RX ring size
    reg [15:0]                dma_reg_rx_tail_ptr;     // DMA RX tail pointer
    
    reg [4:0]                 dma_reg_int_status;      // DMA interrupt status (RW1C)
    reg [4:0]                 dma_reg_int_mask;        // DMA interrupt mask
    reg [15:0]                dma_reg_int_coal_cnt;    // Interrupt coalesce packet count
    reg [15:0]                dma_reg_int_coal_time;   // Interrupt coalesce time

    //==========================================================================
    // AXI Write State Machine Registers
    //==========================================================================
    reg [1:0] wr_state;
    reg [9:0] wr_addr_latched;

    //==========================================================================
    // AXI Read State Machine Registers
    //==========================================================================
    reg       rd_state;
    reg [9:0] rd_addr_latched;

    //==========================================================================
    // MAC Interrupt Edge Detection
    //==========================================================================
    reg mac_int_tx_complete_d, mac_int_rx_received_d;
    reg mac_int_rx_crc_err_d, mac_int_rx_runt_d;
    
    wire mac_int_tx_complete_edge = mac_int_tx_complete && !mac_int_tx_complete_d;
    wire mac_int_rx_received_edge = mac_int_rx_received && !mac_int_rx_received_d;
    wire mac_int_rx_crc_err_edge  = mac_int_rx_crc_err  && !mac_int_rx_crc_err_d;
    wire mac_int_rx_runt_edge     = mac_int_rx_runt     && !mac_int_rx_runt_d;
    
    wire [3:0] mac_int_capture = {mac_int_rx_runt_edge, 
                                   mac_int_rx_crc_err_edge,
                                   mac_int_rx_received_edge, 
                                   mac_int_tx_complete_edge};

    //==========================================================================
    // DMA Interrupt Edge Detection (only if DMA_ENABLE == 1)
    //==========================================================================
    reg dma_int_tx_done_d, dma_int_tx_err_d;
    reg dma_int_rx_done_d, dma_int_rx_err_d, dma_int_desc_err_d;
    
    wire dma_int_tx_done_edge   = dma_int_tx_done   && !dma_int_tx_done_d;
    wire dma_int_tx_err_edge    = dma_int_tx_err    && !dma_int_tx_err_d;
    wire dma_int_rx_done_edge   = dma_int_rx_done   && !dma_int_rx_done_d;
    wire dma_int_rx_err_edge    = dma_int_rx_err    && !dma_int_rx_err_d;
    wire dma_int_desc_err_edge  = dma_int_desc_err  && !dma_int_desc_err_d;
    
    wire [4:0] dma_int_capture = {dma_int_desc_err_edge,
                                   dma_int_rx_err_edge,
                                   dma_int_rx_done_edge,
                                   dma_int_tx_err_edge,
                                   dma_int_tx_done_edge};

    //==========================================================================
    // Output Assignments - MAC
    //==========================================================================
    assign mac_addr      = {mac_reg_addr_hi, mac_reg_addr_lo};
    assign mac_tx_enable = mac_reg_tx_enable;
    assign mac_rx_enable = mac_reg_rx_enable;
    assign mac_int_mask  = mac_reg_int_mask;
    assign mac_irq       = |(mac_reg_int_status & mac_reg_int_mask);

    //==========================================================================
    // Output Assignments - DMA (conditional based on DMA_ENABLE)
    //==========================================================================
    generate
        if (DMA_ENABLE) begin : gen_dma_outputs
            assign dma_tx_enable    = dma_reg_tx_enable;
            assign dma_tx_irq_en    = dma_reg_tx_irq_en;
            assign dma_tx_ring_base = dma_reg_tx_ring_base;
            assign dma_tx_ring_size = dma_reg_tx_ring_size;
            assign dma_tx_head_ptr  = dma_reg_tx_head_ptr;
            
            assign dma_rx_enable    = dma_reg_rx_enable;
            assign dma_rx_irq_en    = dma_reg_rx_irq_en;
            assign dma_rx_ring_base = dma_reg_rx_ring_base;
            assign dma_rx_ring_size = dma_reg_rx_ring_size;
            assign dma_rx_tail_ptr  = dma_reg_rx_tail_ptr;
            
            assign dma_irq = |(dma_reg_int_status & dma_reg_int_mask);
        end else begin : gen_dma_outputs_disabled
            assign dma_tx_enable    = 1'b0;
            assign dma_tx_irq_en    = 1'b0;
            assign dma_tx_ring_base = {DMA_ADDR_WIDTH{1'b0}};
            assign dma_tx_ring_size = 16'd0;
            assign dma_tx_head_ptr  = 16'd0;
            
            assign dma_rx_enable    = 1'b0;
            assign dma_rx_irq_en    = 1'b0;
            assign dma_rx_ring_base = {DMA_ADDR_WIDTH{1'b0}};
            assign dma_rx_ring_size = 16'd0;
            assign dma_rx_tail_ptr  = 16'd0;
            
            assign dma_irq = 1'b0;
        end
    endgenerate

    //==========================================================================
    // AXI Write State Machine
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state        <= WR_IDLE;
            wr_addr_latched <= 10'd0;
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= RESP_OKAY;
        end else begin
            case (wr_state)
                //--------------------------------------------------------------
                // WR_IDLE: Wait for write address and data
                //--------------------------------------------------------------
                WR_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    
                    // Both address and data valid - proceed to response
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        wr_addr_latched <= s_axi_awaddr;
                        s_axi_awready   <= 1'b0;
                        s_axi_wready    <= 1'b0;
                        wr_state        <= WR_RESP;
                    end 
                    // Address arrived first - wait for data
                    else if (s_axi_awvalid) begin
                        wr_addr_latched <= s_axi_awaddr;
                        s_axi_awready   <= 1'b0;
                        wr_state        <= WR_DATA;
                    end
                end

                //--------------------------------------------------------------
                // WR_DATA: Wait for write data
                //--------------------------------------------------------------
                WR_DATA: begin
                    if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b0;
                        wr_state     <= WR_RESP;
                    end
                end

                //--------------------------------------------------------------
                // WR_RESP: Generate write response
                //--------------------------------------------------------------
                WR_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    
                    // Check for decode error (invalid address or DMA disabled)
                    if (!DMA_ENABLE && (wr_addr_latched >= DMA_BASE)) begin
                        s_axi_bresp <= RESP_DECERR;
                    end else begin
                        s_axi_bresp <= RESP_OKAY;
                    end
                    
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
    //==========================================================================
    
    // Write enable signal
    wire wr_en;
    assign wr_en = (wr_state == WR_IDLE && s_axi_awvalid && s_axi_wvalid) ||
                   (wr_state == WR_DATA && s_axi_wvalid);
    
    // Effective write address
    wire [9:0] wr_addr_eff;
    assign wr_addr_eff = (wr_state == WR_IDLE) ? s_axi_awaddr : wr_addr_latched;

    always @(posedge clk) begin
        if (!rst_n) begin
            //------------------------------------------------------------------
            // Reset MAC Registers
            //------------------------------------------------------------------
            mac_reg_addr_lo     <= 32'h0000_0000;
            mac_reg_addr_hi     <= 16'h0000;
            mac_reg_tx_enable   <= 1'b0;
            mac_reg_rx_enable   <= 1'b0;
            mac_reg_int_status  <= 4'b0000;
            mac_reg_int_mask    <= 4'b0000;
            
            // MAC interrupt edge detection
            mac_int_tx_complete_d <= 1'b0;
            mac_int_rx_received_d <= 1'b0;
            mac_int_rx_crc_err_d  <= 1'b0;
            mac_int_rx_runt_d     <= 1'b0;

            //------------------------------------------------------------------
            // Reset DMA Registers (only if DMA_ENABLE == 1)
            //------------------------------------------------------------------
            if (DMA_ENABLE) begin
                dma_reg_tx_enable       <= 1'b0;
                dma_tx_reset            <= 1'b0;
                dma_reg_tx_irq_en       <= 1'b0;
                dma_reg_tx_ring_base    <= {DMA_ADDR_WIDTH{1'b0}};
                dma_reg_tx_ring_size    <= 16'd256;
                dma_reg_tx_head_ptr     <= 16'd0;
                
                dma_reg_rx_enable       <= 1'b0;
                dma_rx_reset            <= 1'b0;
                dma_reg_rx_irq_en       <= 1'b0;
                dma_reg_rx_ring_base    <= {DMA_ADDR_WIDTH{1'b0}};
                dma_reg_rx_ring_size    <= 16'd256;
                dma_reg_rx_tail_ptr     <= 16'd0;
                
                dma_reg_int_status      <= 5'd0;
                dma_reg_int_mask        <= 5'd0;
                dma_reg_int_coal_cnt    <= 16'd1;
                dma_reg_int_coal_time   <= 16'd0;
                
                // DMA interrupt edge detection
                dma_int_tx_done_d   <= 1'b0;
                dma_int_tx_err_d    <= 1'b0;
                dma_int_rx_done_d   <= 1'b0;
                dma_int_rx_err_d    <= 1'b0;
                dma_int_desc_err_d  <= 1'b0;
            end

        end else begin
            //------------------------------------------------------------------
            // Auto-clear DMA reset bits
            //------------------------------------------------------------------
            if (DMA_ENABLE) begin
                dma_tx_reset <= 1'b0;
                dma_rx_reset <= 1'b0;
            end

            //------------------------------------------------------------------
            // MAC Interrupt Edge Detection and Capture
            //------------------------------------------------------------------
            mac_int_tx_complete_d <= mac_int_tx_complete;
            mac_int_rx_received_d <= mac_int_rx_received;
            mac_int_rx_crc_err_d  <= mac_int_rx_crc_err;
            mac_int_rx_runt_d     <= mac_int_rx_runt;
            
            // Capture MAC interrupts (sticky bits)
            mac_reg_int_status <= mac_reg_int_status | mac_int_capture;

            //------------------------------------------------------------------
            // DMA Interrupt Edge Detection and Capture (if enabled)
            //------------------------------------------------------------------
            if (DMA_ENABLE) begin
                dma_int_tx_done_d   <= dma_int_tx_done;
                dma_int_tx_err_d    <= dma_int_tx_err;
                dma_int_rx_done_d   <= dma_int_rx_done;
                dma_int_rx_err_d    <= dma_int_rx_err;
                dma_int_desc_err_d  <= dma_int_desc_err;
                
                // Capture DMA interrupts (sticky bits)
                dma_reg_int_status <= dma_reg_int_status | dma_int_capture;
            end

            //------------------------------------------------------------------
            // Register Writes
            //------------------------------------------------------------------
            if (wr_en) begin
                case (wr_addr_eff)
                    //==========================================================
                    // MAC Register Writes
                    //==========================================================
                    
                    ADDR_MAC_ADDR_LO: begin
                        if (s_axi_wstrb[0]) mac_reg_addr_lo[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) mac_reg_addr_lo[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) mac_reg_addr_lo[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) mac_reg_addr_lo[31:24] <= s_axi_wdata[31:24];
                    end
                    
                    ADDR_MAC_ADDR_HI: begin
                        if (s_axi_wstrb[0]) mac_reg_addr_hi[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) mac_reg_addr_hi[15:8] <= s_axi_wdata[15:8];
                    end
                    
                    ADDR_MAC_CONTROL: begin
                        if (s_axi_wstrb[0]) begin
                            mac_reg_tx_enable <= s_axi_wdata[0];
                            mac_reg_rx_enable <= s_axi_wdata[1];
                        end
                    end
                    
                    ADDR_MAC_INT_STATUS: begin
                        // Write-1-to-Clear: clear bits while capturing new interrupts
                        if (s_axi_wstrb[0]) begin
                            mac_reg_int_status <= (mac_reg_int_status | mac_int_capture) & 
                                                   ~s_axi_wdata[3:0];
                        end
                    end
                    
                    ADDR_MAC_INT_MASK: begin
                        if (s_axi_wstrb[0]) begin
                            mac_reg_int_mask <= s_axi_wdata[3:0];
                        end
                    end

                    //==========================================================
                    // DMA Register Writes (only if DMA_ENABLE == 1)
                    //==========================================================
                    
                    ADDR_DMA_TX_CTRL: begin
                        if (DMA_ENABLE && s_axi_wstrb[0]) begin
                            dma_reg_tx_enable <= s_axi_wdata[0];
                            dma_tx_reset      <= s_axi_wdata[1];  // Auto-clear
                            dma_reg_tx_irq_en <= s_axi_wdata[2];
                        end
                    end
                    
                    ADDR_DMA_TX_DESC_LO: begin
                        if (DMA_ENABLE) begin
                            if (s_axi_wstrb[0]) dma_reg_tx_ring_base[7:0]   <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) dma_reg_tx_ring_base[15:8]  <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) dma_reg_tx_ring_base[23:16] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) dma_reg_tx_ring_base[31:24] <= s_axi_wdata[31:24];
                        end
                    end
                    
                    ADDR_DMA_TX_DESC_HI: begin
                        if (DMA_ENABLE && DMA_ADDR_WIDTH > 32) begin
                            if (s_axi_wstrb[0]) dma_reg_tx_ring_base[39:32] <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) dma_reg_tx_ring_base[47:40] <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) dma_reg_tx_ring_base[55:48] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) dma_reg_tx_ring_base[63:56] <= s_axi_wdata[31:24];
                        end
                    end
                    
                    ADDR_DMA_TX_RING_SIZE: begin
                        if (DMA_ENABLE) begin
                            if (s_axi_wstrb[0]) dma_reg_tx_ring_size[7:0]  <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) dma_reg_tx_ring_size[15:8] <= s_axi_wdata[15:8];
                        end
                    end
                    
                    ADDR_DMA_TX_HEAD_PTR: begin
                        if (DMA_ENABLE) begin
                            if (s_axi_wstrb[0]) dma_reg_tx_head_ptr[7:0]  <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) dma_reg_tx_head_ptr[15:8] <= s_axi_wdata[15:8];
                        end
                    end
                    
                    ADDR_DMA_RX_CTRL: begin
                        if (DMA_ENABLE && s_axi_wstrb[0]) begin
                            dma_reg_rx_enable <= s_axi_wdata[0];
                            dma_rx_reset      <= s_axi_wdata[1];  // Auto-clear
                            dma_reg_rx_irq_en <= s_axi_wdata[2];
                        end
                    end
                    
                    ADDR_DMA_RX_DESC_LO: begin
                        if (DMA_ENABLE) begin
                            if (s_axi_wstrb[0]) dma_reg_rx_ring_base[7:0]   <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) dma_reg_rx_ring_base[15:8]  <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) dma_reg_rx_ring_base[23:16] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) dma_reg_rx_ring_base[31:24] <= s_axi_wdata[31:24];
                        end
                    end
                    
                    ADDR_DMA_RX_DESC_HI: begin
                        if (DMA_ENABLE && DMA_ADDR_WIDTH > 32) begin
                            if (s_axi_wstrb[0]) dma_reg_rx_ring_base[39:32] <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) dma_reg_rx_ring_base[47:40] <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) dma_reg_rx_ring_base[55:48] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) dma_reg_rx_ring_base[63:56] <= s_axi_wdata[31:24];
                        end
                    end
                    
                    ADDR_DMA_RX_RING_SIZE: begin
                        if (DMA_ENABLE) begin
                            if (s_axi_wstrb[0]) dma_reg_rx_ring_size[7:0]  <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) dma_reg_rx_ring_size[15:8] <= s_axi_wdata[15:8];
                        end
                    end
                    
                    ADDR_DMA_RX_TAIL_PTR: begin
                        if (DMA_ENABLE) begin
                            if (s_axi_wstrb[0]) dma_reg_rx_tail_ptr[7:0]  <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) dma_reg_rx_tail_ptr[15:8] <= s_axi_wdata[15:8];
                        end
                    end
                    
                    ADDR_DMA_INT_STATUS: begin
                        // Write-1-to-Clear: clear bits while capturing new interrupts
                        if (DMA_ENABLE && s_axi_wstrb[0]) begin
                            dma_reg_int_status <= (dma_reg_int_status | dma_int_capture) & 
                                                   ~s_axi_wdata[4:0];
                        end
                    end
                    
                    ADDR_DMA_INT_MASK: begin
                        if (DMA_ENABLE && s_axi_wstrb[0]) begin
                            dma_reg_int_mask <= s_axi_wdata[4:0];
                        end
                    end
                    
                    ADDR_DMA_INT_COALESCE: begin
                        if (DMA_ENABLE) begin
                            if (s_axi_wstrb[0]) dma_reg_int_coal_cnt[7:0]    <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) dma_reg_int_coal_cnt[15:8]   <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) dma_reg_int_coal_time[7:0]   <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) dma_reg_int_coal_time[15:8]  <= s_axi_wdata[31:24];
                        end
                    end

                    // All other addresses or RO registers - writes ignored (no side effects)
                    default: begin
                        // No operation
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
            rd_addr_latched <= 10'd0;
            s_axi_arready   <= 1'b0;
            s_axi_rvalid    <= 1'b0;
            s_axi_rdata     <= 32'd0;
            s_axi_rresp     <= RESP_OKAY;
        end else begin
            case (rd_state)
                //--------------------------------------------------------------
                // RD_IDLE: Wait for read address
                //--------------------------------------------------------------
                RD_IDLE: begin
                    s_axi_arready <= 1'b1;
                    s_axi_rvalid  <= 1'b0;
                    
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_addr_latched <= s_axi_araddr;
                        s_axi_arready   <= 1'b0;
                        rd_state        <= RD_DATA;
                    end
                end

                //--------------------------------------------------------------
                // RD_DATA: Return read data
                //--------------------------------------------------------------
                RD_DATA: begin
                    s_axi_rvalid <= 1'b1;
                    
                    // Check for decode error (invalid address or DMA disabled)
                    if (!DMA_ENABLE && (rd_addr_latched >= DMA_BASE)) begin
                        s_axi_rresp <= RESP_DECERR;
                        s_axi_rdata <= 32'hDEAD_BEEF;  // Debug pattern
                    end else begin
                        s_axi_rresp <= RESP_OKAY;
                        
                        // Address decode and data return
                        case (rd_addr_latched)
                            //==================================================
                            // MAC Register Reads
                            //==================================================
                            ADDR_MAC_ADDR_LO:      s_axi_rdata <= mac_reg_addr_lo;
                            ADDR_MAC_ADDR_HI:      s_axi_rdata <= {16'd0, mac_reg_addr_hi};
                            ADDR_MAC_CONTROL:      s_axi_rdata <= {30'd0, mac_reg_rx_enable, mac_reg_tx_enable};
                            ADDR_MAC_STATUS:       s_axi_rdata <= {30'd0, mac_rx_active, mac_tx_active};
                            ADDR_MAC_INT_STATUS:   s_axi_rdata <= {28'd0, mac_reg_int_status};
                            ADDR_MAC_INT_MASK:     s_axi_rdata <= {28'd0, mac_reg_int_mask};
                            ADDR_MAC_TX_FRAME_CNT: s_axi_rdata <= mac_tx_frame_cnt;
                            ADDR_MAC_RX_FRAME_CNT: s_axi_rdata <= mac_rx_frame_cnt;
                            ADDR_MAC_RX_ERR_CNT:   s_axi_rdata <= mac_rx_err_cnt;
                            ADDR_MAC_VERSION:      s_axi_rdata <= MAC_VERSION;

                            //==================================================
                            // DMA Register Reads (only if DMA_ENABLE == 1)
                            //==================================================
                            ADDR_DMA_TX_CTRL: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {29'd0, dma_reg_tx_irq_en, dma_tx_reset, dma_reg_tx_enable};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_TX_STATUS: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {29'd0, dma_tx_error, dma_tx_halted, dma_tx_busy};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_TX_DESC_LO: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= dma_reg_tx_ring_base[31:0];
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_TX_DESC_HI: begin
                                if (DMA_ENABLE && DMA_ADDR_WIDTH > 32)
                                    s_axi_rdata <= dma_reg_tx_ring_base[63:32];
                                else if (DMA_ENABLE)
                                    s_axi_rdata <= 32'd0;
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_TX_RING_SIZE: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {16'd0, dma_reg_tx_ring_size};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_TX_HEAD_PTR: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {16'd0, dma_reg_tx_head_ptr};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_TX_TAIL_PTR: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {16'd0, dma_tx_tail_ptr};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_TX_PKT_CNT: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= dma_tx_pkt_cnt;
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_RX_CTRL: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {29'd0, dma_reg_rx_irq_en, dma_rx_reset, dma_reg_rx_enable};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_RX_STATUS: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {29'd0, dma_rx_error, dma_rx_halted, dma_rx_busy};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_RX_DESC_LO: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= dma_reg_rx_ring_base[31:0];
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_RX_DESC_HI: begin
                                if (DMA_ENABLE && DMA_ADDR_WIDTH > 32)
                                    s_axi_rdata <= dma_reg_rx_ring_base[63:32];
                                else if (DMA_ENABLE)
                                    s_axi_rdata <= 32'd0;
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_RX_RING_SIZE: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {16'd0, dma_reg_rx_ring_size};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_RX_HEAD_PTR: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {16'd0, dma_rx_head_ptr};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_RX_TAIL_PTR: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {16'd0, dma_reg_rx_tail_ptr};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_RX_PKT_CNT: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= dma_rx_pkt_cnt;
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_INT_STATUS: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {27'd0, dma_reg_int_status};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_INT_MASK: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {27'd0, dma_reg_int_mask};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end
                            
                            ADDR_DMA_INT_COALESCE: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= {dma_reg_int_coal_time, dma_reg_int_coal_cnt};
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end

                            ADDR_DMA_VERSION: begin
                                if (DMA_ENABLE)
                                    s_axi_rdata <= DMA_VERSION;
                                else
                                    s_axi_rdata <= 32'hDEAD_BEEF;
                            end

                            // Undefined address
                            default: s_axi_rdata <= 32'hDEAD_BEEF;
                        endcase
                    end
                    
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
