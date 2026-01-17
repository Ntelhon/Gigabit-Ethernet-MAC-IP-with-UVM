//==============================================================================
// File: dma_regs.v
// Description: DMA Register Block
//
// Purpose:
//   Provides AXI4-Lite slave interface for DMA configuration and status.
//   This module handles the DMA-specific register space (offsets 0x00-0xFF
//   from DMA base address, which is 0x200 in the unified address space).
//
// Register Map (relative to DMA base 0x200):
//   0x00 - TX_CTRL:       TX DMA Control
//   0x04 - TX_STATUS:     TX DMA Status (RO)
//   0x08 - TX_DESC_LO:    TX Descriptor Ring Base Low
//   0x0C - TX_DESC_HI:    TX Descriptor Ring Base High
//   0x10 - TX_RING_SIZE:  TX Ring Size (number of descriptors)
//   0x14 - TX_HEAD_PTR:   TX Head Pointer (RW)
//   0x18 - TX_TAIL_PTR:   TX Tail Pointer (RO)
//   0x1C - TX_PKT_CNT:    TX Packet Counter (RO)
//
//   0x40 - RX_CTRL:       RX DMA Control
//   0x44 - RX_STATUS:     RX DMA Status (RO)
//   0x48 - RX_DESC_LO:    RX Descriptor Ring Base Low
//   0x4C - RX_DESC_HI:    RX Descriptor Ring Base High
//   0x50 - RX_RING_SIZE:  RX Ring Size (number of descriptors)
//   0x54 - RX_HEAD_PTR:   RX Head Pointer (RO)
//   0x58 - RX_TAIL_PTR:   RX Tail Pointer (RW)
//   0x5C - RX_PKT_CNT:    RX Packet Counter (RO)
//
//   0x80 - INT_STATUS:    DMA Interrupt Status (RW1C)
//   0x84 - INT_MASK:      DMA Interrupt Mask
//   0x88 - INT_COALESCE:  Interrupt Coalescing Config
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`include "dma_pkg.v"

module dma_regs #(
    parameter ADDR_WIDTH = 64           // System address width
)(
    // Clock and Reset
    input  wire                     clk,
    input  wire                     rst_n,
    
    //--------------------------------------------------------------------------
    // AXI4-Lite Slave Interface
    //--------------------------------------------------------------------------
    // Write Address Channel
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,
    input  wire [7:0]               s_axi_awaddr,   // 8-bit offset within DMA space
    
    // Write Data Channel
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,
    input  wire [31:0]              s_axi_wdata,
    input  wire [3:0]               s_axi_wstrb,
    
    // Write Response Channel
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,
    output wire [1:0]               s_axi_bresp,
    
    // Read Address Channel
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,
    input  wire [7:0]               s_axi_araddr,
    
    // Read Data Channel
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,
    output reg  [31:0]              s_axi_rdata,
    output wire [1:0]               s_axi_rresp,
    
    //--------------------------------------------------------------------------
    // TX DMA Control Outputs
    //--------------------------------------------------------------------------
    output reg                      tx_enable,
    output reg                      tx_reset,
    output reg                      tx_irq_en,
    output reg  [ADDR_WIDTH-1:0]    tx_ring_base,
    output reg  [15:0]              tx_ring_size,
    output reg  [15:0]              tx_head_ptr,
    
    // TX DMA Status Inputs
    input  wire                     tx_busy,
    input  wire                     tx_halted,
    input  wire                     tx_error,
    input  wire [15:0]              tx_tail_ptr,
    input  wire [31:0]              tx_pkt_cnt,
    
    //--------------------------------------------------------------------------
    // RX DMA Control Outputs
    //--------------------------------------------------------------------------
    output reg                      rx_enable,
    output reg                      rx_reset,
    output reg                      rx_irq_en,
    output reg  [ADDR_WIDTH-1:0]    rx_ring_base,
    output reg  [15:0]              rx_ring_size,
    output reg  [15:0]              rx_tail_ptr,
    
    // RX DMA Status Inputs
    input  wire                     rx_busy,
    input  wire                     rx_halted,
    input  wire                     rx_error,
    input  wire [15:0]              rx_head_ptr,
    input  wire [31:0]              rx_pkt_cnt,
    
    //--------------------------------------------------------------------------
    // Interrupt Interface
    //--------------------------------------------------------------------------
    // Raw interrupt sources
    input  wire                     int_tx_done,
    input  wire                     int_tx_err,
    input  wire                     int_rx_done,
    input  wire                     int_rx_err,
    input  wire                     int_desc_err,
    
    // Interrupt output
    output wire                     dma_irq
);

    //--------------------------------------------------------------------------
    // Constants
    //--------------------------------------------------------------------------
    assign s_axi_bresp = 2'b00;  // OKAY
    assign s_axi_rresp = 2'b00;  // OKAY

    //--------------------------------------------------------------------------
    // Register Addresses (relative to DMA base)
    //--------------------------------------------------------------------------
    localparam [7:0]
        REG_TX_CTRL      = 8'h00,
        REG_TX_STATUS    = 8'h04,
        REG_TX_DESC_LO   = 8'h08,
        REG_TX_DESC_HI   = 8'h0C,
        REG_TX_RING_SIZE = 8'h10,
        REG_TX_HEAD_PTR  = 8'h14,
        REG_TX_TAIL_PTR  = 8'h18,
        REG_TX_PKT_CNT   = 8'h1C,
        
        REG_RX_CTRL      = 8'h40,
        REG_RX_STATUS    = 8'h44,
        REG_RX_DESC_LO   = 8'h48,
        REG_RX_DESC_HI   = 8'h4C,
        REG_RX_RING_SIZE = 8'h50,
        REG_RX_HEAD_PTR  = 8'h54,
        REG_RX_TAIL_PTR  = 8'h58,
        REG_RX_PKT_CNT   = 8'h5C,
        
        REG_INT_STATUS   = 8'h80,
        REG_INT_MASK     = 8'h84,
        REG_INT_COALESCE = 8'h88;

    //--------------------------------------------------------------------------
    // Interrupt Registers
    //--------------------------------------------------------------------------
    reg [4:0] int_status;
    reg [4:0] int_mask;
    reg [15:0] int_coalesce_cnt;    // Packet count threshold
    reg [15:0] int_coalesce_time;   // Time threshold
    
    // Edge detection for interrupt sources
    reg int_tx_done_d, int_tx_err_d, int_rx_done_d, int_rx_err_d, int_desc_err_d;
    wire int_tx_done_edge = int_tx_done && !int_tx_done_d;
    wire int_tx_err_edge  = int_tx_err  && !int_tx_err_d;
    wire int_rx_done_edge = int_rx_done && !int_rx_done_d;
    wire int_rx_err_edge  = int_rx_err  && !int_rx_err_d;
    wire int_desc_err_edge = int_desc_err && !int_desc_err_d;
    
    // Masked interrupt output
    assign dma_irq = |(int_status & int_mask);

    //--------------------------------------------------------------------------
    // AXI Write State Machine
    //--------------------------------------------------------------------------
    reg [7:0] aw_addr_latched;
    reg aw_en;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            aw_addr_latched <= 8'd0;
            aw_en <= 1'b1;
            
        end else begin
            // Address ready
            if (!s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_awready <= 1'b1;
                aw_addr_latched <= s_axi_awaddr;
            end else begin
                s_axi_awready <= 1'b0;
            end
            
            // Data ready
            if (!s_axi_wready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_wready <= 1'b1;
            end else begin
                s_axi_wready <= 1'b0;
            end
            
            // Write response
            if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
                aw_en <= 1'b0;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
                aw_en <= 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Register Write Logic
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // TX DMA defaults
            tx_enable    <= 1'b0;
            tx_reset     <= 1'b0;
            tx_irq_en    <= 1'b0;
            tx_ring_base <= {ADDR_WIDTH{1'b0}};
            tx_ring_size <= 16'd256;
            tx_head_ptr  <= 16'd0;
            
            // RX DMA defaults
            rx_enable    <= 1'b0;
            rx_reset     <= 1'b0;
            rx_irq_en    <= 1'b0;
            rx_ring_base <= {ADDR_WIDTH{1'b0}};
            rx_ring_size <= 16'd256;
            rx_tail_ptr  <= 16'd0;
            
            // Interrupt defaults
            int_status   <= 5'd0;
            int_mask     <= 5'd0;
            int_coalesce_cnt  <= 16'd1;
            int_coalesce_time <= 16'd0;
            
            // Edge detect
            int_tx_done_d  <= 1'b0;
            int_tx_err_d   <= 1'b0;
            int_rx_done_d  <= 1'b0;
            int_rx_err_d   <= 1'b0;
            int_desc_err_d <= 1'b0;
            
        end else begin
            // Auto-clear reset bits
            tx_reset <= 1'b0;
            rx_reset <= 1'b0;
            
            // Edge detection registers
            int_tx_done_d  <= int_tx_done;
            int_tx_err_d   <= int_tx_err;
            int_rx_done_d  <= int_rx_done;
            int_rx_err_d   <= int_rx_err;
            int_desc_err_d <= int_desc_err;
            
            // Set interrupt status on rising edge
            if (int_tx_done_edge) int_status[0] <= 1'b1;
            if (int_tx_err_edge)  int_status[1] <= 1'b1;
            if (int_rx_done_edge) int_status[2] <= 1'b1;
            if (int_rx_err_edge)  int_status[3] <= 1'b1;
            if (int_desc_err_edge) int_status[4] <= 1'b1;
            
            // Register writes
            if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid) begin
                case (aw_addr_latched)
                    REG_TX_CTRL: begin
                        if (s_axi_wstrb[0]) begin
                            tx_enable <= s_axi_wdata[0];
                            tx_reset  <= s_axi_wdata[1];
                            tx_irq_en <= s_axi_wdata[2];
                        end
                    end
                    
                    REG_TX_DESC_LO: begin
                        if (s_axi_wstrb[0]) tx_ring_base[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) tx_ring_base[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) tx_ring_base[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) tx_ring_base[31:24] <= s_axi_wdata[31:24];
                    end
                    
                    REG_TX_DESC_HI: begin
                        if (ADDR_WIDTH > 32) begin
                            if (s_axi_wstrb[0]) tx_ring_base[39:32] <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) tx_ring_base[47:40] <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) tx_ring_base[55:48] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) tx_ring_base[63:56] <= s_axi_wdata[31:24];
                        end
                    end
                    
                    REG_TX_RING_SIZE: begin
                        if (s_axi_wstrb[0]) tx_ring_size[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) tx_ring_size[15:8] <= s_axi_wdata[15:8];
                    end
                    
                    REG_TX_HEAD_PTR: begin
                        if (s_axi_wstrb[0]) tx_head_ptr[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) tx_head_ptr[15:8] <= s_axi_wdata[15:8];
                    end
                    
                    REG_RX_CTRL: begin
                        if (s_axi_wstrb[0]) begin
                            rx_enable <= s_axi_wdata[0];
                            rx_reset  <= s_axi_wdata[1];
                            rx_irq_en <= s_axi_wdata[2];
                        end
                    end
                    
                    REG_RX_DESC_LO: begin
                        if (s_axi_wstrb[0]) rx_ring_base[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) rx_ring_base[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) rx_ring_base[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) rx_ring_base[31:24] <= s_axi_wdata[31:24];
                    end
                    
                    REG_RX_DESC_HI: begin
                        if (ADDR_WIDTH > 32) begin
                            if (s_axi_wstrb[0]) rx_ring_base[39:32] <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) rx_ring_base[47:40] <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) rx_ring_base[55:48] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) rx_ring_base[63:56] <= s_axi_wdata[31:24];
                        end
                    end
                    
                    REG_RX_RING_SIZE: begin
                        if (s_axi_wstrb[0]) rx_ring_size[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) rx_ring_size[15:8] <= s_axi_wdata[15:8];
                    end
                    
                    REG_RX_TAIL_PTR: begin
                        if (s_axi_wstrb[0]) rx_tail_ptr[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) rx_tail_ptr[15:8] <= s_axi_wdata[15:8];
                    end
                    
                    REG_INT_STATUS: begin
                        // Write-1-to-clear
                        if (s_axi_wstrb[0]) int_status <= int_status & ~s_axi_wdata[4:0];
                    end
                    
                    REG_INT_MASK: begin
                        if (s_axi_wstrb[0]) int_mask <= s_axi_wdata[4:0];
                    end
                    
                    REG_INT_COALESCE: begin
                        if (s_axi_wstrb[0]) int_coalesce_cnt[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) int_coalesce_cnt[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) int_coalesce_time[7:0]  <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) int_coalesce_time[15:8] <= s_axi_wdata[31:24];
                    end
                    
                    default: ; // Ignore writes to undefined addresses
                endcase
            end
        end
    end

    //--------------------------------------------------------------------------
    // AXI Read State Machine
    //--------------------------------------------------------------------------
    reg ar_en;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            ar_en <= 1'b1;
            
        end else begin
            // Address ready
            if (!s_axi_arready && s_axi_arvalid && ar_en) begin
                s_axi_arready <= 1'b1;
            end else begin
                s_axi_arready <= 1'b0;
            end
            
            // Read data
            if (s_axi_arready && s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                ar_en <= 1'b0;
                
                case (s_axi_araddr)
                    REG_TX_CTRL:      s_axi_rdata <= {29'd0, tx_irq_en, tx_reset, tx_enable};
                    REG_TX_STATUS:    s_axi_rdata <= {29'd0, tx_error, tx_halted, tx_busy};
                    REG_TX_DESC_LO:   s_axi_rdata <= tx_ring_base[31:0];
                    REG_TX_DESC_HI:   s_axi_rdata <= (ADDR_WIDTH > 32) ? tx_ring_base[63:32] : 32'd0;
                    REG_TX_RING_SIZE: s_axi_rdata <= {16'd0, tx_ring_size};
                    REG_TX_HEAD_PTR:  s_axi_rdata <= {16'd0, tx_head_ptr};
                    REG_TX_TAIL_PTR:  s_axi_rdata <= {16'd0, tx_tail_ptr};
                    REG_TX_PKT_CNT:   s_axi_rdata <= tx_pkt_cnt;
                    
                    REG_RX_CTRL:      s_axi_rdata <= {29'd0, rx_irq_en, rx_reset, rx_enable};
                    REG_RX_STATUS:    s_axi_rdata <= {29'd0, rx_error, rx_halted, rx_busy};
                    REG_RX_DESC_LO:   s_axi_rdata <= rx_ring_base[31:0];
                    REG_RX_DESC_HI:   s_axi_rdata <= (ADDR_WIDTH > 32) ? rx_ring_base[63:32] : 32'd0;
                    REG_RX_RING_SIZE: s_axi_rdata <= {16'd0, rx_ring_size};
                    REG_RX_HEAD_PTR:  s_axi_rdata <= {16'd0, rx_head_ptr};
                    REG_RX_TAIL_PTR:  s_axi_rdata <= {16'd0, rx_tail_ptr};
                    REG_RX_PKT_CNT:   s_axi_rdata <= rx_pkt_cnt;
                    
                    REG_INT_STATUS:   s_axi_rdata <= {27'd0, int_status};
                    REG_INT_MASK:     s_axi_rdata <= {27'd0, int_mask};
                    REG_INT_COALESCE: s_axi_rdata <= {int_coalesce_time, int_coalesce_cnt};
                    
                    default: s_axi_rdata <= 32'hDEAD_BEEF;  // Debug: undefined register
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
                ar_en <= 1'b1;
            end
        end
    end

endmodule
