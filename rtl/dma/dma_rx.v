//==============================================================================
// File: dma_rx.v
// Description: RX DMA Engine
//
// Purpose:
//   Consumes incoming packets from the MAC's AXI-Stream RX interface and
//   writes them to system memory based on descriptors. Handles packet
//   assembly, status reporting, and descriptor completion.
//
// Architecture:
//   - Receives data from AXI-Stream RX interface
//   - Buffers in internal FIFO for rate matching
//   - Issues AXI-MM write bursts to store packet data
//   - Triggers descriptor writeback with status and actual length
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`include "dma_pkg.v"

module dma_rx #(
    parameter ADDR_WIDTH    = 64,       // AXI address width
    parameter AXI_DATA_W    = 64,       // AXI-MM data width
    parameter AXIS_DATA_W   = 8,        // AXI-Stream data width (MAC side)
    parameter MAX_BURST_LEN = 16,       // Max AXI burst length
    parameter FIFO_DEPTH    = 4096      // Internal FIFO depth (bytes)
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
    input  wire [15:0]              desc_buf_len,   // Max buffer size
    input  wire [31:0]              desc_ctrl,
    input  wire [15:0]              desc_index,
    
    // Writeback Interface (to dma_desc)
    output reg                      wb_valid,
    input  wire                     wb_ready,
    output reg  [15:0]              wb_index,
    output reg  [15:0]              wb_length,      // Actual received length
    output reg  [31:0]              wb_status,
    
    //--------------------------------------------------------------------------
    // AXI4 Master Write Interface (for packet data)
    //--------------------------------------------------------------------------
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,
    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output reg  [7:0]               m_axi_awlen,
    output wire [2:0]               m_axi_awsize,
    output wire [1:0]               m_axi_awburst,
    output wire [3:0]               m_axi_awid,
    
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,
    output reg  [AXI_DATA_W-1:0]    m_axi_wdata,
    output reg  [AXI_DATA_W/8-1:0]  m_axi_wstrb,
    output reg                      m_axi_wlast,
    
    input  wire                     m_axi_bvalid,
    output reg                      m_axi_bready,
    input  wire [1:0]               m_axi_bresp,
    input  wire [3:0]               m_axi_bid,
    
    //--------------------------------------------------------------------------
    // AXI-Stream RX Interface (from MAC)
    //--------------------------------------------------------------------------
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire [AXIS_DATA_W-1:0]   s_axis_tdata,
    input  wire                     s_axis_tlast,
    input  wire                     s_axis_tuser,   // Error indicator on tlast
    
    //--------------------------------------------------------------------------
    // Statistics
    //--------------------------------------------------------------------------
    output reg  [31:0]              rx_pkt_cnt,
    output reg  [31:0]              rx_byte_cnt,
    output reg  [31:0]              rx_drop_cnt     // Dropped due to no descriptor
);

    //--------------------------------------------------------------------------
    // Local Parameters
    //--------------------------------------------------------------------------
    localparam AXI_BYTES = AXI_DATA_W / 8;
    localparam FIFO_ADDR_W = $clog2(FIFO_DEPTH);
    
    // AXI configuration
    assign m_axi_awsize  = $clog2(AXI_BYTES);
    assign m_axi_awburst = 2'b01;  // INCR
    assign m_axi_awid    = 4'h2;   // RX uses ID=2

    //--------------------------------------------------------------------------
    // State Machine
    //--------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE         = 4'd0,
        ST_WAIT_SOF     = 4'd1,
        ST_RECEIVE      = 4'd2,
        ST_CALC_BURST   = 4'd3,
        ST_ISSUE_AW     = 4'd4,
        ST_WRITE_DATA   = 4'd5,
        ST_WAIT_B       = 4'd6,
        ST_WRITEBACK    = 4'd7,
        ST_WAIT_WB      = 4'd8,
        ST_DROP_PKT     = 4'd9,
        ST_ERROR        = 4'd10;
    
    reg [3:0] state;
    
    //--------------------------------------------------------------------------
    // Internal Registers
    //--------------------------------------------------------------------------
    // Current descriptor info
    reg [ADDR_WIDTH-1:0]    cur_addr;
    reg [15:0]              cur_max_len;
    reg [15:0]              cur_index;
    reg [31:0]              cur_ctrl;
    reg [15:0]              bytes_written;
    reg [15:0]              pkt_len;
    reg                     pkt_error;
    
    // FIFO with metadata
    reg [7:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [FIFO_ADDR_W-1:0] fifo_wr_ptr;
    reg [FIFO_ADDR_W-1:0] fifo_rd_ptr;
    reg [FIFO_ADDR_W:0]   fifo_count;
    
    // Packet boundary tracking
    reg [FIFO_ADDR_W:0]   pkt_end_ptr;    // Where current packet ends
    reg                   pkt_complete;    // Full packet in FIFO
    reg                   eof_received;
    
    wire fifo_full  = (fifo_count >= FIFO_DEPTH - 16);
    wire fifo_empty = (fifo_count == 0);
    
    // Burst calculation
    reg [7:0] burst_len;
    reg [15:0] burst_bytes;
    reg [15:0] bytes_to_write;
    
    // Write data assembly
    reg [2:0] wdata_byte_idx;
    reg [AXI_DATA_W-1:0] wdata_buf;
    reg [AXI_BYTES-1:0] wstrb_buf;
    
    // Temporary calculation variables
    integer i;
    reg [15:0] max_bytes;
    reg [15:0] boundary_bytes;
    reg [15:0] remaining;
    reg [7:0]  calc_len;
    reg [AXI_DATA_W-1:0] new_wdata;
    reg [AXI_BYTES-1:0] new_wstrb;
    reg [15:0] bytes_this_beat;
    reg is_last_beat;

    //--------------------------------------------------------------------------
    // Status
    //--------------------------------------------------------------------------
    assign busy   = (state != ST_IDLE) && (state != ST_WAIT_SOF);
    assign halted = !enable || (state == ST_ERROR);
    
    // Accept data when enabled and FIFO has space (unless dropping)
    assign s_axis_tready = enable && !fifo_full && (state != ST_DROP_PKT);

    //--------------------------------------------------------------------------
    // FIFO Write Logic (receive from MAC)
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr  <= {FIFO_ADDR_W{1'b0}};
            pkt_len      <= 16'd0;
            pkt_error    <= 1'b0;
            eof_received <= 1'b0;
            pkt_complete <= 1'b0;
            pkt_end_ptr  <= {(FIFO_ADDR_W+1){1'b0}};
            
        end else if (soft_reset) begin
            fifo_wr_ptr  <= {FIFO_ADDR_W{1'b0}};
            pkt_len      <= 16'd0;
            pkt_error    <= 1'b0;
            eof_received <= 1'b0;
            pkt_complete <= 1'b0;
            
        end else begin
            // Clear complete flag when packet processing starts
            if (state == ST_CALC_BURST && pkt_complete) begin
                // Keep complete until packet is fully written
            end
            
            if (s_axis_tvalid && s_axis_tready) begin
                // Store byte in FIFO
                fifo_mem[fifo_wr_ptr] <= s_axis_tdata;
                fifo_wr_ptr <= fifo_wr_ptr + 1;
                pkt_len <= pkt_len + 1;
                
                if (s_axis_tlast) begin
                    // End of packet
                    eof_received <= 1'b1;
                    pkt_complete <= 1'b1;
                    pkt_end_ptr  <= fifo_wr_ptr + 1;
                    
                    // tuser on tlast indicates error (e.g., CRC error)
                    if (s_axis_tuser) begin
                        pkt_error <= 1'b1;
                    end
                end
            end
            
            // Reset packet state after writeback
            if (state == ST_WAIT_WB && wb_ready) begin
                pkt_len      <= 16'd0;
                pkt_error    <= 1'b0;
                eof_received <= 1'b0;
                pkt_complete <= 1'b0;
            end
        end
    end
    
    // FIFO count management
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_count <= {(FIFO_ADDR_W+1){1'b0}};
        end else if (soft_reset) begin
            fifo_count <= {(FIFO_ADDR_W+1){1'b0}};
        end else begin
            case ({s_axis_tvalid && s_axis_tready, 
                   m_axi_wvalid && m_axi_wready})
                2'b10: fifo_count <= fifo_count + 1;
                2'b01: fifo_count <= (fifo_count >= AXI_BYTES) ? 
                                     fifo_count - AXI_BYTES : 0;
                2'b11: fifo_count <= fifo_count + 1 - 
                                     ((fifo_count >= AXI_BYTES) ? AXI_BYTES : fifo_count);
                default: ; // No change
            endcase
        end
    end

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
            wb_length  <= 16'd0;
            wb_status  <= 32'd0;
            
            // AXI write
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= {AXI_DATA_W{1'b0}};
            m_axi_wstrb   <= {AXI_BYTES{1'b1}};
            m_axi_wlast   <= 1'b0;
            m_axi_bready  <= 1'b0;
            
            // Internal
            cur_addr      <= {ADDR_WIDTH{1'b0}};
            cur_max_len   <= 16'd0;
            cur_index     <= 16'd0;
            cur_ctrl      <= 32'd0;
            bytes_written <= 16'd0;
            bytes_to_write <= 16'd0;
            burst_len     <= 8'd0;
            burst_bytes   <= 16'd0;
            fifo_rd_ptr   <= {FIFO_ADDR_W{1'b0}};
            wdata_byte_idx <= 3'd0;
            wdata_buf     <= {AXI_DATA_W{1'b0}};
            wstrb_buf     <= {AXI_BYTES{1'b0}};
            
            // Status
            error <= 1'b0;
            rx_pkt_cnt  <= 32'd0;
            rx_byte_cnt <= 32'd0;
            rx_drop_cnt <= 32'd0;
            
        end else if (soft_reset) begin
            state <= ST_IDLE;
            desc_ready    <= 1'b0;
            wb_valid      <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            fifo_rd_ptr   <= {FIFO_ADDR_W{1'b0}};
            error <= 1'b0;
            
        end else begin
            // Default de-assertions
            if (m_axi_awready) m_axi_awvalid <= 1'b0;
            if (m_axi_wready && m_axi_wlast) begin
                m_axi_wvalid <= 1'b0;
                m_axi_wlast  <= 1'b0;
            end
            if (wb_ready) wb_valid <= 1'b0;
            
            case (state)
                //--------------------------------------------------------------
                // Idle - Wait for descriptor and packet
                //--------------------------------------------------------------
                ST_IDLE: begin
                    desc_ready <= enable;
                    bytes_written <= 16'd0;
                    
                    if (enable && desc_valid && desc_ready) begin
                        // Latch descriptor
                        cur_addr    <= desc_buf_addr;
                        cur_max_len <= desc_buf_len;
                        cur_index   <= desc_index;
                        cur_ctrl    <= desc_ctrl;
                        
                        desc_ready <= 1'b0;
                        state <= ST_WAIT_SOF;
                    end
                end
                
                //--------------------------------------------------------------
                // Wait for start of packet
                //--------------------------------------------------------------
                ST_WAIT_SOF: begin
                    if (pkt_complete || eof_received) begin
                        // Packet available, start writing
                        bytes_to_write <= pkt_len;
                        state <= ST_CALC_BURST;
                    end else if (fifo_count >= (FIFO_DEPTH / 2)) begin
                        // Half full, start streaming to memory
                        bytes_to_write <= fifo_count[15:0];
                        state <= ST_CALC_BURST;
                    end
                end
                
                //--------------------------------------------------------------
                // Calculate burst parameters
                //--------------------------------------------------------------
                ST_CALC_BURST: begin
                    if (bytes_to_write == 0 || bytes_written >= cur_max_len) begin
                        // Done writing, do writeback
                        state <= ST_WRITEBACK;
                    end else if (fifo_count == 0 && !eof_received) begin
                        // Wait for more data
                        state <= ST_WAIT_SOF;
                    end else begin
                        // Calculate burst
                        remaining = bytes_to_write - bytes_written;
                        max_bytes = (remaining < fifo_count) ? remaining : fifo_count[15:0];
                        max_bytes = (max_bytes < MAX_BURST_LEN * AXI_BYTES) ? 
                                    max_bytes : (MAX_BURST_LEN * AXI_BYTES);
                        
                        // Check buffer limit
                        if (bytes_written + max_bytes > cur_max_len)
                            max_bytes = cur_max_len - bytes_written;
                        
                        // 4K boundary
                        boundary_bytes = 16'h1000 - cur_addr[11:0];
                        if (max_bytes > boundary_bytes)
                            max_bytes = boundary_bytes;
                        
                        calc_len = (max_bytes + AXI_BYTES - 1) / AXI_BYTES - 1;
                        
                        burst_len   <= calc_len;
                        burst_bytes <= (calc_len + 1) * AXI_BYTES;
                        
                        state <= ST_ISSUE_AW;
                    end
                end
                
                //--------------------------------------------------------------
                // Issue AXI write address
                //--------------------------------------------------------------
                ST_ISSUE_AW: begin
                    m_axi_awvalid <= 1'b1;
                    m_axi_awaddr  <= cur_addr;
                    m_axi_awlen   <= burst_len;
                    wdata_byte_idx <= 3'd0;
                    
                    state <= ST_WRITE_DATA;
                end
                
                //--------------------------------------------------------------
                // Write data to memory
                //--------------------------------------------------------------
                ST_WRITE_DATA: begin
                    if (!m_axi_wvalid || m_axi_wready) begin
                        // Assemble write data from FIFO
                        new_wdata = {AXI_DATA_W{1'b0}};
                        new_wstrb = {AXI_BYTES{1'b0}};
                        bytes_this_beat = 0;
                        
                        for (i = 0; i < AXI_BYTES; i = i + 1) begin
                            if (fifo_count > i && bytes_written + i < bytes_to_write &&
                                bytes_written + i < cur_max_len) begin
                                new_wdata[i*8 +: 8] = fifo_mem[(fifo_rd_ptr + i) & (FIFO_DEPTH-1)];
                                new_wstrb[i] = 1'b1;
                                bytes_this_beat = bytes_this_beat + 1;
                            end
                        end
                        
                        m_axi_wdata  <= new_wdata;
                        m_axi_wstrb  <= new_wstrb;
                        m_axi_wvalid <= 1'b1;
                        
                        // Update pointers
                        fifo_rd_ptr   <= fifo_rd_ptr + bytes_this_beat[FIFO_ADDR_W-1:0];
                        bytes_written <= bytes_written + bytes_this_beat;
                        cur_addr      <= cur_addr + AXI_BYTES;
                        
                        // Check if last beat of burst
                        is_last_beat = (bytes_written + bytes_this_beat >= bytes_to_write) ||
                                       (bytes_written + bytes_this_beat >= cur_max_len) ||
                                       ((bytes_written + bytes_this_beat - bytes_written) >= burst_bytes);
                        
                        // Simplified: count beats
                        if (wdata_byte_idx >= burst_len) begin
                            m_axi_wlast <= 1'b1;
                            m_axi_bready <= 1'b1;
                            state <= ST_WAIT_B;
                        end else begin
                            m_axi_wlast <= 1'b0;
                            wdata_byte_idx <= wdata_byte_idx + 1;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                // Wait for write response
                //--------------------------------------------------------------
                ST_WAIT_B: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        
                        if (m_axi_bresp != 2'b00) begin
                            error <= 1'b1;
                            state <= ST_ERROR;
                        end else begin
                            // More data to write?
                            if (bytes_written < bytes_to_write && bytes_written < cur_max_len) begin
                                state <= ST_CALC_BURST;
                            end else begin
                                state <= ST_WRITEBACK;
                            end
                        end
                    end
                end
                
                //--------------------------------------------------------------
                // Writeback descriptor
                //--------------------------------------------------------------
                ST_WRITEBACK: begin
                    wb_valid  <= 1'b1;
                    wb_index  <= cur_index;
                    wb_length <= bytes_written;
                    wb_status <= {28'd0,
                                  pkt_error,    // Error
                                  1'b1,         // LAST (single descriptor per packet)
                                  1'b1,         // DONE
                                  1'b0};        // OWN=0
                    
                    // Update stats
                    rx_pkt_cnt  <= rx_pkt_cnt + 1;
                    rx_byte_cnt <= rx_byte_cnt + bytes_written;
                    
                    state <= ST_WAIT_WB;
                end
                
                ST_WAIT_WB: begin
                    if (wb_ready) begin
                        wb_valid <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                // Drop packet (no descriptor available)
                //--------------------------------------------------------------
                ST_DROP_PKT: begin
                    // This state is entered from external logic
                    // Drain FIFO until end of packet
                    if (s_axis_tlast && s_axis_tvalid) begin
                        rx_drop_cnt <= rx_drop_cnt + 1;
                        state <= ST_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                // Error state
                //--------------------------------------------------------------
                ST_ERROR: begin
                    // Stuck until reset
                    m_axi_wvalid <= 1'b0;
                    m_axi_bready <= 1'b0;
                end
                
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
