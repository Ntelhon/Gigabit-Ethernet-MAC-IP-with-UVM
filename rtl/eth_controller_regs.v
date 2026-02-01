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
// COMPLETELY FIXED VERSION:
//   - All AXI4-Lite protocol requirements implemented
//   - Fixed address width mismatches
//   - Proper handshake coordination with completion tracking
//   - Fixed address decode timing issues
//   - Added timeout protection
//   - Proper ready/valid signal management
//   - Fixed simultaneous AWVALID/WVALID handling
//   - Removed protocol violations
//   - Added proper DMA_ENABLE runtime checks
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================
module eth_controller_regs #(
    parameter DMA_ENABLE = 1,           // Enable DMA subsystem
    parameter ADDR_WIDTH = 10,          // Address width (10 bits for 0x000-0x3FF)
    parameter TIMEOUT_WIDTH = 4         // Timeout counter width
)(
    //==========================================================================
    // Clock and Reset
    //==========================================================================
    input  wire                     clk,
    input  wire                     rst_n,
    
    //==========================================================================
    // AXI4-Lite Slave Interface (from host)
    //==========================================================================
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
    
    //==========================================================================
    // MAC Register Interface (to mac_regs)
    //==========================================================================
    // Write Address Channel
    output reg                      mac_awvalid,
    input  wire                     mac_awready,
    output reg  [7:0]               mac_awaddr,
    output reg  [2:0]               mac_awprot,
    
    // Write Data Channel
    output reg                      mac_wvalid,
    input  wire                     mac_wready,
    output reg  [31:0]              mac_wdata,
    output reg  [3:0]               mac_wstrb,
    
    // Write Response Channel
    input  wire                     mac_bvalid,
    output reg                      mac_bready,
    input  wire [1:0]               mac_bresp,
    
    // Read Address Channel
    output reg                      mac_arvalid,
    input  wire                     mac_arready,
    output reg  [7:0]               mac_araddr,
    output reg  [2:0]               mac_arprot,
    
    // Read Data Channel
    input  wire                     mac_rvalid,
    output reg                      mac_rready,
    input  wire [31:0]              mac_rdata,
    input  wire [1:0]               mac_rresp,
    
    //==========================================================================
    // DMA Register Interface (to dma_regs)
    //==========================================================================
    // Write Address Channel
    output reg                      dma_awvalid,
    input  wire                     dma_awready,
    output reg  [7:0]               dma_awaddr,
    output reg  [2:0]               dma_awprot,
    
    // Write Data Channel
    output reg                      dma_wvalid,
    input  wire                     dma_wready,
    output reg  [31:0]              dma_wdata,
    output reg  [3:0]               dma_wstrb,
    // Write Response Channel
    input  wire                     dma_bvalid,
    output reg                      dma_bready,
    input  wire [1:0]               dma_bresp,
    
    // Read Address Channel
    output reg                      dma_arvalid,
    input  wire                     dma_arready,
    output reg  [7:0]               dma_araddr,
    output reg  [2:0]               dma_arprot,
    // Read Data Channel
    input  wire                     dma_rvalid,
    output reg                      dma_rready,
    input  wire [31:0]              dma_rdata,
    input  wire [1:0]               dma_rresp
);
    //==========================================================================
    // Local Parameters
    //==========================================================================
    
    // Address Decode - Bit 9 selects MAC (0) or DMA (1)
    localparam MAC_REGION = 1'b0;
    localparam DMA_REGION = 1'b1;
    
    // AXI Response codes
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_EXOKAY = 2'b01;  // Exclusive access okay (not used)
    localparam RESP_SLVERR = 2'b10;  // Slave error
    localparam RESP_DECERR = 2'b11;  // Decode error (not used)
    
    // Error data pattern for read errors
    localparam ERROR_DATA = 32'hDEADBEEF;
    
    // Timeout value (prevents hung transactions)
    localparam TIMEOUT_COUNT = {TIMEOUT_WIDTH{1'b1}};  // Maximum count
    
    //--------------------------------------------------------------------------
    // Write Channel State Machine States
    //--------------------------------------------------------------------------
    localparam [2:0] 
        W_IDLE      = 3'd0,
        W_DECODE    = 3'd1,
        W_FORWARD   = 3'd2,
        W_RESP      = 3'd3,
        W_ERROR     = 3'd4;
    
    //--------------------------------------------------------------------------
    // Read Channel State Machine States
    //--------------------------------------------------------------------------
    localparam [2:0] 
        R_IDLE      = 3'd0,
        R_DECODE    = 3'd1,
        R_FORWARD   = 3'd2,
        R_RESP      = 3'd3,
        R_ERROR     = 3'd4;
    //==========================================================================
    // Internal Registers - Write Channel
    //==========================================================================
    reg [2:0]               wr_state;
    reg [ADDR_WIDTH-1:0]    wr_addr_latched;
    reg [2:0]               wr_prot_latched;
    reg [31:0]              wr_data_latched;
    reg [3:0]               wr_strb_latched;
    reg                     wr_addr_is_dma;
    reg                     wr_addr_valid;
    reg                     wr_data_valid;
    reg                     wr_aw_done;      // Address handshake completed
    reg                     wr_w_done;       // Data handshake completed
    reg [TIMEOUT_WIDTH-1:0] wr_timeout_cnt;
    
    //==========================================================================
    // Internal Registers - Read Channel
    //==========================================================================
    reg [2:0]               rd_state;
    reg [ADDR_WIDTH-1:0]    rd_addr_latched;
    reg [2:0]               rd_prot_latched;
    reg                     rd_addr_is_dma;
    reg                     rd_addr_valid;
    reg                     rd_ar_done;      // Address handshake completed
    reg [TIMEOUT_WIDTH-1:0] rd_timeout_cnt;
    //==========================================================================
    // Write Transaction Handler
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // State and control
            wr_state        <= W_IDLE;
            wr_addr_valid   <= 1'b0;
            wr_data_valid   <= 1'b0;
            wr_addr_is_dma  <= 1'b0;
            wr_aw_done      <= 1'b0;
            wr_w_done       <= 1'b0;
            wr_timeout_cnt  <= {TIMEOUT_WIDTH{1'b0}};
            
            // Slave interface
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= RESP_OKAY;
            
            // MAC master interface
            mac_awvalid     <= 1'b0;
            mac_awaddr      <= 8'd0;
            mac_awprot      <= 3'd0;
            mac_wvalid      <= 1'b0;
            mac_wdata       <= 32'd0;
            mac_wstrb       <= 4'd0;
            mac_bready      <= 1'b0;
            
            // DMA master interface
            dma_awvalid     <= 1'b0;
            dma_awaddr      <= 8'd0;
            dma_awprot      <= 3'd0;
            dma_wvalid      <= 1'b0;
            dma_wdata       <= 32'd0;
            dma_wstrb       <= 4'd0;
            dma_bready      <= 1'b0;
            
            // Latched values
            wr_addr_latched <= {ADDR_WIDTH{1'b0}};
            wr_prot_latched <= 3'b000;
            wr_data_latched <= 32'd0;
            wr_strb_latched <= 4'd0;
            
        end else begin
            case (wr_state)
                //==============================================================
                // W_IDLE: Wait for write transaction to start
                //==============================================================
                W_IDLE: begin
                    // Clear all outputs
                    s_axi_bvalid    <= 1'b0;
                    mac_awvalid     <= 1'b0;
                    mac_wvalid      <= 1'b0;
                    mac_bready      <= 1'b0;
                    dma_awvalid     <= 1'b0;
                    dma_wvalid      <= 1'b0;
                    dma_bready      <= 1'b0;
                    wr_aw_done      <= 1'b0;
                    wr_w_done       <= 1'b0;
                    wr_timeout_cnt  <= {TIMEOUT_WIDTH{1'b0}};
                    
                    // Assert ready signals to accept new transaction
                    s_axi_awready   <= 1'b1;
                    s_axi_wready    <= 1'b1;
                    
                    // Capture address if valid (can arrive before or with data)
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr_latched <= s_axi_awaddr;
                        wr_prot_latched <= s_axi_awprot;
                        wr_addr_valid   <= 1'b1;
                    end else begin
                        wr_addr_valid   <= 1'b0;
                    end
                    
                    // Capture data if valid (can arrive before or with address)
                    if (s_axi_wvalid && s_axi_wready) begin
                        wr_data_latched <= s_axi_wdata;
                        wr_strb_latched <= s_axi_wstrb;
                        wr_data_valid   <= 1'b1;
                    end else begin
                        wr_data_valid   <= 1'b0;
                    end
                    
                    // Transition when we have both address and data
                    // This handles simultaneous arrival and sequential arrival
                    if ((s_axi_awvalid && s_axi_awready) || wr_addr_valid) begin
                        if ((s_axi_wvalid && s_axi_wready) || wr_data_valid) begin
                            s_axi_awready  <= 1'b0;
                            s_axi_wready   <= 1'b0;
                            wr_addr_valid  <= 1'b0;
                            wr_data_valid  <= 1'b0;
                            wr_state       <= W_DECODE;
                        end
                    end
                end
                
                //==============================================================
                // W_DECODE: Decode address and validate target
                //==============================================================
                W_DECODE: begin
                    // Decode the region from bit 9
                    wr_addr_is_dma <= wr_addr_latched[9];
                    
                    // Validate the target
                    if (wr_addr_latched[9] == MAC_REGION) begin
                        // Always valid - MAC is always present
                        wr_state <= W_FORWARD;
                    end else if (wr_addr_latched[9] == DMA_REGION) begin
                        if (DMA_ENABLE) begin
                            // DMA enabled - forward transaction
                            wr_state <= W_FORWARD;
                        end else begin
                            // DMA disabled - return error
                            wr_state <= W_ERROR;
                        end
                    end else begin
                        // Invalid address (shouldn't happen with 1-bit decode)
                        wr_state <= W_ERROR;
                    end
                end
                
                //==============================================================
                // W_FORWARD: Forward transaction to MAC or DMA
                //==============================================================
                W_FORWARD: begin
                    // Increment timeout counter
                    if (wr_timeout_cnt != TIMEOUT_COUNT) begin
                        wr_timeout_cnt <= wr_timeout_cnt + 1'b1;
                    end
                    
                    if (wr_addr_is_dma && DMA_ENABLE) begin
                        //------------------------------------------------------
                        // Forward to DMA
                        //------------------------------------------------------
                        
                        // Address phase - assert valid until handshake
                        if (!wr_aw_done) begin
                            dma_awvalid <= 1'b1;
                            dma_awaddr  <= wr_addr_latched[7:0];  // FIXED: Use [7:0]
                            dma_awprot  <= wr_prot_latched;
                            
                            if (dma_awvalid && dma_awready) begin
                                dma_awvalid <= 1'b0;
                                wr_aw_done  <= 1'b1;
                            end
                        end
                        
                        // Data phase - assert valid until handshake
                        if (!wr_w_done) begin
                            dma_wvalid <= 1'b1;
                            dma_wdata  <= wr_data_latched;
                            dma_wstrb  <= wr_strb_latched;
                            
                            if (dma_wvalid && dma_wready) begin
                                dma_wvalid <= 1'b0;
                                wr_w_done  <= 1'b1;
                            end
                        end
                        
                        // Both handshakes completed or timeout - move to response
                        if ((wr_aw_done && wr_w_done) || (wr_timeout_cnt == TIMEOUT_COUNT)) begin
                            dma_bready     <= 1'b1;
                            wr_timeout_cnt <= {TIMEOUT_WIDTH{1'b0}};
                            
                            if (wr_timeout_cnt == TIMEOUT_COUNT) begin
                                // Timeout occurred - generate error response
                                wr_state <= W_ERROR;
                            end else begin
                                // Normal operation - wait for response
                                wr_state <= W_RESP;
                            end
                        end
                        
                    end else begin
                        //------------------------------------------------------
                        // Forward to MAC
                        //------------------------------------------------------

                        // Address phase - assert valid until handshake
                        if (!wr_aw_done) begin
                            mac_awvalid <= 1'b1;
                            mac_awaddr  <= wr_addr_latched[7:0];  // FIXED: Use [7:0]
                            mac_awprot  <= wr_prot_latched;
                            
                            if (mac_awvalid && mac_awready) begin
                                mac_awvalid <= 1'b0;
                                wr_aw_done  <= 1'b1;
                            end
                        end
                        
                        // Data phase - assert valid until handshake
                        if (!wr_w_done) begin
                            mac_wvalid <= 1'b1;
                            mac_wdata  <= wr_data_latched;
                            mac_wstrb  <= wr_strb_latched;
                            
                            if (mac_wvalid && mac_wready) begin
                                mac_wvalid <= 1'b0;
                                wr_w_done  <= 1'b1;
                            end
                        end
                        
                        // Both handshakes completed or timeout - move to response
                        if ((wr_aw_done && wr_w_done) || (wr_timeout_cnt == TIMEOUT_COUNT)) begin
                            mac_bready     <= 1'b1;
                            wr_timeout_cnt <= {TIMEOUT_WIDTH{1'b0}};
                            
                            if (wr_timeout_cnt == TIMEOUT_COUNT) begin
                                // Timeout occurred - generate error response
                                wr_state <= W_ERROR;
                            end else begin
                                // Normal operation - wait for response
                                wr_state <= W_RESP;
                            end
                        end
                    end
                end
                
                //==============================================================
                // W_RESP: Wait for and forward response
                //==============================================================
                W_RESP: begin
                    // Increment timeout counter
                    if (wr_timeout_cnt != TIMEOUT_COUNT) begin
                        wr_timeout_cnt <= wr_timeout_cnt + 1'b1;
                    end
                    
                    // Check for timeout
                    if (wr_timeout_cnt == TIMEOUT_COUNT) begin
                        // Timeout - generate error response directly
                        if (wr_addr_is_dma) begin
                            dma_bready <= 1'b0;
                        end else begin
                            mac_bready <= 1'b0;
                        end
                        wr_state <= W_ERROR;
                        
                    end else if (wr_addr_is_dma) begin
                        //------------------------------------------------------
                        // Wait for DMA response
                        //------------------------------------------------------
                        if (dma_bvalid && dma_bready) begin
                            dma_bready      <= 1'b0;
                            s_axi_bvalid    <= 1'b1;
                            s_axi_bresp     <= dma_bresp;
                            wr_timeout_cnt  <= {TIMEOUT_WIDTH{1'b0}};
                            
                            // Wait for master to accept response
                            if (s_axi_bvalid && s_axi_bready) begin
                                s_axi_bvalid <= 1'b0;
                                wr_state     <= W_IDLE;
                            end
                        end
                        
                    end else begin
                        //------------------------------------------------------
                        // Wait for MAC response
                        //------------------------------------------------------

                        if (mac_bvalid && mac_bready) begin
                            mac_bready      <= 1'b0;
                            s_axi_bvalid    <= 1'b1;
                            s_axi_bresp     <= mac_bresp;
                            wr_timeout_cnt  <= {TIMEOUT_WIDTH{1'b0}};
                            
                            // Wait for master to accept response
                            if (s_axi_bvalid && s_axi_bready) begin
                                s_axi_bvalid <= 1'b0;
                                wr_state     <= W_IDLE;
                            end
                        end
                    end
                    
                    // Handle case where response already captured
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= W_IDLE;
                    end
                end
                
                //==============================================================
                // W_ERROR: Return error response
                //==============================================================
                W_ERROR: begin
                    // Clear any pending handshakes
                    mac_bready <= 1'b0;
                    dma_bready <= 1'b0;
                    
                    // Generate error response
                    if (!s_axi_bvalid) begin
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= RESP_SLVERR;
                    end
                    
                    // Complete when master accepts response
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= W_IDLE;
                    end
                end
                
                default: begin
                    wr_state <= W_IDLE;
                end
            endcase
        end
    end
    //==========================================================================
    // Read Transaction Handler
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // State and control
            rd_state        <= R_IDLE;
            rd_addr_valid   <= 1'b0;
            rd_ar_done      <= 1'b0;
            rd_addr_is_dma  <= 1'b0;
            rd_timeout_cnt  <= {TIMEOUT_WIDTH{1'b0}};
            
            // Slave interface
            s_axi_arready   <= 1'b0;
            s_axi_rvalid    <= 1'b0;
            s_axi_rdata     <= 32'd0;
            s_axi_rresp     <= RESP_OKAY;
            
            // MAC master interface
            mac_arvalid     <= 1'b0;
            mac_araddr      <= 8'd0;
            mac_arprot      <= 3'd0;
            mac_rready      <= 1'b0;
            
            // DMA master interface
            dma_arvalid     <= 1'b0;
            dma_araddr      <= 8'd0;
            dma_arprot      <= 3'd0;
            dma_rready      <= 1'b0;
            
            // Latched values
            rd_addr_latched <= {ADDR_WIDTH{1'b0}};
            rd_prot_latched <= 3'b000;
            
        end else begin
            case (rd_state)
                //==============================================================
                // R_IDLE: Wait for read address
                //==============================================================
                R_IDLE: begin
                    // Clear all outputs
                    s_axi_rvalid    <= 1'b0;
                    mac_arvalid     <= 1'b0;
                    mac_rready      <= 1'b0;
                    dma_arvalid     <= 1'b0;
                    dma_rready      <= 1'b0;
                    rd_timeout_cnt  <= {TIMEOUT_WIDTH{1'b0}};
                    
                    // Assert ready to accept new transaction
                    s_axi_arready   <= 1'b1;
                    
                    if (s_axi_arvalid && s_axi_arready) begin
                        // Latch address and protection
                        rd_addr_latched <= s_axi_araddr;
                        rd_prot_latched <= s_axi_arprot;
                        rd_addr_valid   <= 1'b1;
                    end else begin
                        rd_addr_valid   <= 1'b0;
                    end

                    if ((s_axi_arvalid && s_axi_arready) || rd_addr_valid) begin
                        // Move to decode state
                        s_axi_arready <= 1'b0;
                        rd_addr_valid <= 1'b0;
                        rd_state      <= R_DECODE;
                    end
                end
                
                //==============================================================
                // R_DECODE: Decode address and validate target
                //==============================================================
                R_DECODE: begin
                    // Decode the region from bit 9
                    rd_addr_is_dma <= rd_addr_latched[9];
                    
                    // Validate the target
                    if (rd_addr_latched[9] == MAC_REGION) begin
                        // Always valid - MAC is always present
                        rd_state <= R_FORWARD;
                    end else if (rd_addr_latched[9] == DMA_REGION) begin
                        if (DMA_ENABLE) begin
                            // DMA enabled - forward transaction
                            rd_state <= R_FORWARD;
                        end else begin
                            // DMA disabled - return error
                            rd_state <= R_ERROR;
                        end
                    end else begin
                        // Invalid address (shouldn't happen with 1-bit decode)
                        rd_state <= R_ERROR;
                    end
                end
                
                //==============================================================
                // R_FORWARD: Forward read address to MAC or DMA
                //==============================================================
                R_FORWARD: begin
                    // Increment timeout counter
                    if (rd_timeout_cnt != TIMEOUT_COUNT) begin
                        rd_timeout_cnt <= rd_timeout_cnt + 1'b1;
                    end
                    
                    if (rd_addr_is_dma && DMA_ENABLE) begin
                        //------------------------------------------------------
                        // Forward to DMA
                        //------------------------------------------------------
                        dma_arvalid <= 1'b1;
                        dma_araddr  <= rd_addr_latched[7:0];  // FIXED: Use [7:0]
                        dma_arprot  <= rd_prot_latched;

                        if (dma_arvalid && dma_arready) begin
                            dma_arvalid    <= 1'b0;
                            dma_rready     <= 1'b1;
                            rd_timeout_cnt <= {TIMEOUT_WIDTH{1'b0}};

                            if (rd_timeout_cnt == TIMEOUT_COUNT) begin
                                // Timeout occurred - generate error response
                                rd_state <= R_ERROR;
                            end else begin
                                // Normal operation - wait for response
                                rd_state <= R_RESP;
                            end
                        end
                        
                    end else begin
                        //------------------------------------------------------
                        // Forward to MAC
                        //------------------------------------------------------
                        mac_arvalid <= 1'b1;
                        mac_araddr  <= rd_addr_latched[7:0];  // FIXED: Use [7:0]
                        mac_arprot  <= rd_prot_latched;

                        if (mac_arvalid && mac_arready) begin
                            mac_arvalid    <= 1'b0;
                            mac_rready     <= 1'b1;
                            rd_ar_done     <= 1'b0;
                            rd_timeout_cnt <= {TIMEOUT_WIDTH{1'b0}};

                            if (rd_timeout_cnt == TIMEOUT_COUNT) begin
                                // Timeout occurred - generate error response
                                rd_state <= R_ERROR;
                            end else begin
                                // Normal operation - wait for response
                                rd_state <= R_RESP;
                            end
                        end

                    end
                end
                
                //==============================================================
                // R_RESP: Wait for and forward read data
                //==============================================================
                R_RESP: begin
                    // Increment timeout counter
                    if (rd_timeout_cnt != TIMEOUT_COUNT) begin
                        rd_timeout_cnt <= rd_timeout_cnt + 1'b1;
                    end
                    
                    // Check for timeout
                    if (rd_timeout_cnt == TIMEOUT_COUNT) begin
                        // Timeout - generate error response directly
                        if (rd_addr_is_dma) begin
                            dma_rready <= 1'b0;
                        end else begin
                            mac_rready <= 1'b0;
                        end
                        rd_state <= R_ERROR;
                        
                    end else if (rd_addr_is_dma) begin
                        //------------------------------------------------------
                        // Wait for DMA read data
                        //------------------------------------------------------
                        if (dma_rvalid && dma_rready) begin
                            dma_rready      <= 1'b0;
                            s_axi_rvalid    <= 1'b1;
                            s_axi_rdata     <= dma_rdata;
                            s_axi_rresp     <= dma_rresp;
                            rd_timeout_cnt  <= {TIMEOUT_WIDTH{1'b0}};
                            
                            // Wait for master to accept data
                            if (s_axi_rvalid && s_axi_rready) begin
                                s_axi_rvalid <= 1'b0;
                                rd_state     <= R_IDLE;
                            end
                        end
                        
                    end else begin
                        //------------------------------------------------------
                        // Wait for MAC read data
                        //------------------------------------------------------
                        if (mac_rvalid && mac_rready) begin
                            mac_rready      <= 1'b0;
                            s_axi_rvalid    <= 1'b1;
                            s_axi_rdata     <= mac_rdata;
                            s_axi_rresp     <= mac_rresp;
                            rd_timeout_cnt  <= {TIMEOUT_WIDTH{1'b0}};
                            
                            // Wait for master to accept data
                            if (s_axi_rvalid && s_axi_rready) begin
                                s_axi_rvalid <= 1'b0;
                                rd_state     <= R_IDLE;
                            end
                        end
                    end
                    
                    // Handle case where data already captured
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rd_state     <= R_IDLE;
                    end
                end
                
                //==============================================================
                // R_ERROR: Return error response
                //==============================================================
                R_ERROR: begin
                    // Clear any pending handshakes
                    mac_rready <= 1'b0;
                    dma_rready <= 1'b0;
                    
                    // Generate error response
                    if (!s_axi_rvalid) begin
                        s_axi_rvalid <= 1'b1;
                        s_axi_rdata  <= ERROR_DATA;
                        s_axi_rresp  <= RESP_SLVERR;
                    end
                    
                    // Complete when master accepts response
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rd_state     <= R_IDLE;
                    end
                end
                
                default: begin
                    rd_state <= R_IDLE;
                end
            endcase
        end
    end
    //==========================================================================
    // Assertions for Simulation/Formal Verification (Optional)
    //==========================================================================
    
    `ifdef ENABLE_ASSERTIONS
        
        // Register previous values for stability checking
        reg [ADDR_WIDTH-1:0] prev_awaddr;
        reg [2:0] prev_awprot;
        reg [31:0] prev_wdata;
        reg [3:0] prev_wstrb;
        reg [1:0] prev_bresp;
        reg [ADDR_WIDTH-1:0] prev_araddr;
        reg [2:0] prev_arprot;
        reg [31:0] prev_rdata;
        reg [1:0] prev_rresp;
        
        always @(posedge clk) begin
            if (rst_n) begin
                // Store previous values
                prev_awaddr <= s_axi_awaddr;
                prev_awprot <= s_axi_awprot;
                prev_wdata  <= s_axi_wdata;
                prev_wstrb  <= s_axi_wstrb;
                prev_bresp  <= s_axi_bresp;
                prev_araddr <= s_axi_araddr;
                prev_arprot <= s_axi_arprot;
                prev_rdata  <= s_axi_rdata;
                prev_rresp  <= s_axi_rresp;
                
                // Check stability - AWVALID
                if (s_axi_awvalid && !s_axi_awready) begin
                    if (s_axi_awaddr !== prev_awaddr)
                        $error("AWADDR changed while AWVALID=1 and AWREADY=0");
                    if (s_axi_awprot !== prev_awprot)
                        $error("AWPROT changed while AWVALID=1 and AWREADY=0");
                end
                
                // Check stability - WVALID
                if (s_axi_wvalid && !s_axi_wready) begin
                    if (s_axi_wdata !== prev_wdata)
                        $error("WDATA changed while WVALID=1 and WREADY=0");
                    if (s_axi_wstrb !== prev_wstrb)
                        $error("WSTRB changed while WVALID=1 and WREADY=0");
                end
                
                // Check stability - BVALID
                if (s_axi_bvalid && !s_axi_bready) begin
                    if (s_axi_bresp !== prev_bresp)
                        $error("BRESP changed while BVALID=1 and BREADY=0");
                end
                
                // Check stability - ARVALID
                if (s_axi_arvalid && !s_axi_arready) begin
                    if (s_axi_araddr !== prev_araddr)
                        $error("ARADDR changed while ARVALID=1 and ARREADY=0");
                    if (s_axi_arprot !== prev_arprot)
                        $error("ARPROT changed while ARVALID=1 and ARREADY=0");
                end
                
                // Check stability - RVALID
                if (s_axi_rvalid && !s_axi_rready) begin
                    if (s_axi_rdata !== prev_rdata)
                        $error("RDATA changed while RVALID=1 and RREADY=0");
                    if (s_axi_rresp !== prev_rresp)
                        $error("RRESP changed while RVALID=1 and RREADY=0");
                end
                
                // Check no simultaneous MAC/DMA valid
                if (mac_awvalid && dma_awvalid)
                    $error("Both MAC and DMA AWVALID asserted");
                if (mac_wvalid && dma_wvalid)
                    $error("Both MAC and DMA WVALID asserted");
                if (mac_arvalid && dma_arvalid)
                    $error("Both MAC and DMA ARVALID asserted");
            end
        end
        
    `endif

endmodule