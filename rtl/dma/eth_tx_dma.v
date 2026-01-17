//==============================================================================
// Module: eth_tx_dma
// Description: TX DMA engine for Ethernet Controller
//
// Features:
//   - Descriptor-based packet transmission
//   - Reads TX descriptors from memory
//   - Fetches packet payload from memory via AXI4
//   - Streams data to MAC via AXI-Stream
//   - Updates descriptor status after transmission
//   - Ring buffer management
//   - Interrupt generation on completion/error
//
// Operation:
//   1. Fetch next TX descriptor from memory
//   2. Check ownership bit (CPU owned vs DMA owned)
//   3. Read packet buffer from memory address in descriptor
//   4. Stream packet data to MAC (assert tlast on last byte)
//   5. Wait for MAC completion
//   6. Write back descriptor status
//   7. Generate interrupt if enabled
//   8. Move to next descriptor
//
// Descriptor Format (128 bits):
//   [63:0]   - buffer_addr:   Physical address of packet buffer
//   [79:64]  - buffer_len:    Length of packet in bytes
//   [95:80]  - reserved
//   [96]     - OWN:           Ownership (0=CPU, 1=DMA)
//   [97]     - LAST:          Last descriptor in packet (for scatter-gather)
//   [98]     - CRC_EN:        Enable CRC generation
//   [99]     - INT_EN:        Enable interrupt on completion
//   [111:100]- reserved
//   [112]    - DONE:          Transmission complete (written by DMA)
//   [113]    - ERR:           Transmission error (written by DMA)
//   [127:114]- reserved
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_tx_dma #(
    parameter AXIS_DATA_WIDTH   = 8,
    parameter MEM_DATA_WIDTH    = 64,
    parameter MEM_ADDR_WIDTH    = 32,
    parameter DESC_ADDR_WIDTH   = 32,
    parameter DESC_PTR_WIDTH    = 8,
    parameter BUF_SIZE_WIDTH    = 14,
    parameter MAX_BURST         = 16
) (
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire                             dma_enable,
    
    // Descriptor ring configuration
    input  wire [DESC_ADDR_WIDTH-1:0]       desc_base_addr,
    input  wire [DESC_PTR_WIDTH-1:0]        desc_ring_size,
    
    // Descriptor fetch interface
    output reg                              desc_req,
    input  wire                             desc_ack,
    output reg  [DESC_ADDR_WIDTH-1:0]       desc_addr,
    input  wire [127:0]                     desc_data,
    input  wire                             desc_valid,
    
    // Descriptor writeback interface
    output reg                              desc_wb_req,
    input  wire                             desc_wb_ack,
    output reg  [DESC_ADDR_WIDTH-1:0]       desc_wb_addr,
    output reg  [127:0]                     desc_wb_data,
    
    // Memory read interface (to descriptor manager)
    output reg                              mem_rd_req,
    input  wire                             mem_rd_ack,
    output reg  [MEM_ADDR_WIDTH-1:0]        mem_rd_addr,
    output reg  [BUF_SIZE_WIDTH-1:0]        mem_rd_len,
    input  wire [MEM_DATA_WIDTH-1:0]        mem_rd_data,
    input  wire                             mem_rd_valid,
    input  wire                             mem_rd_last,
    output reg                              mem_rd_ready,
    
    // AXI-Stream to MAC
    output reg  [AXIS_DATA_WIDTH-1:0]       m_axis_tdata,
    output reg                              m_axis_tvalid,
    output reg                              m_axis_tlast,
    output reg                              m_axis_tuser,       // SOF
    input  wire                             m_axis_tready,
    
    // Status and interrupts
    output wire                             tx_busy,
    output reg  [31:0]                      tx_pkt_count,
    output reg  [31:0]                      tx_err_count,
    output reg                              int_tx_done,
    output reg                              int_tx_err
);

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam STATE_IDLE           = 4'h0;
    localparam STATE_FETCH_DESC     = 4'h1;
    localparam STATE_WAIT_DESC      = 4'h2;
    localparam STATE_CHECK_OWN      = 4'h3;
    localparam STATE_READ_MEM       = 4'h4;
    localparam STATE_WAIT_MEM       = 4'h5;
    localparam STATE_STREAM_DATA    = 4'h6;
    localparam STATE_WAIT_COMPLETE  = 4'h7;
    localparam STATE_WRITEBACK      = 4'h8;
    localparam STATE_WAIT_WB        = 4'h9;
    localparam STATE_NEXT_DESC      = 4'hA;
    localparam STATE_ERROR          = 4'hF;
    
    reg [3:0] state, next_state;
    
    //==========================================================================
    // Descriptor Ring Management
    //==========================================================================
    reg [DESC_PTR_WIDTH-1:0] desc_index;        // Current descriptor index
    reg [127:0]              current_desc;      // Latched descriptor
    reg [63:0]               buffer_addr;       // Buffer address from descriptor
    reg [15:0]               buffer_len;        // Buffer length from descriptor
    reg                      desc_own;          // Ownership bit
    reg                      desc_last;         // Last descriptor bit
    reg                      desc_crc_en;       // CRC enable bit
    reg                      desc_int_en;       // Interrupt enable bit
    
    //==========================================================================
    // Data Streaming
    //==========================================================================
    reg [BUF_SIZE_WIDTH-1:0] byte_count;        // Bytes streamed
    reg [BUF_SIZE_WIDTH-1:0] total_bytes;       // Total bytes to stream
    reg                      sof_flag;          // Start of frame flag
    reg [MEM_DATA_WIDTH-1:0] data_buffer;       // Data buffer from memory
    reg [3:0]                buffer_valid_bytes; // Valid bytes in buffer
    reg [2:0]                byte_offset;       // Byte offset within buffer
    
    //==========================================================================
    // Data Width Conversion (Memory width -> AXI-Stream width)
    //==========================================================================
    wire [AXIS_DATA_WIDTH-1:0] stream_byte;
    
    generate
        if (MEM_DATA_WIDTH == 64 && AXIS_DATA_WIDTH == 8) begin : gen_datapath_64to8
            // Extract byte based on byte_offset
            assign stream_byte = data_buffer[byte_offset*8 +: 8];
        end else begin : gen_datapath_default
            assign stream_byte = data_buffer[AXIS_DATA_WIDTH-1:0];
        end
    endgenerate
    
    //==========================================================================
    // Status
    //==========================================================================
    assign tx_busy = (state != STATE_IDLE);
    
    //==========================================================================
    // State Machine - Sequential Logic
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    //==========================================================================
    // State Machine - Combinational Logic
    //==========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (dma_enable) begin
                    next_state = STATE_FETCH_DESC;
                end
            end
            
            STATE_FETCH_DESC: begin
                if (desc_ack) begin
                    next_state = STATE_WAIT_DESC;
                end
            end
            
            STATE_WAIT_DESC: begin
                if (desc_valid) begin
                    next_state = STATE_CHECK_OWN;
                end
            end
            
            STATE_CHECK_OWN: begin
                if (desc_own) begin
                    next_state = STATE_READ_MEM;
                end else begin
                    next_state = STATE_IDLE;  // No more descriptors to process
                end
            end
            
            STATE_READ_MEM: begin
                if (mem_rd_ack) begin
                    next_state = STATE_WAIT_MEM;
                end
            end
            
            STATE_WAIT_MEM: begin
                if (mem_rd_valid) begin
                    next_state = STATE_STREAM_DATA;
                end
            end
            
            STATE_STREAM_DATA: begin
                if (m_axis_tready && m_axis_tvalid && m_axis_tlast) begin
                    next_state = STATE_WAIT_COMPLETE;
                end
            end
            
            STATE_WAIT_COMPLETE: begin
                next_state = STATE_WRITEBACK;
            end
            
            STATE_WRITEBACK: begin
                if (desc_wb_ack) begin
                    next_state = STATE_WAIT_WB;
                end
            end
            
            STATE_WAIT_WB: begin
                next_state = STATE_NEXT_DESC;
            end
            
            STATE_NEXT_DESC: begin
                if (dma_enable) begin
                    next_state = STATE_FETCH_DESC;
                end else begin
                    next_state = STATE_IDLE;
                end
            end
            
            STATE_ERROR: begin
                next_state = STATE_IDLE;
            end
            
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end
    
    //==========================================================================
    // Descriptor Management Logic
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            desc_index      <= {DESC_PTR_WIDTH{1'b0}};
            desc_req        <= 1'b0;
            desc_addr       <= {DESC_ADDR_WIDTH{1'b0}};
            current_desc    <= 128'h0;
            buffer_addr     <= 64'h0;
            buffer_len      <= 16'h0;
            desc_own        <= 1'b0;
            desc_last       <= 1'b0;
            desc_crc_en     <= 1'b0;
            desc_int_en     <= 1'b0;
        end else begin
            case (state)
                STATE_FETCH_DESC: begin
                    desc_req  <= 1'b1;
                    desc_addr <= desc_base_addr + (desc_index << 4);  // 16 bytes per descriptor
                end
                
                STATE_WAIT_DESC: begin
                    desc_req <= 1'b0;
                    if (desc_valid) begin
                        current_desc <= desc_data;
                        buffer_addr  <= desc_data[63:0];
                        buffer_len   <= desc_data[79:64];
                        desc_own     <= desc_data[96];
                        desc_last    <= desc_data[97];
                        desc_crc_en  <= desc_data[98];
                        desc_int_en  <= desc_data[99];
                    end
                end
                
                STATE_NEXT_DESC: begin
                    // Increment descriptor index (wrap around)
                    if (desc_index == desc_ring_size - 1) begin
                        desc_index <= {DESC_PTR_WIDTH{1'b0}};
                    end else begin
                        desc_index <= desc_index + 1'b1;
                    end
                end
                
                default: begin
                    desc_req <= 1'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // Memory Read Logic
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            mem_rd_req   <= 1'b0;
            mem_rd_addr  <= {MEM_ADDR_WIDTH{1'b0}};
            mem_rd_len   <= {BUF_SIZE_WIDTH{1'b0}};
            mem_rd_ready <= 1'b0;
            data_buffer  <= {MEM_DATA_WIDTH{1'b0}};
        end else begin
            case (state)
                STATE_READ_MEM: begin
                    mem_rd_req  <= 1'b1;
                    mem_rd_addr <= buffer_addr[MEM_ADDR_WIDTH-1:0];
                    mem_rd_len  <= buffer_len[BUF_SIZE_WIDTH-1:0];
                end
                
                STATE_WAIT_MEM: begin
                    mem_rd_req   <= 1'b0;
                    mem_rd_ready <= 1'b1;
                    if (mem_rd_valid) begin
                        data_buffer <= mem_rd_data;
                    end
                end
                
                STATE_STREAM_DATA: begin
                    mem_rd_ready <= m_axis_tready;  // Flow control
                    if (mem_rd_valid && mem_rd_ready) begin
                        data_buffer <= mem_rd_data;
                    end
                end
                
                default: begin
                    mem_rd_req   <= 1'b0;
                    mem_rd_ready <= 1'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // AXI-Stream Output Logic
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axis_tdata  <= {AXIS_DATA_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 1'b0;
            byte_count    <= {BUF_SIZE_WIDTH{1'b0}};
            total_bytes   <= {BUF_SIZE_WIDTH{1'b0}};
            sof_flag      <= 1'b0;
            byte_offset   <= 3'h0;
        end else begin
            case (state)
                STATE_CHECK_OWN: begin
                    byte_count   <= {BUF_SIZE_WIDTH{1'b0}};
                    total_bytes  <= buffer_len[BUF_SIZE_WIDTH-1:0];
                    sof_flag     <= 1'b1;
                    byte_offset  <= 3'h0;
                end
                
                STATE_STREAM_DATA: begin
                    m_axis_tvalid <= 1'b1;
                    m_axis_tdata  <= stream_byte;
                    m_axis_tuser  <= sof_flag;
                    
                    if (m_axis_tready) begin
                        sof_flag <= 1'b0;
                        byte_count <= byte_count + 1'b1;
                        
                        // Check if this is the last byte
                        if (byte_count == total_bytes - 1) begin
                            m_axis_tlast <= 1'b1;
                        end else begin
                            m_axis_tlast <= 1'b0;
                        end
                        
                        // Increment byte offset
                        if (byte_offset == (MEM_DATA_WIDTH/AXIS_DATA_WIDTH - 1)) begin
                            byte_offset <= 3'h0;
                        end else begin
                            byte_offset <= byte_offset + 1'b1;
                        end
                    end
                end
                
                default: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    m_axis_tuser  <= 1'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // Descriptor Writeback Logic
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            desc_wb_req  <= 1'b0;
            desc_wb_addr <= {DESC_ADDR_WIDTH{1'b0}};
            desc_wb_data <= 128'h0;
        end else begin
            case (state)
                STATE_WRITEBACK: begin
                    desc_wb_req  <= 1'b1;
                    desc_wb_addr <= desc_base_addr + (desc_index << 4);
                    // Update descriptor: clear OWN bit, set DONE bit
                    desc_wb_data <= {current_desc[127:113], 1'b1, 1'b0, current_desc[111:97], 1'b0, current_desc[95:0]};
                end
                
                default: begin
                    desc_wb_req <= 1'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // Statistics and Interrupts
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            tx_pkt_count <= 32'h0;
            tx_err_count <= 32'h0;
            int_tx_done  <= 1'b0;
            int_tx_err   <= 1'b0;
        end else begin
            int_tx_done <= 1'b0;
            int_tx_err  <= 1'b0;
            
            if (state == STATE_NEXT_DESC && next_state == STATE_FETCH_DESC) begin
                tx_pkt_count <= tx_pkt_count + 1'b1;
                int_tx_done  <= desc_int_en;
            end
            
            if (state == STATE_ERROR) begin
                tx_err_count <= tx_err_count + 1'b1;
                int_tx_err   <= 1'b1;
            end
        end
    end

endmodule
