//==============================================================================
// Module: eth_dma_regs
// Description: AXI4-Lite slave register interface for Ethernet DMA Controller
//
// Features:
//   - AXI4-Lite slave interface (32-bit data, configurable address width)
//   - Descriptor ring configuration (base address, ring size)
//   - DMA enable/disable control
//   - Interrupt status and mask registers
//   - Statistics counters
//   - Clean synchronous reset behavior
//
// Register Map (byte addresses):
//   0x00: DMA_CONTROL       - DMA enable/reset control        (RW)
//   0x04: DMA_STATUS        - DMA status                      (RO)
//   0x08: TX_DESC_BASE_LO   - TX descriptor base [31:0]      (RW)
//   0x0C: TX_DESC_BASE_HI   - TX descriptor base [63:32]     (RW)
//   0x10: TX_DESC_RING_SIZE - TX ring size (log2)            (RW)
//   0x14: RX_DESC_BASE_LO   - RX descriptor base [31:0]      (RW)
//   0x18: RX_DESC_BASE_HI   - RX descriptor base [63:32]     (RW)
//   0x1C: RX_DESC_RING_SIZE - RX ring size (log2)            (RW)
//   0x20: INT_STATUS        - Interrupt status                (RW1C)
//   0x24: INT_MASK          - Interrupt mask                  (RW)
//   0x28: TX_PKT_COUNT      - TX packet counter               (RO)
//   0x2C: RX_PKT_COUNT      - RX packet counter               (RO)
//   0x30: TX_ERR_COUNT      - TX error counter                (RO)
//   0x34: RX_ERR_COUNT      - RX error counter                (RO)
//   0x38: DMA_VERSION       - DMA IP version                  (RO)
//
// DMA_CONTROL bits:
//   [0] - TX_ENABLE:  Enable TX DMA
//   [1] - RX_ENABLE:  Enable RX DMA
//   [2] - DMA_RESET:  Software reset for DMA (self-clearing)
//
// DMA_STATUS bits:
//   [0] - TX_BUSY: TX DMA busy
//   [1] - RX_BUSY: RX DMA busy
//
// INT_STATUS/INT_MASK bits:
//   [0] - TX_DONE:  TX descriptor complete
//   [1] - RX_DONE:  RX descriptor complete
//   [2] - TX_ERROR: TX DMA error
//   [3] - RX_ERROR: RX DMA error
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_dma_regs #(
    parameter ADDR_WIDTH      = 8,              // AXI address width
    parameter DATA_WIDTH      = 32,             // AXI data width (fixed at 32)
    parameter DESC_ADDR_WIDTH = 32,             // Descriptor address width
    parameter DESC_PTR_WIDTH  = 8,              // Descriptor pointer width
    parameter VERSION         = 32'h0001_0000   // DMA IP Version 1.0.0
) (
    //==========================================================================
    // Clock and Reset
    //==========================================================================
    input  wire                         clk,
    input  wire                         rst_n,

    //==========================================================================
    // AXI4-Lite Slave Interface
    //==========================================================================
    input  wire [ADDR_WIDTH-1:0]        s_axi_awaddr,
    input  wire                         s_axi_awvalid,
    output reg                          s_axi_awready,
    
    input  wire [DATA_WIDTH-1:0]        s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]      s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output reg                          s_axi_wready,
    
    output reg  [1:0]                   s_axi_bresp,
    output reg                          s_axi_bvalid,
    input  wire                         s_axi_bready,
    
    input  wire [ADDR_WIDTH-1:0]        s_axi_araddr,
    input  wire                         s_axi_arvalid,
    output reg                          s_axi_arready,
    
    output reg  [DATA_WIDTH-1:0]        s_axi_rdata,
    output reg  [1:0]                   s_axi_rresp,
    output reg                          s_axi_rvalid,
    input  wire                         s_axi_rready,

    //==========================================================================
    // Control Outputs
    //==========================================================================
    output wire                         dma_tx_enable,
    output wire                         dma_rx_enable,
    output wire                         dma_reset,
    output wire [DESC_ADDR_WIDTH-1:0]   tx_desc_base_addr,
    output wire [DESC_PTR_WIDTH-1:0]    tx_desc_ring_size,
    output wire [DESC_ADDR_WIDTH-1:0]   rx_desc_base_addr,
    output wire [DESC_PTR_WIDTH-1:0]    rx_desc_ring_size,
    output wire [3:0]                   irq_mask,

    //==========================================================================
    // Status Inputs
    //==========================================================================
    input  wire                         tx_desc_busy,
    input  wire                         rx_desc_busy,
    input  wire [31:0]                  tx_pkt_count,
    input  wire [31:0]                  rx_pkt_count,
    input  wire [31:0]                  tx_err_count,
    input  wire [31:0]                  rx_err_count,

    //==========================================================================
    // Interrupt Inputs
    //==========================================================================
    input  wire                         int_tx_done,
    input  wire                         int_rx_done,
    input  wire                         int_tx_err,
    input  wire                         int_rx_err
);

    //==========================================================================
    // Register Address Decode
    //==========================================================================
    localparam  ADDR_DMA_CONTROL       = 8'h00;
    localparam  ADDR_DMA_STATUS        = 8'h04;
    localparam  ADDR_TX_DESC_BASE_LO   = 8'h08;
    localparam  ADDR_TX_DESC_BASE_HI   = 8'h0C;
    localparam  ADDR_TX_DESC_RING_SIZE = 8'h10;
    localparam  ADDR_RX_DESC_BASE_LO   = 8'h14;
    localparam  ADDR_RX_DESC_BASE_HI   = 8'h18;
    localparam  ADDR_RX_DESC_RING_SIZE = 8'h1C;
    localparam  ADDR_INT_STATUS        = 8'h20;
    localparam  ADDR_INT_MASK          = 8'h24;
    localparam  ADDR_TX_PKT_COUNT      = 8'h28;
    localparam  ADDR_RX_PKT_COUNT      = 8'h2C;
    localparam  ADDR_TX_ERR_COUNT      = 8'h30;
    localparam  ADDR_RX_ERR_COUNT      = 8'h34;
    localparam  ADDR_DMA_VERSION       = 8'h38;

    //==========================================================================
    // Registers
    //==========================================================================
    reg [2:0]               reg_dma_control;        // {dma_reset, rx_enable, tx_enable}
    reg [DESC_ADDR_WIDTH-1:0] reg_tx_desc_base_lo;
    reg [DESC_ADDR_WIDTH-1:0] reg_tx_desc_base_hi;  // Only used if DESC_ADDR_WIDTH > 32
    reg [DESC_PTR_WIDTH-1:0]  reg_tx_desc_ring_size;
    reg [DESC_ADDR_WIDTH-1:0] reg_rx_desc_base_lo;
    reg [DESC_ADDR_WIDTH-1:0] reg_rx_desc_base_hi;  // Only used if DESC_ADDR_WIDTH > 32
    reg [DESC_PTR_WIDTH-1:0]  reg_rx_desc_ring_size;
    reg [3:0]               reg_int_status;
    reg [3:0]               reg_int_mask;

    //==========================================================================
    // Control Outputs
    //==========================================================================
    assign dma_tx_enable = reg_dma_control[0];
    assign dma_rx_enable = reg_dma_control[1];
    assign dma_reset     = reg_dma_control[2];
    
    generate
        if (DESC_ADDR_WIDTH <= 32) begin : gen_addr_32
            assign tx_desc_base_addr = reg_tx_desc_base_lo;
            assign rx_desc_base_addr = reg_rx_desc_base_lo;
        end else begin : gen_addr_64
            assign tx_desc_base_addr = {reg_tx_desc_base_hi[DESC_ADDR_WIDTH-33:0], reg_tx_desc_base_lo};
            assign rx_desc_base_addr = {reg_rx_desc_base_hi[DESC_ADDR_WIDTH-33:0], reg_rx_desc_base_lo};
        end
    endgenerate
    
    assign tx_desc_ring_size = reg_tx_desc_ring_size;
    assign rx_desc_ring_size = reg_rx_desc_ring_size;
    assign irq_mask          = reg_int_mask;

    //==========================================================================
    // AXI4-Lite Write Logic
    //==========================================================================
    reg [ADDR_WIDTH-1:0] wr_addr_latched;
    reg                  wr_addr_valid;

    // Write address channel
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_awready    <= 1'b0;
            wr_addr_latched  <= {ADDR_WIDTH{1'b0}};
            wr_addr_valid    <= 1'b0;
        end else begin
            if (s_axi_awvalid && !wr_addr_valid) begin
                s_axi_awready   <= 1'b1;
                wr_addr_latched <= s_axi_awaddr;
                wr_addr_valid   <= 1'b1;
            end else begin
                s_axi_awready <= 1'b0;
                if (s_axi_wvalid && s_axi_wready) begin
                    wr_addr_valid <= 1'b0;
                end
            end
        end
    end

    // Write data channel
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_wready <= 1'b0;
        end else begin
            s_axi_wready <= wr_addr_valid && s_axi_wvalid;
        end
    end

    // Write response channel
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
        end else begin
            if (s_axi_wvalid && s_axi_wready) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;  // OKAY
            end else if (s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // Register writes
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_dma_control        <= 3'b000;
            reg_tx_desc_base_lo    <= {DESC_ADDR_WIDTH{1'b0}};
            reg_tx_desc_base_hi    <= {DESC_ADDR_WIDTH{1'b0}};
            reg_tx_desc_ring_size  <= {DESC_PTR_WIDTH{1'b0}};
            reg_rx_desc_base_lo    <= {DESC_ADDR_WIDTH{1'b0}};
            reg_rx_desc_base_hi    <= {DESC_ADDR_WIDTH{1'b0}};
            reg_rx_desc_ring_size  <= {DESC_PTR_WIDTH{1'b0}};
            reg_int_status         <= 4'b0000;
            reg_int_mask           <= 4'b0000;
        end else begin
            // Auto-clear DMA reset bit
            if (reg_dma_control[2]) begin
                reg_dma_control[2] <= 1'b0;
            end
            
            // Interrupt status - OR with new interrupts
            reg_int_status[0] <= reg_int_status[0] | int_tx_done;
            reg_int_status[1] <= reg_int_status[1] | int_rx_done;
            reg_int_status[2] <= reg_int_status[2] | int_tx_err;
            reg_int_status[3] <= reg_int_status[3] | int_rx_err;
            
            // Register write operations
            if (s_axi_wvalid && s_axi_wready) begin
                case (wr_addr_latched[7:0])
                    ADDR_DMA_CONTROL: begin
                        if (s_axi_wstrb[0]) reg_dma_control <= s_axi_wdata[2:0];
                    end
                    
                    ADDR_TX_DESC_BASE_LO: begin
                        if (s_axi_wstrb[0]) reg_tx_desc_base_lo[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_tx_desc_base_lo[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_tx_desc_base_lo[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_tx_desc_base_lo[31:24] <= s_axi_wdata[31:24];
                    end
                    
                    ADDR_TX_DESC_BASE_HI: begin
                        if (DESC_ADDR_WIDTH > 32) begin
                            if (s_axi_wstrb[0]) reg_tx_desc_base_hi[7:0]   <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) reg_tx_desc_base_hi[15:8]  <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) reg_tx_desc_base_hi[23:16] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) reg_tx_desc_base_hi[31:24] <= s_axi_wdata[31:24];
                        end
                    end
                    
                    ADDR_TX_DESC_RING_SIZE: begin
                        if (s_axi_wstrb[0]) reg_tx_desc_ring_size <= s_axi_wdata[DESC_PTR_WIDTH-1:0];
                    end
                    
                    ADDR_RX_DESC_BASE_LO: begin
                        if (s_axi_wstrb[0]) reg_rx_desc_base_lo[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_rx_desc_base_lo[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_rx_desc_base_lo[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_rx_desc_base_lo[31:24] <= s_axi_wdata[31:24];
                    end
                    
                    ADDR_RX_DESC_BASE_HI: begin
                        if (DESC_ADDR_WIDTH > 32) begin
                            if (s_axi_wstrb[0]) reg_rx_desc_base_hi[7:0]   <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1]) reg_rx_desc_base_hi[15:8]  <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2]) reg_rx_desc_base_hi[23:16] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3]) reg_rx_desc_base_hi[31:24] <= s_axi_wdata[31:24];
                        end
                    end
                    
                    ADDR_RX_DESC_RING_SIZE: begin
                        if (s_axi_wstrb[0]) reg_rx_desc_ring_size <= s_axi_wdata[DESC_PTR_WIDTH-1:0];
                    end
                    
                    ADDR_INT_STATUS: begin
                        // Write-1-to-clear
                        if (s_axi_wstrb[0]) begin
                            reg_int_status[0] <= reg_int_status[0] & ~s_axi_wdata[0];
                            reg_int_status[1] <= reg_int_status[1] & ~s_axi_wdata[1];
                            reg_int_status[2] <= reg_int_status[2] & ~s_axi_wdata[2];
                            reg_int_status[3] <= reg_int_status[3] & ~s_axi_wdata[3];
                        end
                    end
                    
                    ADDR_INT_MASK: begin
                        if (s_axi_wstrb[0]) reg_int_mask <= s_axi_wdata[3:0];
                    end
                    
                    default: begin
                        // Read-only registers - ignore writes
                    end
                endcase
            end
        end
    end

    //==========================================================================
    // AXI4-Lite Read Logic
    //==========================================================================
    reg [ADDR_WIDTH-1:0] rd_addr_latched;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_arready    <= 1'b0;
            rd_addr_latched  <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready   <= 1'b1;
                rd_addr_latched <= s_axi_araddr;
            end else begin
                s_axi_arready <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= {DATA_WIDTH{1'b0}};
            s_axi_rresp  <= 2'b00;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;  // OKAY
                
                case (rd_addr_latched[7:0])
                    ADDR_DMA_CONTROL: begin
                        s_axi_rdata <= {{(DATA_WIDTH-3){1'b0}}, reg_dma_control};
                    end
                    
                    ADDR_DMA_STATUS: begin
                        s_axi_rdata <= {{(DATA_WIDTH-2){1'b0}}, rx_desc_busy, tx_desc_busy};
                    end
                    
                    ADDR_TX_DESC_BASE_LO: begin
                        s_axi_rdata <= reg_tx_desc_base_lo[31:0];
                    end
                    
                    ADDR_TX_DESC_BASE_HI: begin
                        if (DESC_ADDR_WIDTH > 32)
                            s_axi_rdata <= {{(32-(DESC_ADDR_WIDTH-32)){1'b0}}, reg_tx_desc_base_hi[DESC_ADDR_WIDTH-33:0]};
                        else
                            s_axi_rdata <= {DATA_WIDTH{1'b0}};
                    end
                    
                    ADDR_TX_DESC_RING_SIZE: begin
                        s_axi_rdata <= {{(DATA_WIDTH-DESC_PTR_WIDTH){1'b0}}, reg_tx_desc_ring_size};
                    end
                    
                    ADDR_RX_DESC_BASE_LO: begin
                        s_axi_rdata <= reg_rx_desc_base_lo[31:0];
                    end
                    
                    ADDR_RX_DESC_BASE_HI: begin
                        if (DESC_ADDR_WIDTH > 32)
                            s_axi_rdata <= {{(32-(DESC_ADDR_WIDTH-32)){1'b0}}, reg_rx_desc_base_hi[DESC_ADDR_WIDTH-33:0]};
                        else
                            s_axi_rdata <= {DATA_WIDTH{1'b0}};
                    end
                    
                    ADDR_RX_DESC_RING_SIZE: begin
                        s_axi_rdata <= {{(DATA_WIDTH-DESC_PTR_WIDTH){1'b0}}, reg_rx_desc_ring_size};
                    end
                    
                    ADDR_INT_STATUS: begin
                        s_axi_rdata <= {{(DATA_WIDTH-4){1'b0}}, reg_int_status};
                    end
                    
                    ADDR_INT_MASK: begin
                        s_axi_rdata <= {{(DATA_WIDTH-4){1'b0}}, reg_int_mask};
                    end
                    
                    ADDR_TX_PKT_COUNT: begin
                        s_axi_rdata <= tx_pkt_count;
                    end
                    
                    ADDR_RX_PKT_COUNT: begin
                        s_axi_rdata <= rx_pkt_count;
                    end
                    
                    ADDR_TX_ERR_COUNT: begin
                        s_axi_rdata <= tx_err_count;
                    end
                    
                    ADDR_RX_ERR_COUNT: begin
                        s_axi_rdata <= rx_err_count;
                    end
                    
                    ADDR_DMA_VERSION: begin
                        s_axi_rdata <= VERSION;
                    end
                    
                    default: begin
                        s_axi_rdata <= {DATA_WIDTH{1'b0}};
                        s_axi_rresp <= 2'b11;  // DECERR
                    end
                endcase
            end else if (s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
