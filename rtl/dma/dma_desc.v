//==============================================================================
// File: dma_desc.v
// Description: DMA Descriptor Engine
//
// Purpose:
//   Manages descriptor rings for both TX and RX DMA channels. Handles:
//   - Descriptor fetch from system memory
//   - Descriptor writeback after transfer complete
//   - Ring pointer management (head/tail)
//   - Ownership bit checking
//
// Architecture:
//   - Two independent descriptor rings (TX and RX)
//   - Configurable ring depth
//   - Prefetch logic for improved throughput
//   - AXI4 read/write interface for descriptor access
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`include "dma_pkg.v"

module dma_desc #(
    parameter ADDR_WIDTH   = 64,        // AXI address width
    parameter DATA_WIDTH   = 64,        // AXI data width
    parameter DESC_SIZE    = 16,        // Descriptor size in bytes
    parameter MAX_RING_SZ  = 256        // Maximum ring size
)(
    // Clock and Reset
    input  wire                     clk,
    input  wire                     rst_n,
    
    //--------------------------------------------------------------------------
    // TX Descriptor Ring Control
    //--------------------------------------------------------------------------
    input  wire                     tx_enable,          // TX DMA enabled
    input  wire                     tx_reset,           // TX channel reset
    input  wire [ADDR_WIDTH-1:0]    tx_ring_base,       // TX ring base address
    input  wire [15:0]              tx_ring_size,       // Number of descriptors
    input  wire [15:0]              tx_head_ptr,        // Head pointer (SW updates)
    output reg  [15:0]              tx_tail_ptr,        // Tail pointer (HW updates)
    
    // TX Descriptor Output (to TX DMA engine)
    output reg                      tx_desc_valid,
    input  wire                     tx_desc_ready,
    output reg  [ADDR_WIDTH-1:0]    tx_buf_addr,        // Buffer address
    output reg  [15:0]              tx_buf_len,         // Packet length
    output reg  [31:0]              tx_desc_ctrl,       // Control flags
    output reg  [15:0]              tx_desc_index,      // Descriptor index
    
    // TX Descriptor Writeback (from TX DMA engine)
    input  wire                     tx_wb_valid,
    output reg                      tx_wb_ready,
    input  wire [15:0]              tx_wb_index,        // Descriptor to update
    input  wire [31:0]              tx_wb_status,       // Status to write
    
    //--------------------------------------------------------------------------
    // RX Descriptor Ring Control
    //--------------------------------------------------------------------------
    input  wire                     rx_enable,          // RX DMA enabled
    input  wire                     rx_reset,           // RX channel reset
    input  wire [ADDR_WIDTH-1:0]    rx_ring_base,       // RX ring base address
    input  wire [15:0]              rx_ring_size,       // Number of descriptors
    output reg  [15:0]              rx_head_ptr,        // Head pointer (HW updates)
    input  wire [15:0]              rx_tail_ptr,        // Tail pointer (SW updates)
    
    // RX Descriptor Output (to RX DMA engine)
    output reg                      rx_desc_valid,
    input  wire                     rx_desc_ready,
    output reg  [ADDR_WIDTH-1:0]    rx_buf_addr,        // Buffer address
    output reg  [15:0]              rx_buf_len,         // Max buffer length
    output reg  [31:0]              rx_desc_ctrl,       // Control flags
    output reg  [15:0]              rx_desc_index,      // Descriptor index
    
    // RX Descriptor Writeback (from RX DMA engine)
    input  wire                     rx_wb_valid,
    output reg                      rx_wb_ready,
    input  wire [15:0]              rx_wb_index,        // Descriptor to update
    input  wire [15:0]              rx_wb_length,       // Actual received length
    input  wire [31:0]              rx_wb_status,       // Status to write
    
    //--------------------------------------------------------------------------
    // AXI4 Master Interface for Descriptor Access
    //--------------------------------------------------------------------------
    // Read Address Channel
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,
    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
    output wire [7:0]               m_axi_arlen,
    output wire [2:0]               m_axi_arsize,
    output wire [1:0]               m_axi_arburst,
    output wire [3:0]               m_axi_arid,
    
    // Read Data Channel
    input  wire                     m_axi_rvalid,
    output reg                      m_axi_rready,
    input  wire [DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire [3:0]               m_axi_rid,
    
    // Write Address Channel
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,
    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output wire [7:0]               m_axi_awlen,
    output wire [2:0]               m_axi_awsize,
    output wire [1:0]               m_axi_awburst,
    output wire [3:0]               m_axi_awid,
    
    // Write Data Channel
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,
    output reg  [DATA_WIDTH-1:0]    m_axi_wdata,
    output reg  [DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output reg                      m_axi_wlast,
    
    // Write Response Channel
    input  wire                     m_axi_bvalid,
    output reg                      m_axi_bready,
    input  wire [1:0]               m_axi_bresp,
    input  wire [3:0]               m_axi_bid,
    
    //--------------------------------------------------------------------------
    // Status
    //--------------------------------------------------------------------------
    output wire                     tx_desc_avail,      // TX descriptors available
    output wire                     rx_desc_avail,      // RX descriptors available
    output reg                      desc_error          // Descriptor error occurred
);

    //--------------------------------------------------------------------------
    // Local Parameters
    //--------------------------------------------------------------------------
    localparam DESC_WORDS = DESC_SIZE * 8 / DATA_WIDTH; // Words per descriptor
    
    // AXI burst configuration
    assign m_axi_arlen   = DESC_WORDS - 1;  // Burst length
    assign m_axi_arsize  = $clog2(DATA_WIDTH/8);
    assign m_axi_arburst = 2'b01;           // INCR burst
    assign m_axi_arid    = 4'h0;
    
    // C6 fix: writeback is now always a single partial-strobe beat targeting
    // only word1 (status/length), never the full 2-word descriptor, so the
    // write burst is always 1 beat regardless of descriptor size.
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = $clog2(DATA_WIDTH/8);
    assign m_axi_awburst = 2'b01;
    assign m_axi_awid    = 4'h0;

    //--------------------------------------------------------------------------
    // State Machine States
    //--------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE         = 4'd0,
        ST_TX_FETCH_AR  = 4'd1,
        ST_TX_FETCH_R   = 4'd2,
        ST_TX_OUTPUT    = 4'd3,
        ST_TX_WB_AW     = 4'd4,
        ST_TX_WB_W      = 4'd5,
        ST_TX_WB_B      = 4'd6,
        ST_RX_FETCH_AR  = 4'd7,
        ST_RX_FETCH_R   = 4'd8,
        ST_RX_OUTPUT    = 4'd9,
        ST_RX_WB_AW     = 4'd10,
        ST_RX_WB_W      = 4'd11,
        ST_RX_WB_B      = 4'd12;
    
    reg [3:0] state;
    
    //--------------------------------------------------------------------------
    // Descriptor Buffers
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] desc_buf [0:DESC_WORDS-1];
    reg [2:0] desc_word_cnt;
    
    // Writeback buffer
    reg [DATA_WIDTH-1:0] wb_buf [0:DESC_WORDS-1];
    reg [2:0] wb_word_cnt;
    
    // Pending writeback tracking
    reg                     tx_wb_pending;
    reg [15:0]              tx_wb_idx_pending;
    reg [31:0]              tx_wb_status_pending;
    
    reg                     rx_wb_pending;
    reg [15:0]              rx_wb_idx_pending;
    reg [15:0]              rx_wb_len_pending;
    reg [31:0]              rx_wb_status_pending;

    //--------------------------------------------------------------------------
    // Ring Pointer Logic
    //--------------------------------------------------------------------------
    // TX: SW writes head (new descriptors), HW updates tail (consumed)
    //     Available count = head - tail
    // RX: SW writes tail (available buffers), HW updates head (filled buffers)
    //     Available count = tail - head
    //
    // Standard initialization:
    //   TX: SW sets tx_head_ptr = N (number of prepared descriptors), HW starts with tail=0
    //   RX: SW sets rx_tail_ptr = N (number of available buffers), HW starts with head=0
    
    wire [15:0] tx_pending_cnt = (tx_head_ptr >= tx_tail_ptr) ?
                                 (tx_head_ptr - tx_tail_ptr) :
                                 (tx_ring_size - tx_tail_ptr + tx_head_ptr);
    
    wire [15:0] rx_pending_cnt = (rx_tail_ptr >= rx_head_ptr) ?
                                 (rx_tail_ptr - rx_head_ptr) :
                                 (rx_ring_size - rx_head_ptr + rx_tail_ptr);
    
    assign tx_desc_avail = tx_enable && (tx_pending_cnt > 0);
    assign rx_desc_avail = rx_enable && (rx_pending_cnt > 0);

    //--------------------------------------------------------------------------
    // Address Calculation
    //--------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] tx_desc_addr = tx_ring_base + (tx_tail_ptr * DESC_SIZE);
    wire [ADDR_WIDTH-1:0] rx_desc_addr = rx_ring_base + (rx_head_ptr * DESC_SIZE);
    
    // C6 fix: target word1 (the status/length half, offset +8) directly so
    // word0 (buffer address) is never touched by a writeback.
    localparam [ADDR_WIDTH-1:0] WB_WORD1_OFFSET = 8;
    wire [ADDR_WIDTH-1:0] tx_wb_addr = tx_ring_base + (tx_wb_idx_pending * DESC_SIZE) + WB_WORD1_OFFSET;
    wire [ADDR_WIDTH-1:0] rx_wb_addr = rx_ring_base + (rx_wb_idx_pending * DESC_SIZE) + WB_WORD1_OFFSET;

    //--------------------------------------------------------------------------
    // Main State Machine
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            
            // TX outputs
            tx_desc_valid <= 1'b0;
            tx_buf_addr   <= {ADDR_WIDTH{1'b0}};
            tx_buf_len    <= 16'd0;
            tx_desc_ctrl  <= 32'd0;
            tx_desc_index <= 16'd0;
            tx_tail_ptr   <= 16'd0;
            tx_wb_ready   <= 1'b0;
            
            // RX outputs
            rx_desc_valid <= 1'b0;
            rx_buf_addr   <= {ADDR_WIDTH{1'b0}};
            rx_buf_len    <= 16'd0;
            rx_desc_ctrl  <= 32'd0;
            rx_desc_index <= 16'd0;
            rx_head_ptr   <= 16'd0;
            rx_wb_ready   <= 1'b0;
            
            // AXI outputs
            m_axi_arvalid <= 1'b0;
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_rready  <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= {DATA_WIDTH{1'b0}};
            m_axi_wstrb   <= {(DATA_WIDTH/8){1'b1}};
            m_axi_wlast   <= 1'b0;
            m_axi_bready  <= 1'b0;
            
            // Internal
            desc_word_cnt <= 3'd0;
            wb_word_cnt   <= 3'd0;
            tx_wb_pending <= 1'b0;
            rx_wb_pending <= 1'b0;
            desc_error    <= 1'b0;
            
        end else begin
            // Default de-assertions
            if (m_axi_arready) m_axi_arvalid <= 1'b0;
            if (m_axi_awready) m_axi_awvalid <= 1'b0;
            if (m_axi_wready && m_axi_wlast) m_axi_wvalid <= 1'b0;
            
            // Descriptor consumed acknowledgment (folded in from the former
            // standalone "Descriptor consumed acknowledgment" always block,
            // which multiply-drove tx_desc_valid/rx_desc_valid alongside this
            // FSM). When the TX/RX DMA engine accepts a descriptor, clear valid.
            if (tx_desc_valid && tx_desc_ready) begin
                tx_desc_valid <= 1'b0;
            end
            if (rx_desc_valid && rx_desc_ready) begin
                rx_desc_valid <= 1'b0;
            end

            // Capture writeback requests
            tx_wb_ready <= 1'b0;
            rx_wb_ready <= 1'b0;
            
            if (tx_wb_valid && !tx_wb_pending && !tx_wb_ready) begin
                tx_wb_pending <= 1'b1;
                tx_wb_idx_pending <= tx_wb_index;
                tx_wb_status_pending <= tx_wb_status;
                tx_wb_ready <= 1'b1;
            end
            
            if (rx_wb_valid && !rx_wb_pending && !rx_wb_ready) begin
                rx_wb_pending <= 1'b1;
                rx_wb_idx_pending <= rx_wb_index;
                rx_wb_len_pending <= rx_wb_length;
                rx_wb_status_pending <= rx_wb_status;
                rx_wb_ready <= 1'b1;
            end
            
            // Handle resets
            if (tx_reset) begin
                tx_tail_ptr   <= 16'd0;
                tx_desc_valid <= 1'b0;
                tx_wb_pending <= 1'b0;
            end
            
            if (rx_reset) begin
                rx_head_ptr   <= 16'd0;
                rx_desc_valid <= 1'b0;
                rx_wb_pending <= 1'b0;
            end
            
            case (state)
                //--------------------------------------------------------------
                // Idle - Arbitrate between operations
                //--------------------------------------------------------------
                ST_IDLE: begin
                    // Priority: Writebacks > RX fetch > TX fetch
                    if (tx_wb_pending) begin
                        state <= ST_TX_WB_AW;
                        m_axi_awvalid <= 1'b1;
                        m_axi_awaddr  <= tx_wb_addr;
                        
                        // C6 fix: single-beat, partial-strobe write of word1 only (status,
                        // bits[127:96]) -- word0 (address) and the reserved/length bytes of
                        // word1 are protected by wstrb, not just left out of wb_buf.
                        m_axi_wdata <= {tx_wb_status_pending, 32'd0};
                        m_axi_wstrb <= 8'hF0;   // bytes 4-7 only (status)
                        m_axi_wlast <= 1'b1;
                        
                    end else if (rx_wb_pending) begin
                        state <= ST_RX_WB_AW;
                        m_axi_awvalid <= 1'b1;
                        m_axi_awaddr  <= rx_wb_addr;
                        
                        // C6 fix: single-beat write of word1 covering actual-length[31:16]
                        // and status[63:32]; buffer-length bytes[15:0] and word0 preserved.
                        m_axi_wdata <= {rx_wb_status_pending, rx_wb_len_pending, 16'd0};
                        m_axi_wstrb <= 8'hFC;   // bytes 2-7 (length + status)
                        m_axi_wlast <= 1'b1;
                        
                    end else if (rx_desc_avail && !rx_desc_valid) begin
                        // Fetch next RX descriptor
                        state <= ST_RX_FETCH_AR;
                        m_axi_arvalid <= 1'b1;
                        m_axi_araddr  <= rx_desc_addr;
                        m_axi_rready  <= 1'b1;
                        desc_word_cnt <= 3'd0;
                        
                    end else if (tx_desc_avail && !tx_desc_valid) begin
                        // Fetch next TX descriptor
                        state <= ST_TX_FETCH_AR;
                        m_axi_arvalid <= 1'b1;
                        m_axi_araddr  <= tx_desc_addr;
                        m_axi_rready  <= 1'b1;
                        desc_word_cnt <= 3'd0;
                    end
                end
                
                //--------------------------------------------------------------
                // TX Descriptor Fetch
                //--------------------------------------------------------------
                ST_TX_FETCH_AR: begin
                    if (m_axi_arready) begin
                        state <= ST_TX_FETCH_R;
                    end
                end
                
                ST_TX_FETCH_R: begin
                    if (m_axi_rvalid) begin
                        desc_buf[desc_word_cnt] <= m_axi_rdata;
                        
                        if (m_axi_rlast || desc_word_cnt == DESC_WORDS-1) begin
                            m_axi_rready <= 1'b0;
                            state <= ST_TX_OUTPUT;
                        end else begin
                            desc_word_cnt <= desc_word_cnt + 1;
                        end
                        
                        // Check for AXI errors
                        if (m_axi_rresp != 2'b00) begin
                            desc_error <= 1'b1;
                        end
                    end
                end
                
                ST_TX_OUTPUT: begin
                    // Parse descriptor and output to TX DMA engine
                    // Format: [31:0]=addr_lo, [63:32]=addr_hi, [79:64]=length, [127:96]=ctrl
                    if (DATA_WIDTH == 64) begin
                        tx_buf_addr  <= desc_buf[0];
                        tx_buf_len   <= desc_buf[1][15:0];
                        tx_desc_ctrl <= desc_buf[1][63:32];
                    end else begin
                        tx_buf_addr  <= {desc_buf[1], desc_buf[0]};
                        tx_buf_len   <= desc_buf[2][15:0];
                        tx_desc_ctrl <= desc_buf[3];
                    end
                    tx_desc_index <= tx_tail_ptr;
                    
                    // Check ownership bit
                    if (DATA_WIDTH == 64) begin
                        if (desc_buf[1][32]) begin // OWN bit set
                            tx_desc_valid <= 1'b1;
                        end
                    end else begin
                        if (desc_buf[3][0]) begin
                            tx_desc_valid <= 1'b1;
                        end
                    end
                    
                    state <= ST_IDLE;
                end
                
                //--------------------------------------------------------------
                // RX Descriptor Fetch
                //--------------------------------------------------------------
                ST_RX_FETCH_AR: begin
                    if (m_axi_arready) begin
                        state <= ST_RX_FETCH_R;
                    end
                end
                
                ST_RX_FETCH_R: begin
                    if (m_axi_rvalid) begin
                        desc_buf[desc_word_cnt] <= m_axi_rdata;
                        
                        if (m_axi_rlast || desc_word_cnt == DESC_WORDS-1) begin
                            m_axi_rready <= 1'b0;
                            state <= ST_RX_OUTPUT;
                        end else begin
                            desc_word_cnt <= desc_word_cnt + 1;
                        end
                        
                        if (m_axi_rresp != 2'b00) begin
                            desc_error <= 1'b1;
                        end
                    end
                end
                
                ST_RX_OUTPUT: begin
                    // Parse descriptor for RX
                    if (DATA_WIDTH == 64) begin
                        rx_buf_addr  <= desc_buf[0];
                        rx_buf_len   <= desc_buf[1][15:0];
                        rx_desc_ctrl <= desc_buf[1][63:32];
                    end else begin
                        rx_buf_addr  <= {desc_buf[1], desc_buf[0]};
                        rx_buf_len   <= desc_buf[2][15:0];
                        rx_desc_ctrl <= desc_buf[3];
                    end
                    rx_desc_index <= rx_head_ptr;
                    
                    // Check ownership bit
                    if (DATA_WIDTH == 64) begin
                        if (desc_buf[1][32]) begin
                            rx_desc_valid <= 1'b1;
                        end
                    end else begin
                        if (desc_buf[3][0]) begin
                            rx_desc_valid <= 1'b1;
                        end
                    end
                    
                    state <= ST_IDLE;
                end
                
                //--------------------------------------------------------------
                // TX Descriptor Writeback
                //--------------------------------------------------------------
                ST_TX_WB_AW: begin
                    if (m_axi_awready) begin
                        state <= ST_TX_WB_W;
                        m_axi_wvalid <= 1'b1;  // wdata/wstrb/wlast prepared in ST_IDLE
                    end
                end
                
                ST_TX_WB_W: begin
                    if (m_axi_wready) begin
                        // Always a single beat now (C6) -- no more multi-word loop.
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state <= ST_TX_WB_B;
                    end
                end
                
                ST_TX_WB_B: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready  <= 1'b0;
                        tx_wb_pending <= 1'b0;
                        
                        // Advance tail pointer
                        if (tx_tail_ptr == tx_ring_size - 1)
                            tx_tail_ptr <= 16'd0;
                        else
                            tx_tail_ptr <= tx_tail_ptr + 1;
                        
                        // Clear valid for next fetch
                        tx_desc_valid <= 1'b0;
                        
                        if (m_axi_bresp != 2'b00) begin
                            desc_error <= 1'b1;
                        end
                        
                        state <= ST_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                // RX Descriptor Writeback
                //--------------------------------------------------------------
                ST_RX_WB_AW: begin
                    if (m_axi_awready) begin
                        state <= ST_RX_WB_W;
                        m_axi_wvalid <= 1'b1;
                        m_axi_wdata  <= wb_buf[0];
                        m_axi_wstrb  <= {(DATA_WIDTH/8){1'b1}};
                        m_axi_wlast  <= (DESC_WORDS == 1);
                    end
                end
                
                ST_RX_WB_W: begin
                    if (m_axi_wready) begin
                        if (m_axi_wlast) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_bready <= 1'b1;
                            state <= ST_RX_WB_B;
                        end else begin
                            wb_word_cnt <= wb_word_cnt + 1;
                            m_axi_wdata <= wb_buf[wb_word_cnt + 1];
                            m_axi_wlast <= (wb_word_cnt + 1 == DESC_WORDS - 1);
                        end
                    end
                end
                
                ST_RX_WB_B: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready  <= 1'b0;
                        rx_wb_pending <= 1'b0;
                        
                        // Advance head pointer
                        if (rx_head_ptr == rx_ring_size - 1)
                            rx_head_ptr <= 16'd0;
                        else
                            rx_head_ptr <= rx_head_ptr + 1;
                        
                        // Clear valid for next fetch
                        rx_desc_valid <= 1'b0;
                        
                        if (m_axi_bresp != 2'b00) begin
                            desc_error <= 1'b1;
                        end
                        
                        state <= ST_IDLE;
                    end
                end
                
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
