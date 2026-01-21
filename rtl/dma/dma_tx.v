//==============================================================================
// File: dma_tx.v
// Description: TX DMA Engine
//
// Purpose:
//   Reads packet data from system memory based on descriptors and drives
//   the AXI-Stream TX interface toward the MAC. Operates in store-and-forward
//   mode for proper Ethernet framing.
//
// Architecture:
//   - Receives TX descriptors from dma_desc
//   - Issues AXI-MM read bursts to fetch packet data
//   - Buffers data in internal FIFO for rate matching
//   - Drives AXI-Stream TX interface with proper tlast/tuser
//   - Triggers descriptor writeback upon completion
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`include "dma_pkg.v"

module dma_tx #(
    parameter ADDR_WIDTH    = 64,       // AXI address width
    parameter AXI_DATA_W    = 64,       // AXI-MM data width
    parameter AXIS_DATA_W   = 8,        // AXI-Stream data width (MAC side)
    parameter MAX_BURST_LEN = 16,       // Max AXI burst length
    parameter FIFO_DEPTH    = 2048      // Internal FIFO depth (bytes)
)(
    // Clock and Reset
    input  wire                     clk,
    input  wire                     rst_n,
    
    //--------------------------------------------------------------------------
    // Control Interface
    //--------------------------------------------------------------------------
    input  wire                     enable,         // Channel enable
    input  wire                     soft_reset,     // Channel reset
    output wire                     busy,           // DMA busy
    output wire                     halted,         // Channel halted
    output reg                      error,          // Error status
    
    //--------------------------------------------------------------------------
    // Descriptor Interface (from dma_desc)
    //--------------------------------------------------------------------------
    input  wire                     desc_valid,
    output reg                      desc_ready,
    input  wire [ADDR_WIDTH-1:0]    desc_buf_addr,
    input  wire [15:0]              desc_buf_len,
    input  wire [31:0]              desc_ctrl,
    input  wire [15:0]              desc_index,
    
    // Writeback Interface (to dma_desc)
    output reg                      wb_valid,
    input  wire                     wb_ready,
    output reg  [15:0]              wb_index,
    output reg  [31:0]              wb_status,
    
    //--------------------------------------------------------------------------
    // AXI4 Master Read Interface (for packet data)
    //--------------------------------------------------------------------------
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,
    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg  [7:0]               m_axi_arlen,
    output wire [2:0]               m_axi_arsize,
    output wire [1:0]               m_axi_arburst,
    output wire [3:0]               m_axi_arid,
    
    input  wire                     m_axi_rvalid,
    output reg                      m_axi_rready,
    input  wire [AXI_DATA_W-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire [3:0]               m_axi_rid,
    
    //--------------------------------------------------------------------------
    // AXI-Stream TX Interface (to MAC)
    //--------------------------------------------------------------------------
    output reg                      m_axis_tvalid,
    input  wire                     m_axis_tready,
    output reg  [AXIS_DATA_W-1:0]   m_axis_tdata,
    output reg                      m_axis_tlast,
    output reg                      m_axis_tuser,   // SOF indicator
    
    //--------------------------------------------------------------------------
    // Statistics
    //--------------------------------------------------------------------------
    output reg  [31:0]              tx_pkt_cnt,
    output reg  [31:0]              tx_byte_cnt
);

    //--------------------------------------------------------------------------
    // Local Parameters
    //--------------------------------------------------------------------------
    localparam AXI_BYTES = AXI_DATA_W / 8;
    localparam FIFO_ADDR_W = $clog2(FIFO_DEPTH);
    
    // AXI configuration
    assign m_axi_arsize  = $clog2(AXI_BYTES);
    assign m_axi_arburst = 2'b01;  // INCR
    assign m_axi_arid    = 4'h1;   // TX uses ID=1

    //--------------------------------------------------------------------------
    // State Machine
    //--------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE         = 4'd0,
        ST_FETCH_DESC   = 4'd1,
        ST_CALC_BURST   = 4'd2,
        ST_ISSUE_AR     = 4'd3,
        ST_READ_DATA    = 4'd4,
        ST_STREAM_OUT   = 4'd5,
        ST_WRITEBACK    = 4'd6,
        ST_WAIT_WB      = 4'd7,
        ST_ERROR        = 4'd8;
    
    reg [3:0] state;
    
    //--------------------------------------------------------------------------
    // Internal Registers
    //--------------------------------------------------------------------------
    // Current descriptor info
    reg [ADDR_WIDTH-1:0]    cur_addr;
    reg [15:0]              cur_len;
    reg [15:0]              cur_index;
    reg [31:0]              cur_ctrl;
    reg [15:0]              bytes_remaining;
    reg [15:0]              total_len;
    
    // FIFO
    reg [7:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [FIFO_ADDR_W-1:0] fifo_wr_ptr;
    reg [FIFO_ADDR_W-1:0] fifo_rd_ptr;
    reg [FIFO_ADDR_W:0]   fifo_count;
    
    wire fifo_full  = (fifo_count >= FIFO_DEPTH - AXI_BYTES);
    wire fifo_empty = (fifo_count == 0);
    wire [FIFO_ADDR_W:0] fifo_space = FIFO_DEPTH - fifo_count;
    
    // Burst calculation
    reg [7:0] burst_len;
    reg [15:0] burst_bytes;
    
    // Streaming state
    reg [15:0] stream_cnt;
    reg        is_first_byte;
    
    // AXI read byte extraction
    reg [2:0] rdata_byte_idx;
    reg [AXI_DATA_W-1:0] rdata_buf;
    reg [3:0] rdata_bytes_left;
    
    // Temporary calculation variables
    integer i;
    reg [15:0] max_bytes;
    reg [15:0] boundary_bytes;
    reg [7:0]  calc_len;
    
    //--------------------------------------------------------------------------
    // Status
    //--------------------------------------------------------------------------
    assign busy   = (state != ST_IDLE);
    assign halted = !enable || (state == ST_ERROR);

    //--------------------------------------------------------------------------
    // Main State Machine
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            
            // Descriptor interface
            desc_ready <= 1'b0;
            wb_valid   <= 1'b0;
            wb_index   <= 16'd0;
            wb_status  <= 32'd0;
            
            // AXI read
            m_axi_arvalid <= 1'b0;
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen   <= 8'd0;
            m_axi_rready  <= 1'b0;
            
            // AXI-Stream
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= {AXIS_DATA_W{1'b0}};
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 1'b0;
            
            // Internal
            cur_addr   <= {ADDR_WIDTH{1'b0}};
            cur_len    <= 16'd0;
            cur_index  <= 16'd0;
            cur_ctrl   <= 32'd0;
            bytes_remaining <= 16'd0;
            total_len  <= 16'd0;
            burst_len  <= 8'd0;
            burst_bytes <= 16'd0;
            stream_cnt <= 16'd0;
            is_first_byte <= 1'b1;
            rdata_byte_idx <= 3'd0;
            rdata_buf <= {AXI_DATA_W{1'b0}};
            rdata_bytes_left <= 4'd0;
            
            // FIFO
            fifo_wr_ptr <= {FIFO_ADDR_W{1'b0}};
            fifo_rd_ptr <= {FIFO_ADDR_W{1'b0}};
            fifo_count  <= {(FIFO_ADDR_W+1){1'b0}};
            
            // Status
            error <= 1'b0;
            tx_pkt_cnt  <= 32'd0;
            tx_byte_cnt <= 32'd0;
            
        end else if (soft_reset) begin
            state <= ST_IDLE;
            desc_ready <= 1'b0;
            wb_valid   <= 1'b0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            m_axis_tvalid <= 1'b0;
            fifo_wr_ptr <= {FIFO_ADDR_W{1'b0}};
            fifo_rd_ptr <= {FIFO_ADDR_W{1'b0}};
            fifo_count  <= {(FIFO_ADDR_W+1){1'b0}};
            error <= 1'b0;
            
        end else begin
            // Default de-assertions
            if (m_axi_arready) m_axi_arvalid <= 1'b0;
            if (wb_ready) wb_valid <= 1'b0;
            
            case (state)
                //--------------------------------------------------------------
                // Idle - Wait for descriptor
                //--------------------------------------------------------------
                ST_IDLE: begin
                    desc_ready <= enable;
                    is_first_byte <= 1'b1;
                    
                    if (enable && desc_valid && desc_ready) begin
                        // Latch descriptor
                        cur_addr   <= desc_buf_addr;
                        cur_len    <= desc_buf_len;
                        cur_index  <= desc_index;
                        cur_ctrl   <= desc_ctrl;
                        bytes_remaining <= desc_buf_len;
                        total_len  <= desc_buf_len;
                        
                        desc_ready <= 1'b0;
                        state <= ST_CALC_BURST;
                    end
                end
                
                //--------------------------------------------------------------
                // Calculate burst parameters
                //--------------------------------------------------------------
                ST_CALC_BURST: begin
                    // Calculate how many bytes to fetch
                    if (bytes_remaining == 0) begin
                        // Done fetching, stream out from FIFO
                        state <= ST_STREAM_OUT;
                    end else if (fifo_full) begin
                        // FIFO full, stream some data first
                        state <= ST_STREAM_OUT;
                    end else begin
                        // Calculate burst length
                        // Limited by: remaining bytes, max burst, FIFO space, 4K boundary
                        max_bytes = (bytes_remaining < fifo_space) ? bytes_remaining : fifo_space[15:0];
                        max_bytes = (max_bytes < MAX_BURST_LEN * AXI_BYTES) ? max_bytes : (MAX_BURST_LEN * AXI_BYTES);
                        
                        // 4K boundary check
                        boundary_bytes = 16'h1000 - cur_addr[11:0];
                        if (max_bytes > boundary_bytes)
                            max_bytes = boundary_bytes;
                        
                        // Convert to burst length (0-based)
                        calc_len = (max_bytes + AXI_BYTES - 1) / AXI_BYTES - 1;
                        
                        burst_len   <= calc_len;
                        burst_bytes <= (calc_len + 1) * AXI_BYTES;
                        
                        state <= ST_ISSUE_AR;
                    end
                end
                
                //--------------------------------------------------------------
                // Issue AXI read
                //--------------------------------------------------------------
                ST_ISSUE_AR: begin
                    m_axi_arvalid <= 1'b1;
                    m_axi_araddr  <= cur_addr;
                    m_axi_arlen   <= burst_len;
                    m_axi_rready  <= 1'b1;
                    rdata_bytes_left <= 4'd0;
                    
                    state <= ST_READ_DATA;
                end
                
                //--------------------------------------------------------------
                // Read data from AXI and store in FIFO
                //--------------------------------------------------------------
                ST_READ_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        // Store received data into FIFO byte by byte
                        for (i = 0; i < AXI_BYTES; i = i + 1) begin
                            if (bytes_remaining > 0) begin
                                fifo_mem[(fifo_wr_ptr + i) & (FIFO_DEPTH-1)] <= 
                                    m_axi_rdata[i*8 +: 8];
                            end
                        end
                        
                        // Update pointers
                        if (bytes_remaining >= AXI_BYTES) begin
                            fifo_wr_ptr <= fifo_wr_ptr + AXI_BYTES;
                            fifo_count  <= fifo_count + AXI_BYTES;
                            bytes_remaining <= bytes_remaining - AXI_BYTES;
                            cur_addr <= cur_addr + AXI_BYTES;
                        end else begin
                            fifo_wr_ptr <= fifo_wr_ptr + bytes_remaining[FIFO_ADDR_W-1:0];
                            fifo_count  <= fifo_count + bytes_remaining;
                            cur_addr <= cur_addr + bytes_remaining;
                            bytes_remaining <= 16'd0;
                        end
                        
                        // Check for errors
                        if (m_axi_rresp != 2'b00) begin
                            error <= 1'b1;
                            state <= ST_ERROR;
                        end else if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            state <= ST_CALC_BURST;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                // Stream data to MAC
                //--------------------------------------------------------------
                ST_STREAM_OUT: begin
                    if (!fifo_empty || m_axis_tvalid) begin
                        if (!m_axis_tvalid || m_axis_tready) begin
                            if (!fifo_empty) begin
                                m_axis_tvalid <= 1'b1;
                                m_axis_tdata  <= fifo_mem[fifo_rd_ptr];
                                m_axis_tuser  <= is_first_byte;  // SOF
                                
                                fifo_rd_ptr <= fifo_rd_ptr + 1;
                                fifo_count  <= fifo_count - 1;
                                stream_cnt  <= stream_cnt + 1;
                                is_first_byte <= 1'b0;
                                
                                // Check if this is last byte
                                if (stream_cnt + 1 >= total_len) begin
                                    m_axis_tlast <= 1'b1;
                                end else begin
                                    m_axis_tlast <= 1'b0;
                                end
                            end
                        end
                        
                        // Check if transfer complete
                        if (m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;
                            
                            // Update statistics
                            tx_pkt_cnt  <= tx_pkt_cnt + 1;
                            tx_byte_cnt <= tx_byte_cnt + total_len;
                            
                            // Prepare writeback
                            stream_cnt <= 16'd0;
                            state <= ST_WRITEBACK;
                        end
                    end else if (bytes_remaining > 0) begin
                        // Need more data from memory
                        state <= ST_CALC_BURST;
                    end else begin
                        // All data in FIFO, continue streaming
                        // This should not happen normally
                    end
                end
                
                //--------------------------------------------------------------
                // Writeback descriptor
                //--------------------------------------------------------------
                ST_WRITEBACK: begin
                    wb_valid  <= 1'b1;
                    wb_index  <= cur_index;
                    wb_status <= {28'd0, 
                                  1'b0,         // Reserved
                                  1'b0,         // Error
                                  1'b1,         // Done
                                  1'b0};        // OWN=0 (return to CPU)
                    
                    state <= ST_WAIT_WB;
                end
                
                ST_WAIT_WB: begin
                    if (wb_ready) begin
                        wb_valid <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                // Error state
                //--------------------------------------------------------------
                ST_ERROR: begin
                    // Stuck until reset
                    m_axis_tvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                end
                
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
