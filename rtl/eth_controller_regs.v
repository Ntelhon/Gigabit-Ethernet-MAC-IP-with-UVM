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
// When DMA_ENABLE=0, accesses to 0x200+ return SLVERR.
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
    output reg                      s_axi_awready,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [2:0]               s_axi_awprot,
    
    // Write Data Channel
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,
    input  wire [31:0]              s_axi_wdata,
    input  wire [3:0]               s_axi_wstrb,
    
    // Write Response Channel
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,
    output reg  [1:0]               s_axi_bresp,
    
    // Read Address Channel
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [2:0]               s_axi_arprot,
    
    // Read Data Channel
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,
    output reg  [31:0]              s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    
    //--------------------------------------------------------------------------
    // MAC Register Interface (to mac_regs)
    //--------------------------------------------------------------------------
    // Write Address Channel
    output reg                      mac_awvalid,
    input  wire                     mac_awready,
    output wire [7:0]               mac_awaddr,
    output wire [2:0]               mac_awprot,
    
    // Write Data Channel
    output reg                      mac_wvalid,
    input  wire                     mac_wready,
    output wire [31:0]              mac_wdata,
    output wire [3:0]               mac_wstrb,
    
    // Write Response Channel
    input  wire                     mac_bvalid,
    output reg                      mac_bready,
    input  wire [1:0]               mac_bresp,
    
    // Read Address Channel
    output reg                      mac_arvalid,
    input  wire                     mac_arready,
    output wire [7:0]               mac_araddr,
    output wire [2:0]               mac_arprot,
    
    // Read Data Channel
    input  wire                     mac_rvalid,
    output reg                      mac_rready,
    input  wire [31:0]              mac_rdata,
    input  wire [1:0]               mac_rresp,
    
    //--------------------------------------------------------------------------
    // DMA Register Interface (to dma_regs)
    //--------------------------------------------------------------------------
    // Write Address Channel
    output reg                      dma_awvalid,
    input  wire                     dma_awready,
    output wire [7:0]               dma_awaddr,
    output wire [2:0]               dma_awprot,
    
    // Write Data Channel
    output reg                      dma_wvalid,
    input  wire                     dma_wready,
    output wire [31:0]              dma_wdata,
    output wire [3:0]               dma_wstrb,

    // Write Response Channel
    input  wire                     dma_bvalid,
    output reg                      dma_bready,
    input  wire [1:0]               dma_bresp,
    
    // Read Address Channel
    output reg                      dma_arvalid,
    input  wire                     dma_arready,
    output wire [7:0]               dma_araddr,
    output wire [2:0]               dma_arprot,

    // Read Data Channel
    input  wire                     dma_rvalid,
    output reg                      dma_rready,
    input  wire [31:0]              dma_rdata,
    input  wire [1:0]               dma_rresp
);

    //--------------------------------------------------------------------------
    // Address Decode
    //--------------------------------------------------------------------------
    // Address space: bit[9] selects MAC (0) or DMA (1)
    // 0x000-0x1FF: MAC (bit[9] = 0)
    // 0x200-0x3FF: DMA (bit[9] = 1)
    
    localparam MAC_REGION = 1'b0;
    localparam DMA_REGION = 1'b1;
    
    // AXI Response codes
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;
    
    //--------------------------------------------------------------------------
    // Write Channel State Machine
    //--------------------------------------------------------------------------
    localparam [1:0] W_IDLE    = 2'd0,
                     W_MAC     = 2'd1,
                     W_DMA     = 2'd2,
                     W_ERROR   = 2'd3;
    
    reg [1:0] wr_state;
    reg [ADDR_WIDTH-1:0] wr_addr_latched;
    reg [2:0] wr_prot_latched;
    reg wr_addr_is_dma;
    
    //--------------------------------------------------------------------------
    // Read Channel State Machine
    //--------------------------------------------------------------------------
    localparam [1:0] R_IDLE    = 2'd0,
                     R_MAC     = 2'd1,
                     R_DMA     = 2'd2,
                     R_ERROR   = 2'd3;
    
    reg [1:0] rd_state;
    reg [ADDR_WIDTH-1:0] rd_addr_latched;
    reg [2:0] rd_prot_latched;
    reg rd_addr_is_dma;

    //--------------------------------------------------------------------------
    // Address and Control Passthrough
    //--------------------------------------------------------------------------
    assign mac_awaddr = wr_addr_latched[7:0];
    assign dma_awaddr = wr_addr_latched[7:0];
    assign mac_araddr = rd_addr_latched[7:0];
    assign dma_araddr = rd_addr_latched[7:0];
    
    assign mac_awprot = wr_prot_latched;
    assign dma_awprot = wr_prot_latched;
    assign mac_arprot = rd_prot_latched;
    assign dma_arprot = rd_prot_latched;
    
    // Data/Strobe passthrough
    assign mac_wdata = s_axi_wdata;
    assign mac_wstrb = s_axi_wstrb;
    assign dma_wdata = s_axi_wdata;
    assign dma_wstrb = s_axi_wstrb;

    //--------------------------------------------------------------------------
    // Write Transaction Handler
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= RESP_OKAY;
            mac_awvalid   <= 1'b0;
            mac_wvalid    <= 1'b0;
            mac_bready    <= 1'b0;
            dma_awvalid   <= 1'b0;
            dma_wvalid    <= 1'b0;
            dma_bready    <= 1'b0;
            wr_addr_latched <= {ADDR_WIDTH{1'b0}};
            wr_prot_latched <= 3'b000;
            wr_addr_is_dma  <= 1'b0;
            
        end else begin
            case (wr_state)
                //--------------------------------------------------------------
                // IDLE: Wait for write address
                //--------------------------------------------------------------
                W_IDLE: begin
                    s_axi_bvalid  <= 1'b0;
                    mac_awvalid   <= 1'b0;
                    mac_wvalid    <= 1'b0;
                    dma_awvalid   <= 1'b0;
                    dma_wvalid    <= 1'b0;
                    
                    if (s_axi_awvalid) begin
                        // Latch address and decode
                        wr_addr_latched <= s_axi_awaddr;
                        wr_prot_latched <= s_axi_awprot;
                        wr_addr_is_dma  <= s_axi_awaddr[9];
                        s_axi_awready   <= 1'b1;
                        
                        // Determine target
                        if (s_axi_awaddr[9] == MAC_REGION) begin
                            wr_state <= W_MAC;
                        end else if (DMA_ENABLE && s_axi_awaddr[9] == DMA_REGION) begin
                            wr_state <= W_DMA;
                        end else begin
                            wr_state <= W_ERROR;
                        end
                    end else begin
                        s_axi_awready <= 1'b0;
                    end
                end
                
                //--------------------------------------------------------------
                // W_MAC: Forward to MAC
                //--------------------------------------------------------------
                W_MAC: begin
                    s_axi_awready <= 1'b0;
                    
                    // Forward address (single cycle pulse)
                    if (!mac_awvalid) begin
                        mac_awvalid <= 1'b1;
                    end else if (mac_awready) begin
                        mac_awvalid <= 1'b0;
                    end
                    
                    // Forward data when both awready received and wvalid arrives
                    if (s_axi_wvalid && !mac_wvalid) begin
                        mac_wvalid   <= 1'b1;
                        s_axi_wready <= 1'b1;
                    end else if (mac_wready) begin
                        mac_wvalid   <= 1'b0;
                        s_axi_wready <= 1'b0;
                    end else begin
                        s_axi_wready <= 1'b0;
                    end
                    
                    // Wait for response from MAC
                    if (!s_axi_bvalid) begin
                        mac_bready <= 1'b1;
                        
                        if (mac_bvalid && mac_bready) begin
                            mac_bready   <= 1'b0;
                            s_axi_bvalid <= 1'b1;
                            s_axi_bresp  <= mac_bresp;
                        end
                    end else begin
                        mac_bready <= 1'b0;
                    end
                    
                    // Complete when master accepts response
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state <= W_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                // W_DMA: Forward to DMA
                //--------------------------------------------------------------
                W_DMA: begin
                    s_axi_awready <= 1'b0;
                    
                    // Forward address
                    if (!dma_awvalid) begin
                        dma_awvalid <= 1'b1;
                    end else if (dma_awready) begin
                        dma_awvalid <= 1'b0;
                    end
                    
                    // Forward data
                    if (s_axi_wvalid && !dma_wvalid) begin
                        dma_wvalid   <= 1'b1;
                        s_axi_wready <= 1'b1;
                    end else if (dma_wready) begin
                        dma_wvalid   <= 1'b0;
                        s_axi_wready <= 1'b0;
                    end else begin
                        s_axi_wready <= 1'b0;
                    end
                    
                    // Wait for response from DMA
                    if (!s_axi_bvalid) begin
                        dma_bready <= 1'b1;
                        
                        if (dma_bvalid && dma_bready) begin
                            dma_bready   <= 1'b0;
                            s_axi_bvalid <= 1'b1;
                            s_axi_bresp  <= dma_bresp;
                        end
                    end else begin
                        dma_bready <= 1'b0;
                    end
                    
                    // Complete when master accepts response
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state <= W_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                // W_ERROR: Return error response
                //--------------------------------------------------------------
                W_ERROR: begin
                    s_axi_awready <= 1'b0;
                    
                    // Consume write data (must accept to complete transaction)
                    if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b1;
                    end else begin
                        s_axi_wready <= 1'b0;
                    end
                    
                    // Send error response after consuming data
                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= RESP_SLVERR;
                    end
                    
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        s_axi_wready <= 1'b0;
                        wr_state <= W_IDLE;
                    end
                end
                
                default: wr_state <= W_IDLE;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Read Transaction Handler
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= R_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= RESP_OKAY;
            mac_arvalid   <= 1'b0;
            mac_rready    <= 1'b0;
            dma_arvalid   <= 1'b0;
            dma_rready    <= 1'b0;
            rd_addr_latched <= {ADDR_WIDTH{1'b0}};
            rd_prot_latched <= 3'b000;
            rd_addr_is_dma  <= 1'b0;
            
        end else begin
            case (rd_state)
                //--------------------------------------------------------------
                // IDLE: Wait for read address
                //--------------------------------------------------------------
                R_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    mac_arvalid  <= 1'b0;
                    dma_arvalid  <= 1'b0;
                    
                    if (s_axi_arvalid) begin
                        // Latch address and decode
                        rd_addr_latched <= s_axi_araddr;
                        rd_prot_latched <= s_axi_arprot;
                        rd_addr_is_dma  <= s_axi_araddr[9];
                        s_axi_arready   <= 1'b1;
                        
                        // Determine target
                        if (s_axi_araddr[9] == MAC_REGION) begin
                            rd_state <= R_MAC;
                        end else if (DMA_ENABLE && s_axi_araddr[9] == DMA_REGION) begin
                            rd_state <= R_DMA;
                        end else begin
                            rd_state <= R_ERROR;
                        end
                    end else begin
                        s_axi_arready <= 1'b0;
                    end
                end
                
                //--------------------------------------------------------------
                // R_MAC: Forward to MAC
                //--------------------------------------------------------------
                R_MAC: begin
                    s_axi_arready <= 1'b0;
                    
                    // Forward address
                    if (!mac_arvalid) begin
                        mac_arvalid <= 1'b1;
                    end else if (mac_arready) begin
                        mac_arvalid <= 1'b0;
                    end
                    
                    // Wait for read data from MAC
                    if (!s_axi_rvalid) begin
                        mac_rready <= 1'b1;
                        
                        if (mac_rvalid && mac_rready) begin
                            mac_rready   <= 1'b0;
                            s_axi_rvalid <= 1'b1;
                            s_axi_rdata  <= mac_rdata;
                            s_axi_rresp  <= mac_rresp;
                        end
                    end else begin
                        mac_rready <= 1'b0;
                    end
                    
                    // Complete when master accepts data
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rd_state <= R_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                // R_DMA: Forward to DMA
                //--------------------------------------------------------------
                R_DMA: begin
                    s_axi_arready <= 1'b0;
                    
                    // Forward address
                    if (!dma_arvalid) begin
                        dma_arvalid <= 1'b1;
                    end else if (dma_arready) begin
                        dma_arvalid <= 1'b0;
                    end
                    
                    // Wait for read data from DMA
                    if (!s_axi_rvalid) begin
                        dma_rready <= 1'b1;
                        
                        if (dma_rvalid && dma_rready) begin
                            dma_rready   <= 1'b0;
                            s_axi_rvalid <= 1'b1;
                            s_axi_rdata  <= dma_rdata;
                            s_axi_rresp  <= dma_rresp;
                        end
                    end else begin
                        dma_rready <= 1'b0;
                    end
                    
                    // Complete when master accepts data
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rd_state <= R_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                // R_ERROR: Return error response
                //--------------------------------------------------------------
                R_ERROR: begin
                    s_axi_arready <= 1'b0;
                    
                    if (!s_axi_rvalid) begin
                        s_axi_rvalid <= 1'b1;
                        s_axi_rdata  <= 32'hDEADBEEF;
                        s_axi_rresp  <= RESP_SLVERR;
                    end
                    
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rd_state <= R_IDLE;
                    end
                end
                
                default: rd_state <= R_IDLE;
            endcase
        end
    end

endmodule
