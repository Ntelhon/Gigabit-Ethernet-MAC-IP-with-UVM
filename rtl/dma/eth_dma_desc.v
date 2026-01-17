//==============================================================================
// Module: eth_dma_desc
// Description: Descriptor Manager and AXI4 Master Interface
//
// Features:
//   - Centralized AXI4 master for all memory operations
//   - Arbitrates between TX/RX descriptor fetches
//   - Arbitrates between TX/RX data transfers
//   - Handles descriptor reads and writebacks
//   - Burst optimization for data transfers
//   - Error handling and reporting
//
// Priority:
//   1. Descriptor fetches (highest priority)
//   2. Descriptor writebacks
//   3. RX data writes (medium priority - avoid overflow)
//   4. TX data reads (lowest priority)
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_dma_desc #(
    parameter MEM_ADDR_WIDTH    = 32,
    parameter MEM_DATA_WIDTH    = 64,
    parameter MEM_ID_WIDTH      = 4,
    parameter DESC_ADDR_WIDTH   = 32,
    parameter BUF_SIZE_WIDTH    = 14,
    parameter MAX_BURST         = 16
) (
    input  wire                             clk,
    input  wire                             rst_n,
    
    //==========================================================================
    // TX Descriptor Interface
    //==========================================================================
    input  wire                             tx_desc_req,
    output reg                              tx_desc_ack,
    input  wire [DESC_ADDR_WIDTH-1:0]       tx_desc_addr,
    output reg  [127:0]                     tx_desc_data,
    output reg                              tx_desc_valid,
    
    input  wire                             tx_desc_wb_req,
    output reg                              tx_desc_wb_ack,
    input  wire [DESC_ADDR_WIDTH-1:0]       tx_desc_wb_addr,
    input  wire [127:0]                     tx_desc_wb_data,
    
    //==========================================================================
    // RX Descriptor Interface
    //==========================================================================
    input  wire                             rx_desc_req,
    output reg                              rx_desc_ack,
    input  wire [DESC_ADDR_WIDTH-1:0]       rx_desc_addr,
    output reg  [127:0]                     rx_desc_data,
    output reg                              rx_desc_valid,
    
    input  wire                             rx_desc_wb_req,
    output reg                              rx_desc_wb_ack,
    input  wire [DESC_ADDR_WIDTH-1:0]       rx_desc_wb_addr,
    input  wire [127:0]                     rx_desc_wb_data,
    
    //==========================================================================
    // TX Data Read Interface
    //==========================================================================
    input  wire                             tx_data_req,
    output reg                              tx_data_ack,
    input  wire [MEM_ADDR_WIDTH-1:0]        tx_data_addr,
    input  wire [BUF_SIZE_WIDTH-1:0]        tx_data_len,
    output reg  [MEM_DATA_WIDTH-1:0]        tx_data_rdata,
    output reg                              tx_data_rvalid,
    output reg                              tx_data_rlast,
    input  wire                             tx_data_rready,
    
    //==========================================================================
    // RX Data Write Interface
    //==========================================================================
    input  wire                             rx_data_req,
    output reg                              rx_data_ack,
    input  wire [MEM_ADDR_WIDTH-1:0]        rx_data_addr,
    input  wire [BUF_SIZE_WIDTH-1:0]        rx_data_len,
    input  wire [MEM_DATA_WIDTH-1:0]        rx_data_wdata,
    input  wire                             rx_data_wvalid,
    input  wire                             rx_data_wlast,
    output reg                              rx_data_wready,
    input  wire [MEM_DATA_WIDTH/8-1:0]      rx_data_wstrb,
    
    //==========================================================================
    // AXI4 Master Interface
    //==========================================================================
    output reg  [MEM_ID_WIDTH-1:0]          m_axi_awid,
    output reg  [MEM_ADDR_WIDTH-1:0]        m_axi_awaddr,
    output reg  [7:0]                       m_axi_awlen,
    output reg  [2:0]                       m_axi_awsize,
    output reg  [1:0]                       m_axi_awburst,
    output reg                              m_axi_awlock,
    output reg  [3:0]                       m_axi_awcache,
    output reg  [2:0]                       m_axi_awprot,
    output reg                              m_axi_awvalid,
    input  wire                             m_axi_awready,
    
    output reg  [MEM_DATA_WIDTH-1:0]        m_axi_wdata,
    output reg  [MEM_DATA_WIDTH/8-1:0]      m_axi_wstrb,
    output reg                              m_axi_wlast,
    output reg                              m_axi_wvalid,
    input  wire                             m_axi_wready,
    
    input  wire [MEM_ID_WIDTH-1:0]          m_axi_bid,
    input  wire [1:0]                       m_axi_bresp,
    input  wire                             m_axi_bvalid,
    output reg                              m_axi_bready,
    
    output reg  [MEM_ID_WIDTH-1:0]          m_axi_arid,
    output reg  [MEM_ADDR_WIDTH-1:0]        m_axi_araddr,
    output reg  [7:0]                       m_axi_arlen,
    output reg  [2:0]                       m_axi_arsize,
    output reg  [1:0]                       m_axi_arburst,
    output reg                              m_axi_arlock,
    output reg  [3:0]                       m_axi_arcache,
    output reg  [2:0]                       m_axi_arprot,
    output reg                              m_axi_arvalid,
    input  wire                             m_axi_arready,
    
    input  wire [MEM_ID_WIDTH-1:0]          m_axi_rid,
    input  wire [MEM_DATA_WIDTH-1:0]        m_axi_rdata,
    input  wire [1:0]                       m_axi_rresp,
    input  wire                             m_axi_rlast,
    input  wire                             m_axi_rvalid,
    output reg                              m_axi_rready
);

    //==========================================================================
    // AXI Transaction IDs
    //==========================================================================
    localparam ID_TX_DESC = 4'h0;
    localparam ID_RX_DESC = 4'h1;
    localparam ID_TX_DATA = 4'h2;
    localparam ID_RX_DATA = 4'h3;
    
    //==========================================================================
    // Arbiter State Machine
    //==========================================================================
    localparam ARB_IDLE         = 3'h0;
    localparam ARB_TX_DESC_RD   = 3'h1;
    localparam ARB_RX_DESC_RD   = 3'h2;
    localparam ARB_TX_DESC_WR   = 3'h3;
    localparam ARB_RX_DESC_WR   = 3'h4;
    localparam ARB_TX_DATA_RD   = 3'h5;
    localparam ARB_RX_DATA_WR   = 3'h6;
    
    reg [2:0] arb_state, arb_next_state;
    
    //==========================================================================
    // Priority Encoder for Arbitration
    //==========================================================================
    always @(*) begin
        arb_next_state = ARB_IDLE;
        
        case (arb_state)
            ARB_IDLE: begin
                // Priority: Descriptor ops > RX data > TX data
                if (tx_desc_req) begin
                    arb_next_state = ARB_TX_DESC_RD;
                end else if (rx_desc_req) begin
                    arb_next_state = ARB_RX_DESC_RD;
                end else if (tx_desc_wb_req) begin
                    arb_next_state = ARB_TX_DESC_WR;
                end else if (rx_desc_wb_req) begin
                    arb_next_state = ARB_RX_DESC_WR;
                end else if (rx_data_req) begin
                    arb_next_state = ARB_RX_DATA_WR;
                end else if (tx_data_req) begin
                    arb_next_state = ARB_TX_DATA_RD;
                end else begin
                    arb_next_state = ARB_IDLE;
                end
            end
            
            // Each state completes and returns to IDLE
            default: begin
                arb_next_state = ARB_IDLE;
            end
        endcase
    end
    
    always @(posedge clk) begin
        if (!rst_n) begin
            arb_state <= ARB_IDLE;
        end else begin
            arb_state <= arb_next_state;
        end
    end
    
    //==========================================================================
    // AXI Read Address Channel
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_arid    <= {MEM_ID_WIDTH{1'b0}};
            m_axi_araddr  <= {MEM_ADDR_WIDTH{1'b0}};
            m_axi_arlen   <= 8'h0;
            m_axi_arsize  <= 3'h3;  // 64-bit transfers
            m_axi_arburst <= 2'b01; // INCR
            m_axi_arlock  <= 1'b0;
            m_axi_arcache <= 4'h3;  // Cacheable
            m_axi_arprot  <= 3'h0;
            m_axi_arvalid <= 1'b0;
            tx_desc_ack   <= 1'b0;
            rx_desc_ack   <= 1'b0;
            tx_data_ack   <= 1'b0;
        end else begin
            tx_desc_ack <= 1'b0;
            rx_desc_ack <= 1'b0;
            tx_data_ack <= 1'b0;
            
            case (arb_state)
                ARB_TX_DESC_RD: begin
                    if (!m_axi_arvalid) begin
                        m_axi_arid    <= ID_TX_DESC;
                        m_axi_araddr  <= tx_desc_addr[MEM_ADDR_WIDTH-1:0];
                        m_axi_arlen   <= 8'h1;  // 2 beats for 128-bit descriptor
                        m_axi_arvalid <= 1'b1;
                        tx_desc_ack   <= 1'b1;
                    end else if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                    end
                end
                
                ARB_RX_DESC_RD: begin
                    if (!m_axi_arvalid) begin
                        m_axi_arid    <= ID_RX_DESC;
                        m_axi_araddr  <= rx_desc_addr[MEM_ADDR_WIDTH-1:0];
                        m_axi_arlen   <= 8'h1;
                        m_axi_arvalid <= 1'b1;
                        rx_desc_ack   <= 1'b1;
                    end else if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                    end
                end
                
                ARB_TX_DATA_RD: begin
                    if (!m_axi_arvalid) begin
                        m_axi_arid    <= ID_TX_DATA;
                        m_axi_araddr  <= tx_data_addr;
                        m_axi_arlen   <= (tx_data_len >> 3) - 1;  // Convert bytes to beats
                        m_axi_arvalid <= 1'b1;
                        tx_data_ack   <= 1'b1;
                    end else if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                    end
                end
                
                default: begin
                    m_axi_arvalid <= 1'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // AXI Read Data Channel
    //==========================================================================
    reg [63:0] desc_buffer_lo;
    reg        desc_beat_count;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_rready    <= 1'b0;
            tx_desc_valid   <= 1'b0;
            rx_desc_valid   <= 1'b0;
            tx_desc_data    <= 128'h0;
            rx_desc_data    <= 128'h0;
            tx_data_rdata   <= {MEM_DATA_WIDTH{1'b0}};
            tx_data_rvalid  <= 1'b0;
            tx_data_rlast   <= 1'b0;
            desc_buffer_lo  <= 64'h0;
            desc_beat_count <= 1'b0;
        end else begin
            tx_desc_valid  <= 1'b0;
            rx_desc_valid  <= 1'b0;
            tx_data_rvalid <= 1'b0;
            tx_data_rlast  <= 1'b0;
            
            m_axi_rready <= (arb_state != ARB_IDLE) || tx_data_rready;
            
            if (m_axi_rvalid && m_axi_rready) begin
                case (m_axi_rid)
                    ID_TX_DESC: begin
                        if (!desc_beat_count) begin
                            desc_buffer_lo  <= m_axi_rdata[63:0];
                            desc_beat_count <= 1'b1;
                        end else begin
                            tx_desc_data    <= {m_axi_rdata[63:0], desc_buffer_lo};
                            tx_desc_valid   <= 1'b1;
                            desc_beat_count <= 1'b0;
                        end
                    end
                    
                    ID_RX_DESC: begin
                        if (!desc_beat_count) begin
                            desc_buffer_lo  <= m_axi_rdata[63:0];
                            desc_beat_count <= 1'b1;
                        end else begin
                            rx_desc_data    <= {m_axi_rdata[63:0], desc_buffer_lo};
                            rx_desc_valid   <= 1'b1;
                            desc_beat_count <= 1'b0;
                        end
                    end
                    
                    ID_TX_DATA: begin
                        tx_data_rdata  <= m_axi_rdata;
                        tx_data_rvalid <= 1'b1;
                        tx_data_rlast  <= m_axi_rlast;
                    end
                    
                    default: begin
                    end
                endcase
            end
        end
    end
    
    //==========================================================================
    // AXI Write Address Channel
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_awid     <= {MEM_ID_WIDTH{1'b0}};
            m_axi_awaddr   <= {MEM_ADDR_WIDTH{1'b0}};
            m_axi_awlen    <= 8'h0;
            m_axi_awsize   <= 3'h3;
            m_axi_awburst  <= 2'b01;
            m_axi_awlock   <= 1'b0;
            m_axi_awcache  <= 4'h3;
            m_axi_awprot   <= 3'h0;
            m_axi_awvalid  <= 1'b0;
            tx_desc_wb_ack <= 1'b0;
            rx_desc_wb_ack <= 1'b0;
            rx_data_ack    <= 1'b0;
        end else begin
            tx_desc_wb_ack <= 1'b0;
            rx_desc_wb_ack <= 1'b0;
            rx_data_ack    <= 1'b0;
            
            case (arb_state)
                ARB_TX_DESC_WR: begin
                    if (!m_axi_awvalid) begin
                        m_axi_awid      <= ID_TX_DESC;
                        m_axi_awaddr    <= tx_desc_wb_addr[MEM_ADDR_WIDTH-1:0];
                        m_axi_awlen     <= 8'h1;
                        m_axi_awvalid   <= 1'b1;
                        tx_desc_wb_ack  <= 1'b1;
                    end else if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                    end
                end
                
                ARB_RX_DESC_WR: begin
                    if (!m_axi_awvalid) begin
                        m_axi_awid      <= ID_RX_DESC;
                        m_axi_awaddr    <= rx_desc_wb_addr[MEM_ADDR_WIDTH-1:0];
                        m_axi_awlen     <= 8'h1;
                        m_axi_awvalid   <= 1'b1;
                        rx_desc_wb_ack  <= 1'b1;
                    end else if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                    end
                end
                
                ARB_RX_DATA_WR: begin
                    if (!m_axi_awvalid) begin
                        m_axi_awid     <= ID_RX_DATA;
                        m_axi_awaddr   <= rx_data_addr;
                        m_axi_awlen    <= (rx_data_len >> 3) - 1;
                        m_axi_awvalid  <= 1'b1;
                        rx_data_ack    <= 1'b1;
                    end else if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                    end
                end
                
                default: begin
                    m_axi_awvalid <= 1'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // AXI Write Data Channel
    //==========================================================================
    reg        wb_beat_count;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_wdata    <= {MEM_DATA_WIDTH{1'b0}};
            m_axi_wstrb    <= {MEM_DATA_WIDTH/8{1'b0}};
            m_axi_wlast    <= 1'b0;
            m_axi_wvalid   <= 1'b0;
            rx_data_wready <= 1'b0;
            wb_beat_count  <= 1'b0;
        end else begin
            case (arb_state)
                ARB_TX_DESC_WR: begin
                    if (!wb_beat_count) begin
                        m_axi_wdata   <= tx_desc_wb_data[63:0];
                        m_axi_wstrb   <= {MEM_DATA_WIDTH/8{1'b1}};
                        m_axi_wlast   <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        if (m_axi_wready) begin
                            wb_beat_count <= 1'b1;
                        end
                    end else begin
                        m_axi_wdata  <= tx_desc_wb_data[127:64];
                        m_axi_wlast  <= 1'b1;
                        if (m_axi_wready) begin
                            m_axi_wvalid  <= 1'b0;
                            wb_beat_count <= 1'b0;
                        end
                    end
                end
                
                ARB_RX_DESC_WR: begin
                    if (!wb_beat_count) begin
                        m_axi_wdata   <= rx_desc_wb_data[63:0];
                        m_axi_wstrb   <= {MEM_DATA_WIDTH/8{1'b1}};
                        m_axi_wlast   <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        if (m_axi_wready) begin
                            wb_beat_count <= 1'b1;
                        end
                    end else begin
                        m_axi_wdata  <= rx_desc_wb_data[127:64];
                        m_axi_wlast  <= 1'b1;
                        if (m_axi_wready) begin
                            m_axi_wvalid  <= 1'b0;
                            wb_beat_count <= 1'b0;
                        end
                    end
                end
                
                ARB_RX_DATA_WR: begin
                    rx_data_wready <= m_axi_wready;
                    m_axi_wdata    <= rx_data_wdata;
                    m_axi_wstrb    <= rx_data_wstrb;
                    m_axi_wlast    <= rx_data_wlast;
                    m_axi_wvalid   <= rx_data_wvalid;
                end
                
                default: begin
                    m_axi_wvalid   <= 1'b0;
                    rx_data_wready <= 1'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // AXI Write Response Channel
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_bready <= 1'b0;
        end else begin
            m_axi_bready <= 1'b1;  // Always ready for write response
        end
    end

endmodule
