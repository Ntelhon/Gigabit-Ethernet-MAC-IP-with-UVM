//==============================================================================
// Module: eth_rx_dma
// Description: RX DMA engine for Ethernet Controller
//
// Features:
//   - Descriptor-based packet reception
//   - Reads RX descriptors from memory
//   - Receives packet data from MAC via AXI-Stream
//   - Writes packet payload to memory via AXI4
//   - Updates descriptor with actual length and status
//   - Ring buffer management
//   - Interrupt generation on reception/error
//
// Operation:
//   1. Fetch next RX descriptor from memory
//   2. Check ownership bit (CPU owned vs DMA owned)
//   3. Receive packet from MAC via AXI-Stream (monitor tlast)
//   4. Write packet data to memory address from descriptor
//   5. Update descriptor with actual length and frame status
//   6. Write back descriptor
//   7. Generate interrupt if enabled
//   8. Move to next descriptor
//
// Descriptor Format (128 bits):
//   [63:0]   - buffer_addr:   Physical address of RX buffer
//   [79:64]  - buffer_len:    Size of RX buffer (max packet size)
//   [95:80]  - reserved
//   [96]     - OWN:           Ownership (0=CPU, 1=DMA)
//   [97]     - WRAP:          Last descriptor in ring
//   [98]     - INT_EN:        Enable interrupt on reception
//   [111:99] - reserved
//   [112]    - DONE:          Reception complete (written by DMA)
//   [113]    - ERR:           Reception error (written by DMA)
//   [114]    - CRC_ERR:       CRC error (written by DMA)
//   [127:115]- actual_len:    Actual received length (written by DMA)
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_rx_dma #(
    parameter AXIS_DATA_WIDTH   = 8,
    parameter AXIS_USER_WIDTH   = 2,
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
    
    // Memory write interface (to descriptor manager)
    output reg                              mem_wr_req,
    input  wire                             mem_wr_ack,
    output reg  [MEM_ADDR_WIDTH-1:0]        mem_wr_addr,
    output reg  [BUF_SIZE_WIDTH-1:0]        mem_wr_len,
    output reg  [MEM_DATA_WIDTH-1:0]        mem_wr_data,
    output reg                              mem_wr_valid,
    output reg                              mem_wr_last,
    input  wire                             mem_wr_ready,
    output reg  [MEM_DATA_WIDTH/8-1:0]      mem_wr_strb,
    
    // AXI-Stream from MAC
    input  wire [AXIS_DATA_WIDTH-1:0]       s_axis_tdata,
    input  wire                             s_axis_tvalid,
    input  wire                             s_axis_tlast,
    input  wire [AXIS_USER_WIDTH-1:0]       s_axis_tuser,   // {frame_bad, frame_good}
    output reg                              s_axis_tready,
    
    // Status and interrupts
    output wire                             rx_busy,
    output reg  [31:0]                      rx_pkt_count,
    output reg  [31:0]                      rx_err_count,
    output reg                              int_rx_done,
    output reg                              int_rx_err
);

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam STATE_IDLE           = 4'h0;
    localparam STATE_FETCH_DESC     = 4'h1;
    localparam STATE_WAIT_DESC      = 4'h2;
    localparam STATE_CHECK_OWN      = 4'h3;
    localparam STATE_RECEIVE        = 4'h4;
    localparam STATE_ACCUMULATE     = 4'h5;
    localparam STATE_WRITE_MEM      = 4'h6;
    localparam STATE_WAIT_WRITE     = 4'h7;
    localparam STATE_WRITEBACK      = 4'h8;
    localparam STATE_WAIT_WB        = 4'h9;
    localparam STATE_NEXT_DESC      = 4'hA;
    localparam STATE_ERROR          = 4'hF;
    
    reg [3:0] state, next_state;
    
    //==========================================================================
    // Descriptor Ring Management
    //==========================================================================
    reg [DESC_PTR_WIDTH-1:0] desc_index;
    reg [127:0]              current_desc;
    reg [63:0]               buffer_addr;
    reg [15:0]               buffer_len;
    reg                      desc_own;
    reg                      desc_wrap;
    reg                      desc_int_en;
    
    //==========================================================================
    // Packet Reception
    //==========================================================================
    reg [BUF_SIZE_WIDTH-1:0] rx_byte_count;
    reg [BUF_SIZE_WIDTH-1:0] rx_total_bytes;
    reg                      frame_good;
    reg                      frame_bad;
    reg                      crc_error;
    
    //==========================================================================
    // Data Accumulation Buffer (AXIS width -> MEM width)
    //==========================================================================
    reg [MEM_DATA_WIDTH-1:0]  data_buffer;
    reg [2:0]                 buffer_byte_count;
    reg                       buffer_full;
    localparam [3:0]          bytes_per_word = MEM_DATA_WIDTH / AXIS_DATA_WIDTH;
    
    //==========================================================================
    // Status
    //==========================================================================
    assign rx_busy = (state != STATE_IDLE);
    
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
                    next_state = STATE_RECEIVE;
                end else begin
                    next_state = STATE_IDLE;
                end
            end
            
            STATE_RECEIVE: begin
                if (s_axis_tvalid && s_axis_tready) begin
                    next_state = STATE_ACCUMULATE;
                end
            end
            
            STATE_ACCUMULATE: begin
                if (buffer_full) begin
                    next_state = STATE_WRITE_MEM;
                end else if (s_axis_tvalid && s_axis_tlast) begin
                    next_state = STATE_WRITE_MEM;  // Flush partial buffer
                end else begin
                    next_state = STATE_RECEIVE;
                end
            end
            
            STATE_WRITE_MEM: begin
                if (mem_wr_ack) begin
                    next_state = STATE_WAIT_WRITE;
                end
            end
            
            STATE_WAIT_WRITE: begin
                if (mem_wr_valid && mem_wr_ready && mem_wr_last) begin
                    if (s_axis_tlast) begin
                        next_state = STATE_WRITEBACK;
                    end else begin
                        next_state = STATE_RECEIVE;
                    end
                end
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
            desc_index   <= {DESC_PTR_WIDTH{1'b0}};
            desc_req     <= 1'b0;
            desc_addr    <= {DESC_ADDR_WIDTH{1'b0}};
            current_desc <= 128'h0;
            buffer_addr  <= 64'h0;
            buffer_len   <= 16'h0;
            desc_own     <= 1'b0;
            desc_wrap    <= 1'b0;
            desc_int_en  <= 1'b0;
        end else begin
            case (state)
                STATE_FETCH_DESC: begin
                    desc_req  <= 1'b1;
                    desc_addr <= desc_base_addr + (desc_index << 4);
                end
                
                STATE_WAIT_DESC: begin
                    desc_req <= 1'b0;
                    if (desc_valid) begin
                        current_desc <= desc_data;
                        buffer_addr  <= desc_data[63:0];
                        buffer_len   <= desc_data[79:64];
                        desc_own     <= desc_data[96];
                        desc_wrap    <= desc_data[97];
                        desc_int_en  <= desc_data[98];
                    end
                end
                
                STATE_NEXT_DESC: begin
                    if (desc_wrap || (desc_index == desc_ring_size - 1)) begin
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
    // Packet Reception and Data Accumulation
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axis_tready      <= 1'b0;
            data_buffer        <= {MEM_DATA_WIDTH{1'b0}};
            buffer_byte_count  <= 3'h0;
            buffer_full        <= 1'b0;
            rx_byte_count      <= {BUF_SIZE_WIDTH{1'b0}};
            rx_total_bytes     <= {BUF_SIZE_WIDTH{1'b0}};
            frame_good         <= 1'b0;
            frame_bad          <= 1'b0;
            crc_error          <= 1'b0;
        end else begin
            case (state)
                STATE_CHECK_OWN: begin
                    s_axis_tready     <= 1'b1;
                    rx_byte_count     <= {BUF_SIZE_WIDTH{1'b0}};
                    buffer_byte_count <= 3'h0;
                    buffer_full       <= 1'b0;
                    frame_good        <= 1'b0;
                    frame_bad         <= 1'b0;
                    crc_error         <= 1'b0;
                end
                
                STATE_RECEIVE: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        // Accumulate byte into buffer
                        data_buffer[buffer_byte_count*AXIS_DATA_WIDTH +: AXIS_DATA_WIDTH] <= s_axis_tdata;
                        buffer_byte_count <= buffer_byte_count + 1'b1;
                        rx_byte_count     <= rx_byte_count + 1'b1;
                        
                        // Check if buffer is full
                        if (buffer_byte_count == bytes_per_word - 1) begin
                            buffer_full <= 1'b1;
                        end
                        
                        // Capture frame status on last byte
                        if (s_axis_tlast) begin
                            rx_total_bytes <= rx_byte_count + 1'b1;
                            frame_good     <= s_axis_tuser[0];
                            frame_bad      <= s_axis_tuser[1];
                            crc_error      <= s_axis_tuser[1];  // Assume tuser[1] indicates error
                            s_axis_tready  <= 1'b0;
                        end
                    end
                end
                
                STATE_WRITE_MEM: begin
                    buffer_full       <= 1'b0;
                    buffer_byte_count <= 3'h0;
                end
                
                STATE_WAIT_WRITE: begin
                    if (mem_wr_valid && mem_wr_ready) begin
                        data_buffer <= {MEM_DATA_WIDTH{1'b0}};
                    end
                    if (!s_axis_tlast && mem_wr_last) begin
                        s_axis_tready <= 1'b1;
                    end
                end
                
                default: begin
                    s_axis_tready <= 1'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // Memory Write Logic
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            mem_wr_req   <= 1'b0;
            mem_wr_addr  <= {MEM_ADDR_WIDTH{1'b0}};
            mem_wr_len   <= {BUF_SIZE_WIDTH{1'b0}};
            mem_wr_data  <= {MEM_DATA_WIDTH{1'b0}};
            mem_wr_valid <= 1'b0;
            mem_wr_last  <= 1'b0;
            mem_wr_strb  <= {MEM_DATA_WIDTH/8{1'b0}};
        end else begin
            case (state)
                STATE_WRITE_MEM: begin
                    mem_wr_req   <= 1'b1;
                    mem_wr_addr  <= buffer_addr[MEM_ADDR_WIDTH-1:0] + rx_byte_count - buffer_byte_count;
                    mem_wr_len   <= {{(BUF_SIZE_WIDTH-3){1'b0}}, buffer_byte_count};
                    mem_wr_data  <= data_buffer;
                    mem_wr_valid <= 1'b1;
                    
                    // Generate write strobes based on valid bytes
                    if (buffer_byte_count == bytes_per_word) begin
                        mem_wr_strb <= {MEM_DATA_WIDTH/8{1'b1}};  // All bytes valid
                    end else begin
                        mem_wr_strb <= ({MEM_DATA_WIDTH/8{1'b1}} >> (MEM_DATA_WIDTH/8 - buffer_byte_count));
                    end
                    
                    // Last beat if this was triggered by tlast
                    mem_wr_last <= s_axis_tlast;
                end
                
                STATE_WAIT_WRITE: begin
                    mem_wr_req <= 1'b0;
                    if (mem_wr_ready) begin
                        mem_wr_valid <= 1'b0;
                    end
                end
                
                default: begin
                    mem_wr_req   <= 1'b0;
                    mem_wr_valid <= 1'b0;
                    mem_wr_last  <= 1'b0;
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
                    // Update descriptor: clear OWN, set DONE, set actual_len
                    desc_wb_data <= {
                        rx_total_bytes[12:0],   // [127:115] actual_len
                        crc_error,              // [114] CRC_ERR
                        frame_bad,              // [113] ERR
                        1'b1,                   // [112] DONE
                        current_desc[111:97],   // [111:97] reserved + control
                        1'b0,                   // [96] OWN = 0 (return to CPU)
                        current_desc[95:0]      // [95:0] buffer info
                    };
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
            rx_pkt_count <= 32'h0;
            rx_err_count <= 32'h0;
            int_rx_done  <= 1'b0;
            int_rx_err   <= 1'b0;
        end else begin
            int_rx_done <= 1'b0;
            int_rx_err  <= 1'b0;
            
            if (state == STATE_NEXT_DESC && next_state == STATE_FETCH_DESC) begin
                if (!frame_bad) begin
                    rx_pkt_count <= rx_pkt_count + 1'b1;
                    int_rx_done  <= desc_int_en;
                end else begin
                    rx_err_count <= rx_err_count + 1'b1;
                    int_rx_err   <= desc_int_en;
                end
            end
            
            if (state == STATE_ERROR) begin
                rx_err_count <= rx_err_count + 1'b1;
                int_rx_err   <= 1'b1;
            end
        end
    end

endmodule
