//==============================================================================
// Module: eth_dma_top
// Description: Top-level DMA controller for Ethernet MAC
//
// Features:
//   - Descriptor-based DMA for TX and RX paths
//   - AXI4 memory interface with configurable burst support
//   - AXI4-Lite control/status register interface
//   - Completely independent from MAC core
//   - Optional/removable via DMA_ENABLE parameter
//   - Separate interrupt outputs for TX/RX/Errors
//   - Ring-based descriptor management
//
// Architecture:
//   ┌─────────────────────────────────────────────────────────────────┐
//   │                       eth_dma_top                               │
//   │                                                                 │
//   │  ┌──────────────┐    ┌────────────────┐    ┌─────────────────┐ │
//   │  │  DMA Control │    │  eth_rx_dma    │    │  eth_tx_dma     │ │
//   │  │  Registers   │───▶│                │    │                 │ │
//   │  │  (AXI-Lite)  │    │  Desc Fetch    │    │  Desc Fetch     │ │
//   │  └──────────────┘    │  Data Write    │    │  Data Read      │ │
//   │         │            │  Desc Update   │    │  Desc Update    │ │
//   │         │            └────────┬───────┘    └────────┬────────┘ │
//   │         │                     │                     │          │
//   │         │            ┌────────▼─────────────────────▼────────┐ │
//   │         └───────────▶│   eth_dma_desc (Descriptor Mgmt)      │ │
//   │                      │   - Ring management                   │ │
//   │                      │   - Ownership tracking                │ │
//   │                      │   - AXI4 master arbitration           │ │
//   │                      └──────────┬────────────────────────────┘ │
//   │                                 │                              │
//   │                      ┌──────────▼────────────┐                 │
//   │                      │   AXI4 Master I/F     │                 │
//   │                      │   (to Memory)         │                 │
//   │                      └───────────────────────┘                 │
//   │                                                                 │
//   │  AXI-Stream (MAC side)         AXI4 Memory          AXI-Lite    │
//   └─────────────────────────────────────────────────────────────────┘
//
// Use Cases:
//   1. DMA_ENABLE=1: Full DMA functionality for embedded systems
//   2. DMA_ENABLE=0: Direct AXI-Stream connection (bypass DMA)
//
// Clock Domains:
//   - sys_clk: All DMA logic, AXI interfaces, AXI-Stream interfaces
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module eth_dma_top #(
    //==========================================================================
    // DMA Enable/Bypass Parameters
    //==========================================================================
    parameter DMA_ENABLE         = 1,           // 1=DMA enabled, 0=bypass (passthrough)
    
    //==========================================================================
    // AXI4-Lite Parameters (Control Interface)
    //==========================================================================
    parameter C_ADDR_WIDTH       = 8,           // Control register address width
    parameter C_DATA_WIDTH       = 32,          // Control register data width
    
    //==========================================================================
    // AXI4 Memory Interface Parameters
    //==========================================================================
    parameter M_AXI_ADDR_WIDTH   = 32,          // Memory address width (32 or 64)
    parameter M_AXI_DATA_WIDTH   = 64,          // Memory data width (32/64/128)
    parameter M_AXI_ID_WIDTH     = 4,           // AXI ID width
    parameter M_AXI_MAX_BURST    = 16,          // Maximum burst length (AXI: 1-256)
    
    //==========================================================================
    // Descriptor Parameters
    //==========================================================================
    parameter DESC_ADDR_WIDTH    = 32,          // Descriptor address width
    parameter DESC_RING_DEPTH    = 8,           // Log2(ring size), e.g., 8 = 256 descriptors
    parameter DESC_PTR_WIDTH     = DESC_RING_DEPTH, // Descriptor pointer width
    
    //==========================================================================
    // Buffer Parameters
    //==========================================================================
    parameter BUF_SIZE_WIDTH     = 14,          // Buffer size width (16KB max)
    parameter MIN_FRAME_SIZE     = 64,          // Minimum Ethernet frame size
    parameter MAX_FRAME_SIZE     = 1518,        // Maximum Ethernet frame size
    
    //==========================================================================
    // AXI-Stream Parameters (MAC Interface)
    //==========================================================================
    parameter AXIS_DATA_WIDTH    = 8,           // AXI-Stream data width (matches MAC)
    parameter AXIS_USER_WIDTH    = 2            // AXI-Stream user width (frame status)
) (
    //==========================================================================
    // Clock and Reset
    //==========================================================================
    input  wire                             clk,            // System clock
    input  wire                             rst_n,          // Active-low reset

    //==========================================================================
    // AXI4-Lite Slave Interface (DMA Control/Status Registers)
    //==========================================================================
    // Write Address Channel
    input  wire [C_ADDR_WIDTH-1:0]          s_axi_ctrl_awaddr,
    input  wire                             s_axi_ctrl_awvalid,
    output wire                             s_axi_ctrl_awready,
    
    // Write Data Channel
    input  wire [C_DATA_WIDTH-1:0]          s_axi_ctrl_wdata,
    input  wire [C_DATA_WIDTH/8-1:0]        s_axi_ctrl_wstrb,
    input  wire                             s_axi_ctrl_wvalid,
    output wire                             s_axi_ctrl_wready,
    
    // Write Response Channel
    output wire [1:0]                       s_axi_ctrl_bresp,
    output wire                             s_axi_ctrl_bvalid,
    input  wire                             s_axi_ctrl_bready,
    
    // Read Address Channel
    input  wire [C_ADDR_WIDTH-1:0]          s_axi_ctrl_araddr,
    input  wire                             s_axi_ctrl_arvalid,
    output wire                             s_axi_ctrl_arready,
    
    // Read Data Channel
    output wire [C_DATA_WIDTH-1:0]          s_axi_ctrl_rdata,
    output wire [1:0]                       s_axi_ctrl_rresp,
    output wire                             s_axi_ctrl_rvalid,
    input  wire                             s_axi_ctrl_rready,

    //==========================================================================
    // AXI4 Master Interface (Memory Access)
    //==========================================================================
    // Write Address Channel
    output wire [M_AXI_ID_WIDTH-1:0]        m_axi_mem_awid,
    output wire [M_AXI_ADDR_WIDTH-1:0]      m_axi_mem_awaddr,
    output wire [7:0]                       m_axi_mem_awlen,
    output wire [2:0]                       m_axi_mem_awsize,
    output wire [1:0]                       m_axi_mem_awburst,
    output wire                             m_axi_mem_awlock,
    output wire [3:0]                       m_axi_mem_awcache,
    output wire [2:0]                       m_axi_mem_awprot,
    output wire                             m_axi_mem_awvalid,
    input  wire                             m_axi_mem_awready,
    
    // Write Data Channel
    output wire [M_AXI_DATA_WIDTH-1:0]      m_axi_mem_wdata,
    output wire [M_AXI_DATA_WIDTH/8-1:0]    m_axi_mem_wstrb,
    output wire                             m_axi_mem_wlast,
    output wire                             m_axi_mem_wvalid,
    input  wire                             m_axi_mem_wready,
    
    // Write Response Channel
    input  wire [M_AXI_ID_WIDTH-1:0]        m_axi_mem_bid,
    input  wire [1:0]                       m_axi_mem_bresp,
    input  wire                             m_axi_mem_bvalid,
    output wire                             m_axi_mem_bready,
    
    // Read Address Channel
    output wire [M_AXI_ID_WIDTH-1:0]        m_axi_mem_arid,
    output wire [M_AXI_ADDR_WIDTH-1:0]      m_axi_mem_araddr,
    output wire [7:0]                       m_axi_mem_arlen,
    output wire [2:0]                       m_axi_mem_arsize,
    output wire [1:0]                       m_axi_mem_arburst,
    output wire                             m_axi_mem_arlock,
    output wire [3:0]                       m_axi_mem_arcache,
    output wire [2:0]                       m_axi_mem_arprot,
    output wire                             m_axi_mem_arvalid,
    input  wire                             m_axi_mem_arready,
    
    // Read Data Channel
    input  wire [M_AXI_ID_WIDTH-1:0]        m_axi_mem_rid,
    input  wire [M_AXI_DATA_WIDTH-1:0]      m_axi_mem_rdata,
    input  wire [1:0]                       m_axi_mem_rresp,
    input  wire                             m_axi_mem_rlast,
    input  wire                             m_axi_mem_rvalid,
    output wire                             m_axi_mem_rready,

    //==========================================================================
    // MAC Side - TX AXI-Stream Interface (to MAC TX input)
    //==========================================================================
    output wire [AXIS_DATA_WIDTH-1:0]       m_axis_mac_tx_tdata,
    output wire                             m_axis_mac_tx_tvalid,
    output wire                             m_axis_mac_tx_tlast,
    output wire                             m_axis_mac_tx_tuser,   // SOF
    input  wire                             m_axis_mac_tx_tready,

    //==========================================================================
    // MAC Side - RX AXI-Stream Interface (from MAC RX output)
    //==========================================================================
    input  wire [AXIS_DATA_WIDTH-1:0]       s_axis_mac_rx_tdata,
    input  wire                             s_axis_mac_rx_tvalid,
    input  wire                             s_axis_mac_rx_tlast,
    input  wire [AXIS_USER_WIDTH-1:0]       s_axis_mac_rx_tuser,   // {frame_bad, frame_good}
    output wire                             s_axis_mac_rx_tready,

    //==========================================================================
    // User Side - TX AXI-Stream Interface (from CPU/SW)
    // Only used when DMA_ENABLE=0 (passthrough mode)
    //==========================================================================
    input  wire [AXIS_DATA_WIDTH-1:0]       s_axis_user_tx_tdata,
    input  wire                             s_axis_user_tx_tvalid,
    input  wire                             s_axis_user_tx_tlast,
    input  wire                             s_axis_user_tx_tuser,
    output wire                             s_axis_user_tx_tready,

    //==========================================================================
    // User Side - RX AXI-Stream Interface (to CPU/SW)
    // Only used when DMA_ENABLE=0 (passthrough mode)
    //==========================================================================
    output wire [AXIS_DATA_WIDTH-1:0]       m_axis_user_rx_tdata,
    output wire                             m_axis_user_rx_tvalid,
    output wire                             m_axis_user_rx_tlast,
    output wire [AXIS_USER_WIDTH-1:0]       m_axis_user_rx_tuser,
    input  wire                             m_axis_user_rx_tready,

    //==========================================================================
    // Interrupts
    //==========================================================================
    output wire                             irq_tx_done,        // TX descriptor complete
    output wire                             irq_rx_done,        // RX descriptor complete
    output wire                             irq_tx_error,       // TX error (AXI error, etc.)
    output wire                             irq_rx_error,       // RX error (AXI error, overflow, etc.)
    output wire                             irq_combined        // OR of all interrupts
);

    //==========================================================================
    // Generate Block: DMA Enable/Disable
    //==========================================================================
    generate
        if (DMA_ENABLE == 1) begin : gen_dma_enabled
            
            //==================================================================
            // Internal Signals - Control Registers
            //==================================================================
            wire                                dma_tx_enable;
            wire                                dma_rx_enable;
            wire                                dma_reset;
            wire [DESC_ADDR_WIDTH-1:0]          tx_desc_base_addr;
            wire [DESC_PTR_WIDTH-1:0]           tx_desc_ring_size;
            wire [DESC_ADDR_WIDTH-1:0]          rx_desc_base_addr;
            wire [DESC_PTR_WIDTH-1:0]           rx_desc_ring_size;
            wire [3:0]                          irq_mask;
            
            // Status signals
            wire                                tx_desc_busy;
            wire                                rx_desc_busy;
            wire [31:0]                         tx_pkt_count;
            wire [31:0]                         rx_pkt_count;
            wire [31:0]                         tx_err_count;
            wire [31:0]                         rx_err_count;
            
            //==================================================================
            // Internal Signals - TX DMA
            //==================================================================
            // TX descriptor request/response
            wire                                tx_desc_req;
            wire                                tx_desc_ack;
            wire [DESC_ADDR_WIDTH-1:0]          tx_desc_addr;
            wire [127:0]                        tx_desc_data;
            wire                                tx_desc_valid;
            
            // TX descriptor writeback
            wire                                tx_desc_wb_req;
            wire                                tx_desc_wb_ack;
            wire [DESC_ADDR_WIDTH-1:0]          tx_desc_wb_addr;
            wire [127:0]                        tx_desc_wb_data;
            
            // TX data read request/response
            wire                                tx_data_req;
            wire                                tx_data_ack;
            wire [M_AXI_ADDR_WIDTH-1:0]         tx_data_addr;
            wire [BUF_SIZE_WIDTH-1:0]           tx_data_len;
            wire [M_AXI_DATA_WIDTH-1:0]         tx_data_rdata;
            wire                                tx_data_rvalid;
            wire                                tx_data_rlast;
            wire                                tx_data_rready;
            
            //==================================================================
            // Internal Signals - RX DMA
            //==================================================================
            // RX descriptor request/response
            wire                                rx_desc_req;
            wire                                rx_desc_ack;
            wire [DESC_ADDR_WIDTH-1:0]          rx_desc_addr;
            wire [127:0]                        rx_desc_data;
            wire                                rx_desc_valid;
            
            // RX descriptor writeback
            wire                                rx_desc_wb_req;
            wire                                rx_desc_wb_ack;
            wire [DESC_ADDR_WIDTH-1:0]          rx_desc_wb_addr;
            wire [127:0]                        rx_desc_wb_data;
            
            // RX data write request/response
            wire                                rx_data_req;
            wire                                rx_data_ack;
            wire [M_AXI_ADDR_WIDTH-1:0]         rx_data_addr;
            wire [BUF_SIZE_WIDTH-1:0]           rx_data_len;
            wire [M_AXI_DATA_WIDTH-1:0]         rx_data_wdata;
            wire                                rx_data_wvalid;
            wire                                rx_data_wlast;
            wire                                rx_data_wready;
            wire [M_AXI_DATA_WIDTH/8-1:0]       rx_data_wstrb;
            
            //==================================================================
            // Internal Signals - Interrupts
            //==================================================================
            wire                                int_tx_done_raw;
            wire                                int_rx_done_raw;
            wire                                int_tx_err_raw;
            wire                                int_rx_err_raw;

            //==================================================================
            // Module Instantiation: DMA Control Registers
            //==================================================================
            eth_dma_regs #(
                .ADDR_WIDTH         (C_ADDR_WIDTH),
                .DATA_WIDTH         (C_DATA_WIDTH),
                .DESC_ADDR_WIDTH    (DESC_ADDR_WIDTH),
                .DESC_PTR_WIDTH     (DESC_PTR_WIDTH)
            ) u_dma_regs (
                .clk                (clk),
                .rst_n              (rst_n),
                
                // AXI4-Lite interface
                .s_axi_awaddr       (s_axi_ctrl_awaddr),
                .s_axi_awvalid      (s_axi_ctrl_awvalid),
                .s_axi_awready      (s_axi_ctrl_awready),
                .s_axi_wdata        (s_axi_ctrl_wdata),
                .s_axi_wstrb        (s_axi_ctrl_wstrb),
                .s_axi_wvalid       (s_axi_ctrl_wvalid),
                .s_axi_wready       (s_axi_ctrl_wready),
                .s_axi_bresp        (s_axi_ctrl_bresp),
                .s_axi_bvalid       (s_axi_ctrl_bvalid),
                .s_axi_bready       (s_axi_ctrl_bready),
                .s_axi_araddr       (s_axi_ctrl_araddr),
                .s_axi_arvalid      (s_axi_ctrl_arvalid),
                .s_axi_arready      (s_axi_ctrl_arready),
                .s_axi_rdata        (s_axi_ctrl_rdata),
                .s_axi_rresp        (s_axi_ctrl_rresp),
                .s_axi_rvalid       (s_axi_ctrl_rvalid),
                .s_axi_rready       (s_axi_ctrl_rready),
                
                // Control outputs
                .dma_tx_enable      (dma_tx_enable),
                .dma_rx_enable      (dma_rx_enable),
                .dma_reset          (dma_reset),
                .tx_desc_base_addr  (tx_desc_base_addr),
                .tx_desc_ring_size  (tx_desc_ring_size),
                .rx_desc_base_addr  (rx_desc_base_addr),
                .rx_desc_ring_size  (rx_desc_ring_size),
                .irq_mask           (irq_mask),
                
                // Status inputs
                .tx_desc_busy       (tx_desc_busy),
                .rx_desc_busy       (rx_desc_busy),
                .tx_pkt_count       (tx_pkt_count),
                .rx_pkt_count       (rx_pkt_count),
                .tx_err_count       (tx_err_count),
                .rx_err_count       (rx_err_count),
                
                // Interrupt inputs
                .int_tx_done        (int_tx_done_raw),
                .int_rx_done        (int_rx_done_raw),
                .int_tx_err         (int_tx_err_raw),
                .int_rx_err         (int_rx_err_raw)
            );

            //==================================================================
            // Module Instantiation: TX DMA Engine
            //==================================================================
            eth_tx_dma #(
                .AXIS_DATA_WIDTH    (AXIS_DATA_WIDTH),
                .MEM_DATA_WIDTH     (M_AXI_DATA_WIDTH),
                .MEM_ADDR_WIDTH     (M_AXI_ADDR_WIDTH),
                .DESC_ADDR_WIDTH    (DESC_ADDR_WIDTH),
                .DESC_PTR_WIDTH     (DESC_PTR_WIDTH),
                .BUF_SIZE_WIDTH     (BUF_SIZE_WIDTH),
                .MAX_BURST          (M_AXI_MAX_BURST)
            ) u_tx_dma (
                .clk                (clk),
                .rst_n              (rst_n),
                .dma_enable         (dma_tx_enable),
                
                // Descriptor interface
                .desc_base_addr     (tx_desc_base_addr),
                .desc_ring_size     (tx_desc_ring_size),
                .desc_req           (tx_desc_req),
                .desc_ack           (tx_desc_ack),
                .desc_addr          (tx_desc_addr),
                .desc_data          (tx_desc_data),
                .desc_valid         (tx_desc_valid),
                .desc_wb_req        (tx_desc_wb_req),
                .desc_wb_ack        (tx_desc_wb_ack),
                .desc_wb_addr       (tx_desc_wb_addr),
                .desc_wb_data       (tx_desc_wb_data),
                
                // Memory read interface
                .mem_rd_req         (tx_data_req),
                .mem_rd_ack         (tx_data_ack),
                .mem_rd_addr        (tx_data_addr),
                .mem_rd_len         (tx_data_len),
                .mem_rd_data        (tx_data_rdata),
                .mem_rd_valid       (tx_data_rvalid),
                .mem_rd_last        (tx_data_rlast),
                .mem_rd_ready       (tx_data_rready),
                
                // AXI-Stream to MAC
                .m_axis_tdata       (m_axis_mac_tx_tdata),
                .m_axis_tvalid      (m_axis_mac_tx_tvalid),
                .m_axis_tlast       (m_axis_mac_tx_tlast),
                .m_axis_tuser       (m_axis_mac_tx_tuser),
                .m_axis_tready      (m_axis_mac_tx_tready),
                
                // Status and interrupts
                .tx_busy            (tx_desc_busy),
                .tx_pkt_count       (tx_pkt_count),
                .tx_err_count       (tx_err_count),
                .int_tx_done        (int_tx_done_raw),
                .int_tx_err         (int_tx_err_raw)
            );

            //==================================================================
            // Module Instantiation: RX DMA Engine
            //==================================================================
            eth_rx_dma #(
                .AXIS_DATA_WIDTH    (AXIS_DATA_WIDTH),
                .AXIS_USER_WIDTH    (AXIS_USER_WIDTH),
                .MEM_DATA_WIDTH     (M_AXI_DATA_WIDTH),
                .MEM_ADDR_WIDTH     (M_AXI_ADDR_WIDTH),
                .DESC_ADDR_WIDTH    (DESC_ADDR_WIDTH),
                .DESC_PTR_WIDTH     (DESC_PTR_WIDTH),
                .BUF_SIZE_WIDTH     (BUF_SIZE_WIDTH),
                .MAX_BURST          (M_AXI_MAX_BURST)
            ) u_rx_dma (
                .clk                (clk),
                .rst_n              (rst_n),
                .dma_enable         (dma_rx_enable),
                
                // Descriptor interface
                .desc_base_addr     (rx_desc_base_addr),
                .desc_ring_size     (rx_desc_ring_size),
                .desc_req           (rx_desc_req),
                .desc_ack           (rx_desc_ack),
                .desc_addr          (rx_desc_addr),
                .desc_data          (rx_desc_data),
                .desc_valid         (rx_desc_valid),
                .desc_wb_req        (rx_desc_wb_req),
                .desc_wb_ack        (rx_desc_wb_ack),
                .desc_wb_addr       (rx_desc_wb_addr),
                .desc_wb_data       (rx_desc_wb_data),
                
                // Memory write interface
                .mem_wr_req         (rx_data_req),
                .mem_wr_ack         (rx_data_ack),
                .mem_wr_addr        (rx_data_addr),
                .mem_wr_len         (rx_data_len),
                .mem_wr_data        (rx_data_wdata),
                .mem_wr_valid       (rx_data_wvalid),
                .mem_wr_last        (rx_data_wlast),
                .mem_wr_ready       (rx_data_wready),
                .mem_wr_strb        (rx_data_wstrb),
                
                // AXI-Stream from MAC
                .s_axis_tdata       (s_axis_mac_rx_tdata),
                .s_axis_tvalid      (s_axis_mac_rx_tvalid),
                .s_axis_tlast       (s_axis_mac_rx_tlast),
                .s_axis_tuser       (s_axis_mac_rx_tuser),
                .s_axis_tready      (s_axis_mac_rx_tready),
                
                // Status and interrupts
                .rx_busy            (rx_desc_busy),
                .rx_pkt_count       (rx_pkt_count),
                .rx_err_count       (rx_err_count),
                .int_rx_done        (int_rx_done_raw),
                .int_rx_err         (int_rx_err_raw)
            );

            //==================================================================
            // Module Instantiation: Descriptor Manager & AXI4 Master
            //==================================================================
            eth_dma_desc #(
                .MEM_ADDR_WIDTH     (M_AXI_ADDR_WIDTH),
                .MEM_DATA_WIDTH     (M_AXI_DATA_WIDTH),
                .MEM_ID_WIDTH       (M_AXI_ID_WIDTH),
                .DESC_ADDR_WIDTH    (DESC_ADDR_WIDTH),
                .BUF_SIZE_WIDTH     (BUF_SIZE_WIDTH),
                .MAX_BURST          (M_AXI_MAX_BURST)
            ) u_dma_desc (
                .clk                (clk),
                .rst_n              (rst_n),
                
                // TX descriptor interface
                .tx_desc_req        (tx_desc_req),
                .tx_desc_ack        (tx_desc_ack),
                .tx_desc_addr       (tx_desc_addr),
                .tx_desc_data       (tx_desc_data),
                .tx_desc_valid      (tx_desc_valid),
                .tx_desc_wb_req     (tx_desc_wb_req),
                .tx_desc_wb_ack     (tx_desc_wb_ack),
                .tx_desc_wb_addr    (tx_desc_wb_addr),
                .tx_desc_wb_data    (tx_desc_wb_data),
                
                // RX descriptor interface
                .rx_desc_req        (rx_desc_req),
                .rx_desc_ack        (rx_desc_ack),
                .rx_desc_addr       (rx_desc_addr),
                .rx_desc_data       (rx_desc_data),
                .rx_desc_valid      (rx_desc_valid),
                .rx_desc_wb_req     (rx_desc_wb_req),
                .rx_desc_wb_ack     (rx_desc_wb_ack),
                .rx_desc_wb_addr    (rx_desc_wb_addr),
                .rx_desc_wb_data    (rx_desc_wb_data),
                
                // TX data read interface
                .tx_data_req        (tx_data_req),
                .tx_data_ack        (tx_data_ack),
                .tx_data_addr       (tx_data_addr),
                .tx_data_len        (tx_data_len),
                .tx_data_rdata      (tx_data_rdata),
                .tx_data_rvalid     (tx_data_rvalid),
                .tx_data_rlast      (tx_data_rlast),
                .tx_data_rready     (tx_data_rready),
                
                // RX data write interface
                .rx_data_req        (rx_data_req),
                .rx_data_ack        (rx_data_ack),
                .rx_data_addr       (rx_data_addr),
                .rx_data_len        (rx_data_len),
                .rx_data_wdata      (rx_data_wdata),
                .rx_data_wvalid     (rx_data_wvalid),
                .rx_data_wlast      (rx_data_wlast),
                .rx_data_wready     (rx_data_wready),
                .rx_data_wstrb      (rx_data_wstrb),
                
                // AXI4 Master interface to memory
                .m_axi_awid         (m_axi_mem_awid),
                .m_axi_awaddr       (m_axi_mem_awaddr),
                .m_axi_awlen        (m_axi_mem_awlen),
                .m_axi_awsize       (m_axi_mem_awsize),
                .m_axi_awburst      (m_axi_mem_awburst),
                .m_axi_awlock       (m_axi_mem_awlock),
                .m_axi_awcache      (m_axi_mem_awcache),
                .m_axi_awprot       (m_axi_mem_awprot),
                .m_axi_awvalid      (m_axi_mem_awvalid),
                .m_axi_awready      (m_axi_mem_awready),
                .m_axi_wdata        (m_axi_mem_wdata),
                .m_axi_wstrb        (m_axi_mem_wstrb),
                .m_axi_wlast        (m_axi_mem_wlast),
                .m_axi_wvalid       (m_axi_mem_wvalid),
                .m_axi_wready       (m_axi_mem_wready),
                .m_axi_bid          (m_axi_mem_bid),
                .m_axi_bresp        (m_axi_mem_bresp),
                .m_axi_bvalid       (m_axi_mem_bvalid),
                .m_axi_bready       (m_axi_mem_bready),
                .m_axi_arid         (m_axi_mem_arid),
                .m_axi_araddr       (m_axi_mem_araddr),
                .m_axi_arlen        (m_axi_mem_arlen),
                .m_axi_arsize       (m_axi_mem_arsize),
                .m_axi_arburst      (m_axi_mem_arburst),
                .m_axi_arlock       (m_axi_mem_arlock),
                .m_axi_arcache      (m_axi_mem_arcache),
                .m_axi_arprot       (m_axi_mem_arprot),
                .m_axi_arvalid      (m_axi_mem_arvalid),
                .m_axi_arready      (m_axi_mem_arready),
                .m_axi_rid          (m_axi_mem_rid),
                .m_axi_rdata        (m_axi_mem_rdata),
                .m_axi_rresp        (m_axi_mem_rresp),
                .m_axi_rlast        (m_axi_mem_rlast),
                .m_axi_rvalid       (m_axi_mem_rvalid),
                .m_axi_rready       (m_axi_mem_rready)
            );

            //==================================================================
            // Module Instantiation: Interrupt Controller
            //==================================================================
            eth_dma_irq u_dma_irq (
                .clk                (clk),
                .rst_n              (rst_n),
                
                // Interrupt sources
                .int_tx_done_raw    (int_tx_done_raw),
                .int_rx_done_raw    (int_rx_done_raw),
                .int_tx_err_raw     (int_tx_err_raw),
                .int_rx_err_raw     (int_rx_err_raw),
                
                // Interrupt mask
                .irq_mask           (irq_mask),
                
                // Interrupt outputs
                .irq_tx_done        (irq_tx_done),
                .irq_rx_done        (irq_rx_done),
                .irq_tx_error       (irq_tx_error),
                .irq_rx_error       (irq_rx_error),
                .irq_combined       (irq_combined)
            );

            // User-side TX/RX unused in DMA mode
            assign s_axis_user_tx_tready = 1'b0;
            assign m_axis_user_rx_tdata  = {AXIS_DATA_WIDTH{1'b0}};
            assign m_axis_user_rx_tvalid = 1'b0;
            assign m_axis_user_rx_tlast  = 1'b0;
            assign m_axis_user_rx_tuser  = {AXIS_USER_WIDTH{1'b0}};

        end else begin : gen_dma_bypassed
            
            //==================================================================
            // DMA Bypass Mode: Direct Passthrough
            //==================================================================
            
            // TX path: User -> MAC
            assign m_axis_mac_tx_tdata  = s_axis_user_tx_tdata;
            assign m_axis_mac_tx_tvalid = s_axis_user_tx_tvalid;
            assign m_axis_mac_tx_tlast  = s_axis_user_tx_tlast;
            assign m_axis_mac_tx_tuser  = s_axis_user_tx_tuser;
            assign s_axis_user_tx_tready = m_axis_mac_tx_tready;
            
            // RX path: MAC -> User
            assign m_axis_user_rx_tdata  = s_axis_mac_rx_tdata;
            assign m_axis_user_rx_tvalid = s_axis_mac_rx_tvalid;
            assign m_axis_user_rx_tlast  = s_axis_mac_rx_tlast;
            assign m_axis_user_rx_tuser  = s_axis_mac_rx_tuser;
            assign s_axis_mac_rx_tready  = m_axis_user_rx_tready;
            
            // AXI4-Lite control interface - tie off with error response
            assign s_axi_ctrl_awready = 1'b1;
            assign s_axi_ctrl_wready  = 1'b1;
            assign s_axi_ctrl_bresp   = 2'b11;  // DECERR
            assign s_axi_ctrl_bvalid  = s_axi_ctrl_awvalid || s_axi_ctrl_wvalid;
            assign s_axi_ctrl_arready = 1'b1;
            assign s_axi_ctrl_rdata   = {C_DATA_WIDTH{1'b0}};
            assign s_axi_ctrl_rresp   = 2'b11;  // DECERR
            assign s_axi_ctrl_rvalid  = s_axi_ctrl_arvalid;
            
            // AXI4 memory interface - tie off
            assign m_axi_mem_awid     = {M_AXI_ID_WIDTH{1'b0}};
            assign m_axi_mem_awaddr   = {M_AXI_ADDR_WIDTH{1'b0}};
            assign m_axi_mem_awlen    = 8'h0;
            assign m_axi_mem_awsize   = 3'h0;
            assign m_axi_mem_awburst  = 2'b01;
            assign m_axi_mem_awlock   = 1'b0;
            assign m_axi_mem_awcache  = 4'h0;
            assign m_axi_mem_awprot   = 3'h0;
            assign m_axi_mem_awvalid  = 1'b0;
            assign m_axi_mem_wdata    = {M_AXI_DATA_WIDTH{1'b0}};
            assign m_axi_mem_wstrb    = {M_AXI_DATA_WIDTH/8{1'b0}};
            assign m_axi_mem_wlast    = 1'b0;
            assign m_axi_mem_wvalid   = 1'b0;
            assign m_axi_mem_bready   = 1'b1;
            assign m_axi_mem_arid     = {M_AXI_ID_WIDTH{1'b0}};
            assign m_axi_mem_araddr   = {M_AXI_ADDR_WIDTH{1'b0}};
            assign m_axi_mem_arlen    = 8'h0;
            assign m_axi_mem_arsize   = 3'h0;
            assign m_axi_mem_arburst  = 2'b01;
            assign m_axi_mem_arlock   = 1'b0;
            assign m_axi_mem_arcache  = 4'h0;
            assign m_axi_mem_arprot   = 3'h0;
            assign m_axi_mem_arvalid  = 1'b0;
            assign m_axi_mem_rready   = 1'b1;
            
            // No interrupts in bypass mode
            assign irq_tx_done    = 1'b0;
            assign irq_rx_done    = 1'b0;
            assign irq_tx_error   = 1'b0;
            assign irq_rx_error   = 1'b0;
            assign irq_combined   = 1'b0;
            
        end
    endgenerate

endmodule
