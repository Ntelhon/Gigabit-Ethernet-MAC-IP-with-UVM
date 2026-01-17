//==============================================================================
// File: eth_controller_regs.v
// Description: Unified Register Block for Ethernet Controller
//
// Purpose:
//   Provides a single AXI4-Lite slave interface for the entire Ethernet
//   controller (MAC + optional DMA). Handles address decode and routes
//   transactions to the appropriate sub-block.
//
// Address Map:
//   0x000 - 0x1FF: MAC Registers (forwarded to mac_regs)
//   0x200 - 0x3FF: DMA Registers (forwarded to dma_regs, if DMA_ENABLE=1)
//
// When DMA_ENABLE=0, accesses to 0x200+ return DECERR.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_controller_regs #(
    parameter DMA_ENABLE = 1,           // Enable DMA subsystem
    parameter ADDR_WIDTH = 10           // Address width (10 bits for 0x000-0x3FF)
)(
    // Clock and Reset
    input  wire                     clk,
    input  wire                     rst_n,
    
    //--------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (from host)
    //--------------------------------------------------------------------------
    // Write Address Channel
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [2:0]               s_axi_awprot,
    
    // Write Data Channel
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,
    input  wire [31:0]              s_axi_wdata,
    input  wire [3:0]               s_axi_wstrb,
    
    // Write Response Channel
    output wire                     s_axi_bvalid,
    input  wire                     s_axi_bready,
    output wire [1:0]               s_axi_bresp,
    
    // Read Address Channel
    input  wire                     s_axi_arvalid,
    output wire                     s_axi_arready,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [2:0]               s_axi_arprot,
    
    // Read Data Channel
    output wire                     s_axi_rvalid,
    input  wire                     s_axi_rready,
    output wire [31:0]              s_axi_rdata,
    output wire [1:0]               s_axi_rresp,
    
    //--------------------------------------------------------------------------
    // MAC Register Interface (to mac_regs)
    //--------------------------------------------------------------------------
    output wire                     mac_awvalid,
    input  wire                     mac_awready,
    output wire [7:0]               mac_awaddr,
    
    output wire                     mac_wvalid,
    input  wire                     mac_wready,
    output wire [31:0]              mac_wdata,
    output wire [3:0]               mac_wstrb,
    
    input  wire                     mac_bvalid,
    output wire                     mac_bready,
    input  wire [1:0]               mac_bresp,
    
    output wire                     mac_arvalid,
    input  wire                     mac_arready,
    output wire [7:0]               mac_araddr,
    
    input  wire                     mac_rvalid,
    output wire                     mac_rready,
    input  wire [31:0]              mac_rdata,
    input  wire [1:0]               mac_rresp,
    
    //--------------------------------------------------------------------------
    // DMA Register Interface (to dma_regs)
    //--------------------------------------------------------------------------
    output wire                     dma_awvalid,
    input  wire                     dma_awready,
    output wire [7:0]               dma_awaddr,
    
    output wire                     dma_wvalid,
    input  wire                     dma_wready,
    output wire [31:0]              dma_wdata,
    output wire [3:0]               dma_wstrb,
    
    input  wire                     dma_bvalid,
    output wire                     dma_bready,
    input  wire [1:0]               dma_bresp,
    
    output wire                     dma_arvalid,
    input  wire                     dma_arready,
    output wire [7:0]               dma_araddr,
    
    input  wire                     dma_rvalid,
    output wire                     dma_rready,
    input  wire [31:0]              dma_rdata,
    input  wire [1:0]               dma_rresp
);

    //--------------------------------------------------------------------------
    // Address Decode
    //--------------------------------------------------------------------------
    // Bit 9 selects MAC (0) vs DMA (1)
    wire write_to_dma = s_axi_awaddr[9];
    wire read_from_dma = s_axi_araddr[9];
    
    //--------------------------------------------------------------------------
    // Write Path
    //--------------------------------------------------------------------------
    reg aw_target;  // 0=MAC, 1=DMA
    reg aw_target_valid;
    reg aw_invalid; // Access to disabled DMA
    
    // Latch target on address phase
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_target <= 1'b0;
            aw_target_valid <= 1'b0;
            aw_invalid <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_target <= write_to_dma;
                aw_target_valid <= 1'b1;
                aw_invalid <= write_to_dma && !DMA_ENABLE;
            end else if (s_axi_bvalid && s_axi_bready) begin
                aw_target_valid <= 1'b0;
                aw_invalid <= 1'b0;
            end
        end
    end
    
    // Route write address
    assign mac_awvalid = s_axi_awvalid && !write_to_dma;
    assign dma_awvalid = s_axi_awvalid && write_to_dma && DMA_ENABLE;
    assign mac_awaddr  = s_axi_awaddr[7:0];
    assign dma_awaddr  = s_axi_awaddr[7:0];
    
    assign s_axi_awready = write_to_dma ? 
                           (DMA_ENABLE ? dma_awready : 1'b1) : 
                           mac_awready;
    
    // Route write data
    assign mac_wvalid = s_axi_wvalid && !aw_target && aw_target_valid;
    assign dma_wvalid = s_axi_wvalid && aw_target && aw_target_valid && DMA_ENABLE;
    assign mac_wdata  = s_axi_wdata;
    assign dma_wdata  = s_axi_wdata;
    assign mac_wstrb  = s_axi_wstrb;
    assign dma_wstrb  = s_axi_wstrb;
    
    assign s_axi_wready = aw_target ? 
                          (DMA_ENABLE ? dma_wready : 1'b1) : 
                          mac_wready;
    
    // Route write response
    assign mac_bready = s_axi_bready && !aw_target;
    assign dma_bready = s_axi_bready && aw_target && DMA_ENABLE;
    
    assign s_axi_bvalid = aw_invalid ? aw_target_valid : 
                          (aw_target ? dma_bvalid : mac_bvalid);
    assign s_axi_bresp  = aw_invalid ? 2'b11 :  // DECERR
                          (aw_target ? dma_bresp : mac_bresp);
    
    //--------------------------------------------------------------------------
    // Read Path
    //--------------------------------------------------------------------------
    reg ar_target;  // 0=MAC, 1=DMA
    reg ar_target_valid;
    reg ar_invalid;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_target <= 1'b0;
            ar_target_valid <= 1'b0;
            ar_invalid <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                ar_target <= read_from_dma;
                ar_target_valid <= 1'b1;
                ar_invalid <= read_from_dma && !DMA_ENABLE;
            end else if (s_axi_rvalid && s_axi_rready) begin
                ar_target_valid <= 1'b0;
                ar_invalid <= 1'b0;
            end
        end
    end
    
    // Route read address
    assign mac_arvalid = s_axi_arvalid && !read_from_dma;
    assign dma_arvalid = s_axi_arvalid && read_from_dma && DMA_ENABLE;
    assign mac_araddr  = s_axi_araddr[7:0];
    assign dma_araddr  = s_axi_araddr[7:0];
    
    assign s_axi_arready = read_from_dma ? 
                           (DMA_ENABLE ? dma_arready : 1'b1) : 
                           mac_arready;
    
    // Route read data
    assign mac_rready = s_axi_rready && !ar_target;
    assign dma_rready = s_axi_rready && ar_target && DMA_ENABLE;
    
    assign s_axi_rvalid = ar_invalid ? ar_target_valid :
                          (ar_target ? dma_rvalid : mac_rvalid);
    assign s_axi_rdata  = ar_invalid ? 32'hDEAD_BEEF :
                          (ar_target ? dma_rdata : mac_rdata);
    assign s_axi_rresp  = ar_invalid ? 2'b11 :  // DECERR
                          (ar_target ? dma_rresp : mac_rresp);

endmodule
