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
    parameter AXI_DATA_W    = 64,       // AXI-MM data width (must be power of 2, >= 8)
    parameter AXIS_DATA_W   = 8,        // AXI-Stream data width (MAC side, must be 8)
    parameter MAX_BURST_LEN = 16,       // Max AXI burst length (1-256)
    parameter FIFO_DEPTH    = 4096     // Internal FIFO depth in bytes (must be power of 2)
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
    localparam AXI_BYTES      = AXI_DATA_W / 8;
    localparam AXIS_BYTES     = AXIS_DATA_W / 8;  // Should be 1
    localparam FIFO_ADDR_W    = $clog2(FIFO_DEPTH);
    localparam FIFO_COUNT_W   = FIFO_ADDR_W + 1;  // One extra bit for full detection
    localparam PKT_LEN_W      = 16;  // Fixed at 16 bits for packet length (max 64KB)
    
    // FIFO almost full threshold (leave headroom for in-flight data)
    localparam [FIFO_COUNT_W-1:0] FIFO_AFULL_THRESH = FIFO_DEPTH - (AXI_BYTES * 4);
    
    // AXI 4KB boundary in bytes
    localparam AXI_4K_BOUNDARY = 12;
    
    // AXI configuration
    assign m_axi_awsize  = $clog2(AXI_BYTES);
    assign m_axi_awburst = 2'b01;  // INCR
    assign m_axi_awid    = 4'h2;   // RX uses ID=2

    //--------------------------------------------------------------------------
    // State Machine
    //--------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE         = 4'd0,
        ST_WAIT_PKT     = 4'd1,
        ST_RECEIVE      = 4'd2,
        ST_CALC_BURST   = 4'd3,
        ST_ISSUE_AW     = 4'd4,
        ST_WRITE_DATA   = 4'd5,
        ST_WAIT_B       = 4'd6,
        ST_WRITEBACK    = 4'd7,
        ST_DROP_PKT     = 4'd8,
        ST_ERROR        = 4'd9;
    
    reg [3:0] state, next_state;
    
    //--------------------------------------------------------------------------
    // Internal Registers
    //--------------------------------------------------------------------------
    // Current descriptor info
    reg [ADDR_WIDTH-1:0]    cur_addr;
    reg [15:0]              cur_max_len;
    reg [15:0]              cur_index;
    reg [31:0]              cur_ctrl;
    reg [15:0]              bytes_written;      // Bytes written to memory in current packet
    reg [15:0]              pkt_len;            // Current packet length being received
    reg                     pkt_error;          // Packet had error flag
    reg                     pkt_complete;       // Complete packet in FIFO
    
    // FIFO - byte-addressable memory
    reg [7:0]               fifo_mem [0:FIFO_DEPTH-1];
    reg [FIFO_ADDR_W-1:0]   fifo_wr_ptr;
    reg [FIFO_ADDR_W-1:0]   fifo_rd_ptr;
    reg [FIFO_COUNT_W-1:0]  fifo_count;         // Number of valid bytes in FIFO
    
    // FIFO control signals
    wire                    fifo_wr_en;
    wire                    fifo_rd_en;
    wire [7:0]              fifo_wr_data;
    reg  [7:0]              fifo_rd_bytes;      // How many bytes to read this cycle (0 to AXI_BYTES)
    
    wire                    fifo_empty;
    wire                    fifo_afull;
    
    // Burst tracking
    reg [7:0]               burst_len;          // AXI burst length (beats - 1)
    reg [7:0]               burst_beat_cnt;     // Current beat in burst
    reg [15:0]              burst_bytes_total;  // Total bytes in this burst
    reg [15:0]              bytes_remaining;    // Bytes left to write for this packet
    
    // Burst calculation temporaries
    reg [15:0]              max_burst_bytes;
    reg [15:0]              boundary_limit;
    reg [15:0]              buffer_limit;
    reg [15:0]              fifo_limit;
    reg [15:0]              min_bytes;
    reg [7:0]               calculated_len;
    
    // Write data assembly temporaries
    reg [AXI_DATA_W-1:0]    assembled_data;
    reg [AXI_BYTES-1:0]     assembled_strb;
    reg [FIFO_ADDR_W-1:0]   rd_idx;
    reg [7:0]               valid_bytes;
    
    // Loop counter
    integer i;
    
    //--------------------------------------------------------------------------
    // FIFO Status Flags
    //--------------------------------------------------------------------------
    assign fifo_empty = (fifo_count == {FIFO_COUNT_W{1'b0}});
    assign fifo_afull = (fifo_count >= FIFO_AFULL_THRESH);
    
    //--------------------------------------------------------------------------
    // Status Outputs
    //--------------------------------------------------------------------------
    assign busy   = (state != ST_IDLE);
    assign halted = !enable || (state == ST_ERROR);
    
    // Accept stream data when enabled, FIFO has space, and not in drop state
    assign s_axis_tready = enable && !fifo_afull && 
                           (state != ST_DROP_PKT) && (state != ST_ERROR);

    //--------------------------------------------------------------------------
    // FIFO Write Interface (from AXI-Stream)
    //--------------------------------------------------------------------------
    assign fifo_wr_en   = s_axis_tvalid && s_axis_tready;
    assign fifo_wr_data = s_axis_tdata;
    
    //--------------------------------------------------------------------------
    // FIFO Read Interface (to AXI-MM)
    //--------------------------------------------------------------------------
    assign fifo_rd_en = m_axi_wvalid && m_axi_wready;
    
    // Calculate how many bytes we'll read from FIFO this cycle
    always @(*) begin
        if (fifo_rd_en) begin
            if (fifo_count >= AXI_BYTES)
                fifo_rd_bytes = AXI_BYTES;
            else
                fifo_rd_bytes = {{(8-FIFO_COUNT_W){1'b0}}, fifo_count};
            
            // Also limit by remaining bytes to write
            if (bytes_remaining < AXI_BYTES)
                fifo_rd_bytes = bytes_remaining[7:0];
        end else begin
            fifo_rd_bytes = 8'd0;
        end
    end

    //--------------------------------------------------------------------------
    // FIFO Memory and Pointer Management
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr  <= {FIFO_ADDR_W{1'b0}};
            fifo_rd_ptr  <= {FIFO_ADDR_W{1'b0}};
            fifo_count   <= {FIFO_COUNT_W{1'b0}};
            
        end else if (soft_reset) begin
            fifo_wr_ptr  <= {FIFO_ADDR_W{1'b0}};
            fifo_rd_ptr  <= {FIFO_ADDR_W{1'b0}};
            fifo_count   <= {FIFO_COUNT_W{1'b0}};
            
        end else begin
            // Write to FIFO
            if (fifo_wr_en) begin
                fifo_mem[fifo_wr_ptr] <= fifo_wr_data;
                fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
            end
            
            // Read from FIFO (pointer update)
            if (fifo_rd_en) begin
                fifo_rd_ptr <= fifo_rd_ptr + fifo_rd_bytes[FIFO_ADDR_W-1:0];
            end
            
            // Update count (write and read can happen simultaneously)
            case ({fifo_wr_en, fifo_rd_en})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: begin
                    if (fifo_count >= fifo_rd_bytes)
                        fifo_count <= fifo_count - fifo_rd_bytes;
                    else
                        fifo_count <= {FIFO_COUNT_W{1'b0}};
                end
                2'b11: begin
                    if (fifo_count >= fifo_rd_bytes)
                        fifo_count <= fifo_count + 1'b1 - fifo_rd_bytes;
                    else
                        fifo_count <= 1'b1;  // Just the written byte
                end
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Packet Reception Tracking
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_len      <= 16'd0;
            pkt_error    <= 1'b0;
            pkt_complete <= 1'b0;
            
        end else if (soft_reset) begin
            pkt_len      <= 16'd0;
            pkt_error    <= 1'b0;
            pkt_complete <= 1'b0;
            
        end else begin
            // Accumulate packet length as bytes arrive
            if (fifo_wr_en) begin
                if (s_axis_tlast) begin
                    // End of packet
                    pkt_complete <= 1'b1;
                    pkt_len      <= pkt_len + 16'd1;
                    
                    // Check for error indication
                    if (s_axis_tuser) begin
                        pkt_error <= 1'b1;
                    end
                end else begin
                    pkt_len <= pkt_len + 16'd1;
                end
            end
            
            // Clear packet state after writeback completes
            if (state == ST_WRITEBACK && wb_valid && wb_ready) begin
                pkt_len      <= 16'd0;
                pkt_error    <= 1'b0;
                pkt_complete <= 1'b0;
            end
            
            // Clear packet state when dropping
            if (state == ST_DROP_PKT && s_axis_tlast && s_axis_tvalid) begin
                pkt_len      <= 16'd0;
                pkt_error    <= 1'b0;
                pkt_complete <= 1'b0;
            end
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
            
            // AXI write interface
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= {AXI_DATA_W{1'b0}};
            m_axi_wstrb   <= {AXI_BYTES{1'b0}};
            m_axi_wlast   <= 1'b0;
            m_axi_bready  <= 1'b0;
            
            // Internal state
            cur_addr       <= {ADDR_WIDTH{1'b0}};
            cur_max_len    <= 16'd0;
            cur_index      <= 16'd0;
            cur_ctrl       <= 32'd0;
            bytes_written  <= 16'd0;
            bytes_remaining <= 16'd0;
            burst_len      <= 8'd0;
            burst_beat_cnt <= 8'd0;
            burst_bytes_total <= 16'd0;
            
            // Burst calc temps
            max_burst_bytes <= 16'd0;
            boundary_limit  <= 16'd0;
            buffer_limit    <= 16'd0;
            fifo_limit      <= 16'd0;
            min_bytes       <= 16'd0;
            calculated_len  <= 8'd0;
            
            // Write assembly temps
            assembled_data  <= {AXI_DATA_W{1'b0}};
            assembled_strb  <= {AXI_BYTES{1'b0}};
            rd_idx          <= {FIFO_ADDR_W{1'b0}};
            valid_bytes     <= 8'd0;
            
            // Status
            error       <= 1'b0;
            rx_pkt_cnt  <= 32'd0;
            rx_byte_cnt <= 32'd0;
            rx_drop_cnt <= 32'd0;
            
        end else if (soft_reset) begin
            state         <= ST_IDLE;
            desc_ready    <= 1'b0;
            wb_valid      <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wlast   <= 1'b0;
            m_axi_bready  <= 1'b0;
            error         <= 1'b0;
            
        end else begin
            // Default: clear single-cycle signals
            if (desc_ready && desc_valid)
                desc_ready <= 1'b0;
            
            if (m_axi_awvalid && m_axi_awready)
                m_axi_awvalid <= 1'b0;
            
            if (wb_valid && wb_ready)
                wb_valid <= 1'b0;
            
            case (state)
                //--------------------------------------------------------------
                // IDLE: Wait for descriptor
                //--------------------------------------------------------------
                ST_IDLE: begin
                    if (enable) begin
                        desc_ready <= 1'b1;
                        
                        if (desc_valid && desc_ready) begin
                            // Latch descriptor
                            cur_addr    <= desc_buf_addr;
                            cur_max_len <= desc_buf_len;
                            cur_index   <= desc_index;
                            cur_ctrl    <= desc_ctrl;
                            bytes_written <= 16'd0;
                            
                            desc_ready <= 1'b0;
                            state <= ST_WAIT_PKT;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                // WAIT_PKT: Wait for packet data
                //--------------------------------------------------------------
                ST_WAIT_PKT: begin
                    if (pkt_complete) begin
                        // Full packet received, start DMA
                        bytes_remaining <= pkt_len;
                        state <= ST_CALC_BURST;
                        
                    end else if (!fifo_empty && (fifo_count >= AXI_BYTES)) begin
                        // Streaming mode: start writing before packet completes
                        bytes_remaining <= {{(16-FIFO_COUNT_W){1'b0}}, fifo_count};
                        state <= ST_CALC_BURST;
                    end
                end
                
                //--------------------------------------------------------------
                // CALC_BURST: Calculate burst parameters
                //--------------------------------------------------------------
                ST_CALC_BURST: begin
                    if ((bytes_written >= cur_max_len) || (bytes_written >= pkt_len)) begin
                        // Done writing this packet
                        state <= ST_WRITEBACK;
                        
                    end else if (fifo_empty) begin
                        // Wait for more data
                        state <= ST_WAIT_PKT;
                        
                    end else begin
                        // Calculate maximum burst size
                        max_burst_bytes = MAX_BURST_LEN * AXI_BYTES;
                        
                        // Limit 1: Remaining packet bytes
                        if (pkt_len - bytes_written < max_burst_bytes)
                            min_bytes = pkt_len - bytes_written;
                        else
                            min_bytes = max_burst_bytes;
                        
                        // Limit 2: Descriptor buffer size
                        buffer_limit = cur_max_len - bytes_written;
                        if (min_bytes > buffer_limit)
                            min_bytes = buffer_limit;
                        
                        // Limit 3: FIFO available data
                        fifo_limit = {{(16-FIFO_COUNT_W){1'b0}}, fifo_count};
                        if (min_bytes > fifo_limit)
                            min_bytes = fifo_limit;
                        
                        // Limit 4: AXI 4KB boundary
                        boundary_limit = (16'h1000 - cur_addr[AXI_4K_BOUNDARY-1:0]);
                        if (min_bytes > boundary_limit)
                            min_bytes = boundary_limit;
                        
                        // Ensure at least 1 byte
                        if (min_bytes == 16'd0)
                            min_bytes = 16'd1;
                        
                        // Convert bytes to AXI beats (round up)
                        calculated_len = ((min_bytes + AXI_BYTES - 1) / AXI_BYTES) - 1;
                        
                        burst_len <= calculated_len;
                        burst_bytes_total <= (calculated_len + 1) * AXI_BYTES;
                        burst_beat_cnt <= 8'd0;
                        
                        state <= ST_ISSUE_AW;
                    end
                end
                
                //--------------------------------------------------------------
                // ISSUE_AW: Issue write address
                //--------------------------------------------------------------
                ST_ISSUE_AW: begin
                    if (!m_axi_awvalid || m_axi_awready) begin
                        m_axi_awvalid <= 1'b1;
                        m_axi_awaddr  <= cur_addr;
                        m_axi_awlen   <= burst_len;
                        
                        state <= ST_WRITE_DATA;
                    end
                end
                
                //--------------------------------------------------------------
                // WRITE_DATA: Stream data to AXI
                //--------------------------------------------------------------
                ST_WRITE_DATA: begin
                    if (!m_axi_wvalid || m_axi_wready) begin
                        // Assemble data from FIFO
                        assembled_data = {AXI_DATA_W{1'b0}};
                        assembled_strb = {AXI_BYTES{1'b0}};
                        valid_bytes = 8'd0;
                        
                        for (i = 0; i < AXI_BYTES; i = i + 1) begin
                            rd_idx = fifo_rd_ptr + i[FIFO_ADDR_W-1:0];
                            
                            if ((i < fifo_count) && 
                                (bytes_written + i < pkt_len) &&
                                (bytes_written + i < cur_max_len)) begin
                                
                                assembled_data[i*8 +: 8] = fifo_mem[rd_idx];
                                assembled_strb[i] = 1'b1;
                                valid_bytes = valid_bytes + 8'd1;
                            end
                        end
                        
                        m_axi_wdata  <= assembled_data;
                        m_axi_wstrb  <= assembled_strb;
                        m_axi_wvalid <= 1'b1;
                        m_axi_wlast  <= (burst_beat_cnt == burst_len);
                        
                        bytes_written <= bytes_written + valid_bytes[7:0];
                        bytes_remaining <= bytes_remaining - valid_bytes[7:0];
                        cur_addr <= cur_addr + AXI_BYTES;
                        
                        if (burst_beat_cnt == burst_len) begin
                            m_axi_bready <= 1'b1;
                            state <= ST_WAIT_B;
                        end else begin
                            burst_beat_cnt <= burst_beat_cnt + 8'd1;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                // WAIT_B: Wait for write response
                //--------------------------------------------------------------
                ST_WAIT_B: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        
                        if (m_axi_bresp != 2'b00) begin
                            // AXI error
                            error <= 1'b1;
                            state <= ST_ERROR;
                            
                        end else if ((bytes_written >= pkt_len) || 
                                     (bytes_written >= cur_max_len)) begin
                            // Packet complete
                            state <= ST_WRITEBACK;
                            
                        end else begin
                            // More data to transfer
                            state <= ST_CALC_BURST;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                // WRITEBACK: Update descriptor with status
                //--------------------------------------------------------------
                ST_WRITEBACK: begin
                    if (!wb_valid || wb_ready) begin
                        wb_valid  <= 1'b1;
                        wb_index  <= cur_index;
                        wb_length <= bytes_written;
                        wb_status <= {28'd0,
                                      pkt_error,    // [3] Error
                                      1'b1,         // [2] EOP (end of packet)
                                      1'b1,         // [1] Complete
                                      1'b0};        // [0] Owned by SW
                        
                        // Update statistics
                        rx_pkt_cnt  <= rx_pkt_cnt + 32'd1;
                        rx_byte_cnt <= rx_byte_cnt + {16'd0, bytes_written};
                        
                        if (wb_ready) begin
                            wb_valid <= 1'b0;
                            state <= ST_IDLE;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                // DROP_PKT: Discard packet (no descriptor available)
                //--------------------------------------------------------------
                ST_DROP_PKT: begin
                    // Wait for packet to complete, then discard
                    if (pkt_complete) begin
                        rx_drop_cnt <= rx_drop_cnt + 32'd1;
                        state <= ST_IDLE;
                    end
                end
                
                //--------------------------------------------------------------
                // ERROR: Fatal error state
                //--------------------------------------------------------------
                ST_ERROR: begin
                    // Remain here until reset
                    error <= 1'b1;
                end
                
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
