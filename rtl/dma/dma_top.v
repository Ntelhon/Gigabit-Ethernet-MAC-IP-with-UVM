//==============================================================================
// File: dma_top.v
// Description: DMA Subsystem Top Module
//
// Purpose:
//   Integrates all DMA components: descriptor engine, TX DMA, RX DMA, and
//   register block. Provides unified interfaces to the rest of the system.
//
// Interfaces:
//   - AXI4-Lite slave for configuration (connected via eth_controller_regs)
//   - AXI4 master for memory access (descriptors + data)
//   - AXI-Stream slave for RX data (from MAC)
//   - AXI-Stream master for TX data (to MAC)
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`include "dma_pkg.v"

module dma_top #(
    parameter ADDR_WIDTH    = 64,       // AXI address width
    parameter AXI_DATA_W    = 64,       // AXI-MM data width
    parameter AXIS_DATA_W   = 8,        // AXI-Stream data width
    parameter MAX_BURST_LEN = 16,       // Max AXI burst length
    parameter TX_FIFO_DEPTH = 2048,     // TX FIFO depth
    parameter RX_FIFO_DEPTH = 4096      // RX FIFO depth
)(
    // Clock and Reset
    input  wire                     clk,
    input  wire                     rst_n,
    
    //--------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (Configuration)
    //--------------------------------------------------------------------------
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,
    input  wire [7:0]               s_axi_awaddr,
    
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,
    input  wire [31:0]              s_axi_wdata,
    input  wire [3:0]               s_axi_wstrb,
    
    output wire                     s_axi_bvalid,
    input  wire                     s_axi_bready,
    output wire [1:0]               s_axi_bresp,
    
    input  wire                     s_axi_arvalid,
    output wire                     s_axi_arready,
    input  wire [7:0]               s_axi_araddr,
    
    output wire                     s_axi_rvalid,
    input  wire                     s_axi_rready,
    output wire [31:0]              s_axi_rdata,
    output wire [1:0]               s_axi_rresp,
    
    //--------------------------------------------------------------------------
    // AXI4 Master Interface (Memory Access)
    //--------------------------------------------------------------------------
    // Write Address Channel
    output wire                     m_axi_awvalid,
    input  wire                     m_axi_awready,
    output wire [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output wire [7:0]               m_axi_awlen,
    output wire [2:0]               m_axi_awsize,
    output wire [1:0]               m_axi_awburst,
    output wire [3:0]               m_axi_awid,
    
    // Write Data Channel
    output wire                     m_axi_wvalid,
    input  wire                     m_axi_wready,
    output wire [AXI_DATA_W-1:0]    m_axi_wdata,
    output wire [AXI_DATA_W/8-1:0]  m_axi_wstrb,
    output wire                     m_axi_wlast,
    
    // Write Response Channel
    input  wire                     m_axi_bvalid,
    output wire                     m_axi_bready,
    input  wire [1:0]               m_axi_bresp,
    input  wire [3:0]               m_axi_bid,
    
    // Read Address Channel
    output wire                     m_axi_arvalid,
    input  wire                     m_axi_arready,
    output wire [ADDR_WIDTH-1:0]    m_axi_araddr,
    output wire [7:0]               m_axi_arlen,
    output wire [2:0]               m_axi_arsize,
    output wire [1:0]               m_axi_arburst,
    output wire [3:0]               m_axi_arid,
    
    // Read Data Channel
    input  wire                     m_axi_rvalid,
    output wire                     m_axi_rready,
    input  wire [AXI_DATA_W-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire [3:0]               m_axi_rid,
    
    //--------------------------------------------------------------------------
    // AXI-Stream TX Interface (to MAC)
    //--------------------------------------------------------------------------
    output wire                     m_axis_tx_tvalid,
    input  wire                     m_axis_tx_tready,
    output wire [AXIS_DATA_W-1:0]   m_axis_tx_tdata,
    output wire                     m_axis_tx_tlast,
    output wire                     m_axis_tx_tuser,
    
    //--------------------------------------------------------------------------
    // AXI-Stream RX Interface (from MAC)
    //--------------------------------------------------------------------------
    input  wire                     s_axis_rx_tvalid,
    output wire                     s_axis_rx_tready,
    input  wire [AXIS_DATA_W-1:0]   s_axis_rx_tdata,
    input  wire                     s_axis_rx_tlast,
    input  wire                     s_axis_rx_tuser,
    
    //--------------------------------------------------------------------------
    // Interrupt
    //--------------------------------------------------------------------------
    output wire                     dma_irq
);

    //--------------------------------------------------------------------------
    // Internal Signals - Register Interface
    //--------------------------------------------------------------------------
    // TX control
    wire                    tx_enable;
    wire                    tx_reset;
    wire                    tx_irq_en;
    wire [ADDR_WIDTH-1:0]   tx_ring_base;
    wire [15:0]             tx_ring_size;
    wire [15:0]             tx_head_ptr_sw;
    wire                    tx_busy;
    wire                    tx_halted;
    wire                    tx_error;
    wire [15:0]             tx_tail_ptr_hw;
    wire [31:0]             tx_pkt_cnt;
    
    // RX control
    wire                    rx_enable;
    wire                    rx_reset;
    wire                    rx_irq_en;
    wire [ADDR_WIDTH-1:0]   rx_ring_base;
    wire [15:0]             rx_ring_size;
    wire [15:0]             rx_tail_ptr_sw;
    wire                    rx_busy;
    wire                    rx_halted;
    wire                    rx_error;
    wire [15:0]             rx_head_ptr_hw;
    wire [31:0]             rx_pkt_cnt;
    
    //--------------------------------------------------------------------------
    // Internal Signals - Descriptor Engine
    //--------------------------------------------------------------------------
    // TX descriptor interface
    wire                    tx_desc_valid;
    wire                    tx_desc_ready;
    wire [ADDR_WIDTH-1:0]   tx_buf_addr;
    wire [15:0]             tx_buf_len;
    wire [31:0]             tx_desc_ctrl;
    wire [15:0]             tx_desc_index;
    
    wire                    tx_wb_valid;
    wire                    tx_wb_ready;
    wire [15:0]             tx_wb_index;
    wire [31:0]             tx_wb_status;
    
    // RX descriptor interface
    wire                    rx_desc_valid;
    wire                    rx_desc_ready;
    wire [ADDR_WIDTH-1:0]   rx_buf_addr;
    wire [15:0]             rx_buf_len;
    wire [31:0]             rx_desc_ctrl;
    wire [15:0]             rx_desc_index;
    
    wire                    rx_wb_valid;
    wire                    rx_wb_ready;
    wire [15:0]             rx_wb_index;
    wire [15:0]             rx_wb_length;
    wire [31:0]             rx_wb_status;
    
    //--------------------------------------------------------------------------
    // Internal Signals - AXI Arbiter
    //--------------------------------------------------------------------------
    // Descriptor engine AXI
    wire                    desc_arvalid, desc_arready;
    wire [ADDR_WIDTH-1:0]   desc_araddr;
    wire [7:0]              desc_arlen;
    wire [2:0]              desc_arsize;
    wire [1:0]              desc_arburst;
    wire [3:0]              desc_arid;
    wire                    desc_rvalid, desc_rready;
    wire [AXI_DATA_W-1:0]   desc_rdata;
    wire [1:0]              desc_rresp;
    wire                    desc_rlast;
    wire [3:0]              desc_rid;
    
    wire                    desc_awvalid, desc_awready;
    wire [ADDR_WIDTH-1:0]   desc_awaddr;
    wire [7:0]              desc_awlen;
    wire [2:0]              desc_awsize;
    wire [1:0]              desc_awburst;
    wire [3:0]              desc_awid;
    wire                    desc_wvalid, desc_wready;
    wire [AXI_DATA_W-1:0]   desc_wdata;
    wire [AXI_DATA_W/8-1:0] desc_wstrb;
    wire                    desc_wlast;
    wire                    desc_bvalid, desc_bready;
    wire [1:0]              desc_bresp;
    wire [3:0]              desc_bid;
    
    // TX DMA AXI (read only)
    wire                    txdma_arvalid, txdma_arready;
    wire [ADDR_WIDTH-1:0]   txdma_araddr;
    wire [7:0]              txdma_arlen;
    wire [2:0]              txdma_arsize;
    wire [1:0]              txdma_arburst;
    wire [3:0]              txdma_arid;
    wire                    txdma_rvalid, txdma_rready;
    wire [AXI_DATA_W-1:0]   txdma_rdata;
    wire [1:0]              txdma_rresp;
    wire                    txdma_rlast;
    wire [3:0]              txdma_rid;
    
    // RX DMA AXI (write only)
    wire                    rxdma_awvalid, rxdma_awready;
    wire [ADDR_WIDTH-1:0]   rxdma_awaddr;
    wire [7:0]              rxdma_awlen;
    wire [2:0]              rxdma_awsize;
    wire [1:0]              rxdma_awburst;
    wire [3:0]              rxdma_awid;
    wire                    rxdma_wvalid, rxdma_wready;
    wire [AXI_DATA_W-1:0]   rxdma_wdata;
    wire [AXI_DATA_W/8-1:0] rxdma_wstrb;
    wire                    rxdma_wlast;
    wire                    rxdma_bvalid, rxdma_bready;
    wire [1:0]              rxdma_bresp;
    wire [3:0]              rxdma_bid;
    
    //--------------------------------------------------------------------------
    // Interrupt Signals
    //--------------------------------------------------------------------------
    wire int_tx_done;
    wire int_tx_err;
    wire int_rx_done;
    wire int_rx_err;
    wire int_desc_err;
    
    assign int_tx_done = tx_wb_valid && tx_wb_ready;
    assign int_tx_err  = tx_error;
    assign int_rx_done = rx_wb_valid && rx_wb_ready;
    assign int_rx_err  = rx_error;

    //--------------------------------------------------------------------------
    // DMA Register Block
    //--------------------------------------------------------------------------
    dma_regs #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_dma_regs (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI-Lite slave
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        
        // TX control
        .tx_enable      (tx_enable),
        .tx_reset       (tx_reset),
        .tx_irq_en      (tx_irq_en),
        .tx_ring_base   (tx_ring_base),
        .tx_ring_size   (tx_ring_size),
        .tx_head_ptr    (tx_head_ptr_sw),
        .tx_busy        (tx_busy),
        .tx_halted      (tx_halted),
        .tx_error       (tx_error),
        .tx_tail_ptr    (tx_tail_ptr_hw),
        .tx_pkt_cnt     (tx_pkt_cnt),
        
        // RX control
        .rx_enable      (rx_enable),
        .rx_reset       (rx_reset),
        .rx_irq_en      (rx_irq_en),
        .rx_ring_base   (rx_ring_base),
        .rx_ring_size   (rx_ring_size),
        .rx_tail_ptr    (rx_tail_ptr_sw),
        .rx_busy        (rx_busy),
        .rx_halted      (rx_halted),
        .rx_error       (rx_error),
        .rx_head_ptr    (rx_head_ptr_hw),
        .rx_pkt_cnt     (rx_pkt_cnt),
        
        // Interrupts
        .int_tx_done    (int_tx_done),
        .int_tx_err     (int_tx_err),
        .int_rx_done    (int_rx_done),
        .int_rx_err     (int_rx_err),
        .int_desc_err   (int_desc_err),
        .dma_irq        (dma_irq)
    );

    //--------------------------------------------------------------------------
    // Descriptor Engine
    //--------------------------------------------------------------------------
    dma_desc #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_W),
        .DESC_SIZE  (16),
        .MAX_RING_SZ(256)
    ) u_dma_desc (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // TX ring control
        .tx_enable      (tx_enable),
        .tx_reset       (tx_reset),
        .tx_ring_base   (tx_ring_base),
        .tx_ring_size   (tx_ring_size),
        .tx_head_ptr    (tx_head_ptr_sw),
        .tx_tail_ptr    (tx_tail_ptr_hw),
        
        // TX descriptor output
        .tx_desc_valid  (tx_desc_valid),
        .tx_desc_ready  (tx_desc_ready),
        .tx_buf_addr    (tx_buf_addr),
        .tx_buf_len     (tx_buf_len),
        .tx_desc_ctrl   (tx_desc_ctrl),
        .tx_desc_index  (tx_desc_index),
        
        // TX writeback
        .tx_wb_valid    (tx_wb_valid),
        .tx_wb_ready    (tx_wb_ready),
        .tx_wb_index    (tx_wb_index),
        .tx_wb_status   (tx_wb_status),
        
        // RX ring control
        .rx_enable      (rx_enable),
        .rx_reset       (rx_reset),
        .rx_ring_base   (rx_ring_base),
        .rx_ring_size   (rx_ring_size),
        .rx_head_ptr    (rx_head_ptr_hw),
        .rx_tail_ptr    (rx_tail_ptr_sw),
        
        // RX descriptor output
        .rx_desc_valid  (rx_desc_valid),
        .rx_desc_ready  (rx_desc_ready),
        .rx_buf_addr    (rx_buf_addr),
        .rx_buf_len     (rx_buf_len),
        .rx_desc_ctrl   (rx_desc_ctrl),
        .rx_desc_index  (rx_desc_index),
        
        // RX writeback
        .rx_wb_valid    (rx_wb_valid),
        .rx_wb_ready    (rx_wb_ready),
        .rx_wb_index    (rx_wb_index),
        .rx_wb_length   (rx_wb_length),
        .rx_wb_status   (rx_wb_status),
        
        // AXI master
        .m_axi_arvalid  (desc_arvalid),
        .m_axi_arready  (desc_arready),
        .m_axi_araddr   (desc_araddr),
        .m_axi_arlen    (desc_arlen),
        .m_axi_arsize   (desc_arsize),
        .m_axi_arburst  (desc_arburst),
        .m_axi_arid     (desc_arid),
        .m_axi_rvalid   (desc_rvalid),
        .m_axi_rready   (desc_rready),
        .m_axi_rdata    (desc_rdata),
        .m_axi_rresp    (desc_rresp),
        .m_axi_rlast    (desc_rlast),
        .m_axi_rid      (desc_rid),
        .m_axi_awvalid  (desc_awvalid),
        .m_axi_awready  (desc_awready),
        .m_axi_awaddr   (desc_awaddr),
        .m_axi_awlen    (desc_awlen),
        .m_axi_awsize   (desc_awsize),
        .m_axi_awburst  (desc_awburst),
        .m_axi_awid     (desc_awid),
        .m_axi_wvalid   (desc_wvalid),
        .m_axi_wready   (desc_wready),
        .m_axi_wdata    (desc_wdata),
        .m_axi_wstrb    (desc_wstrb),
        .m_axi_wlast    (desc_wlast),
        .m_axi_bvalid   (desc_bvalid),
        .m_axi_bready   (desc_bready),
        .m_axi_bresp    (desc_bresp),
        .m_axi_bid      (desc_bid),
        
        // Status
        .tx_desc_avail  (),
        .rx_desc_avail  (),
        .desc_error     (int_desc_err)
    );

    //--------------------------------------------------------------------------
    // TX DMA Engine
    //--------------------------------------------------------------------------
    wire [31:0] tx_byte_cnt_unused;
    
    dma_tx #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .AXI_DATA_W     (AXI_DATA_W),
        .AXIS_DATA_W    (AXIS_DATA_W),
        .MAX_BURST_LEN  (MAX_BURST_LEN),
        .FIFO_DEPTH     (TX_FIFO_DEPTH)
    ) u_dma_tx (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // Control
        .enable         (tx_enable),
        .soft_reset     (tx_reset),
        .busy           (tx_busy),
        .halted         (tx_halted),
        .error          (tx_error),
        
        // Descriptor interface
        .desc_valid     (tx_desc_valid),
        .desc_ready     (tx_desc_ready),
        .desc_buf_addr  (tx_buf_addr),
        .desc_buf_len   (tx_buf_len),
        .desc_ctrl      (tx_desc_ctrl),
        .desc_index     (tx_desc_index),
        
        // Writeback
        .wb_valid       (tx_wb_valid),
        .wb_ready       (tx_wb_ready),
        .wb_index       (tx_wb_index),
        .wb_status      (tx_wb_status),
        
        // AXI read
        .m_axi_arvalid  (txdma_arvalid),
        .m_axi_arready  (txdma_arready),
        .m_axi_araddr   (txdma_araddr),
        .m_axi_arlen    (txdma_arlen),
        .m_axi_arsize   (txdma_arsize),
        .m_axi_arburst  (txdma_arburst),
        .m_axi_arid     (txdma_arid),
        .m_axi_rvalid   (txdma_rvalid),
        .m_axi_rready   (txdma_rready),
        .m_axi_rdata    (txdma_rdata),
        .m_axi_rresp    (txdma_rresp),
        .m_axi_rlast    (txdma_rlast),
        .m_axi_rid      (txdma_rid),
        
        // AXI-Stream TX
        .m_axis_tvalid  (m_axis_tx_tvalid),
        .m_axis_tready  (m_axis_tx_tready),
        .m_axis_tdata   (m_axis_tx_tdata),
        .m_axis_tlast   (m_axis_tx_tlast),
        .m_axis_tuser   (m_axis_tx_tuser),
        
        // Stats
        .tx_pkt_cnt     (tx_pkt_cnt),
        .tx_byte_cnt    (tx_byte_cnt_unused)
    );

    //--------------------------------------------------------------------------
    // RX DMA Engine
    //--------------------------------------------------------------------------
    wire [31:0] rx_byte_cnt_unused;
    wire [31:0] rx_drop_cnt_unused;
    
    dma_rx #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .AXI_DATA_W     (AXI_DATA_W),
        .AXIS_DATA_W    (AXIS_DATA_W),
        .MAX_BURST_LEN  (MAX_BURST_LEN),
        .FIFO_DEPTH     (RX_FIFO_DEPTH)
    ) u_dma_rx (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // Control
        .enable         (rx_enable),
        .soft_reset     (rx_reset),
        .busy           (rx_busy),
        .halted         (rx_halted),
        .error          (rx_error),
        
        // Descriptor interface
        .desc_valid     (rx_desc_valid),
        .desc_ready     (rx_desc_ready),
        .desc_buf_addr  (rx_buf_addr),
        .desc_buf_len   (rx_buf_len),
        .desc_ctrl      (rx_desc_ctrl),
        .desc_index     (rx_desc_index),
        
        // Writeback
        .wb_valid       (rx_wb_valid),
        .wb_ready       (rx_wb_ready),
        .wb_index       (rx_wb_index),
        .wb_length      (rx_wb_length),
        .wb_status      (rx_wb_status),
        
        // AXI write
        .m_axi_awvalid  (rxdma_awvalid),
        .m_axi_awready  (rxdma_awready),
        .m_axi_awaddr   (rxdma_awaddr),
        .m_axi_awlen    (rxdma_awlen),
        .m_axi_awsize   (rxdma_awsize),
        .m_axi_awburst  (rxdma_awburst),
        .m_axi_awid     (rxdma_awid),
        .m_axi_wvalid   (rxdma_wvalid),
        .m_axi_wready   (rxdma_wready),
        .m_axi_wdata    (rxdma_wdata),
        .m_axi_wstrb    (rxdma_wstrb),
        .m_axi_wlast    (rxdma_wlast),
        .m_axi_bvalid   (rxdma_bvalid),
        .m_axi_bready   (rxdma_bready),
        .m_axi_bresp    (rxdma_bresp),
        .m_axi_bid      (rxdma_bid),
        
        // AXI-Stream RX
        .s_axis_tvalid  (s_axis_rx_tvalid),
        .s_axis_tready  (s_axis_rx_tready),
        .s_axis_tdata   (s_axis_rx_tdata),
        .s_axis_tlast   (s_axis_rx_tlast),
        .s_axis_tuser   (s_axis_rx_tuser),
        
        // Stats
        .rx_pkt_cnt     (rx_pkt_cnt),
        .rx_byte_cnt    (rx_byte_cnt_unused),
        .rx_drop_cnt    (rx_drop_cnt_unused)
    );

    //--------------------------------------------------------------------------
    // AXI Arbiter - Transaction-locked arbiter for multiple masters
    //--------------------------------------------------------------------------
    // Read channel: desc + txdma
    // Write channel: desc + rxdma
    //
    // CRITICAL: Arbiter must remain locked to selected master for entire
    // transaction (AW + all W beats + B response) to maintain AXI protocol.
    
    reg read_arb_sel;    // 0=desc, 1=txdma
    reg write_arb_sel;   // 0=desc, 1=rxdma
    reg write_locked;    // Write transaction in progress, don't switch arbiter
    
    // Read arbitration (address + data on same channel, uses AXI ID for demux)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_arb_sel <= 1'b0;
        end else begin
            // Can only switch when no outstanding address request
            if (!m_axi_arvalid || m_axi_arready) begin
                if (read_arb_sel == 1'b0 && txdma_arvalid && !desc_arvalid)
                    read_arb_sel <= 1'b1;
                else if (read_arb_sel == 1'b1 && desc_arvalid && !txdma_arvalid)
                    read_arb_sel <= 1'b0;
                else if (desc_arvalid || txdma_arvalid) begin
                    // Round robin
                    read_arb_sel <= ~read_arb_sel;
                end
            end
        end
    end
    
    // Write transaction lock + write arbitration selection.
    // NOTE: These were previously two separate always blocks that both drove
    // write_locked (one cleared it on B completion, the other set it on a new
    // grant) -- a multi-driver conflict. Merged into a single block so
    // write_locked has exactly one driver. Clear-on-completion is evaluated
    // first, so a same-cycle new grant (which re-asserts the lock) still wins,
    // preserving the original "lock BEFORE the handshake cycle" intent.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_arb_sel <= 1'b0;
            write_locked  <= 1'b0;
        end else begin
            if (m_axi_bvalid && m_axi_bready) begin
                // Write response completed, unlock (can accept new transaction next cycle)
                write_locked <= 1'b0;
            end

            // Can only switch when not locked and no pending address
            if (!write_locked && (!m_axi_awvalid || m_axi_awready)) begin
                if (write_arb_sel == 1'b0 && rxdma_awvalid && !desc_awvalid) begin
                    write_arb_sel <= 1'b1;
                    write_locked  <= 1'b1;
                end else if (write_arb_sel == 1'b1 && desc_awvalid && !rxdma_awvalid) begin
                    write_arb_sel <= 1'b0;
                    write_locked  <= 1'b1;
                end else if (desc_awvalid || rxdma_awvalid) begin
                    // Round robin
                    write_arb_sel <= ~write_arb_sel;
                end
            end
        end
    end
    
    // Read channel mux
    assign m_axi_arvalid = read_arb_sel ? txdma_arvalid : desc_arvalid;
    assign m_axi_araddr  = read_arb_sel ? txdma_araddr  : desc_araddr;
    assign m_axi_arlen   = read_arb_sel ? txdma_arlen   : desc_arlen;
    assign m_axi_arsize  = read_arb_sel ? txdma_arsize  : desc_arsize;
    assign m_axi_arburst = read_arb_sel ? txdma_arburst : desc_arburst;
    assign m_axi_arid    = read_arb_sel ? txdma_arid    : desc_arid;
    
    assign desc_arready  = !read_arb_sel && m_axi_arready;
    assign txdma_arready = read_arb_sel  && m_axi_arready;
    
    // Read data demux based on rid
    assign desc_rvalid  = m_axi_rvalid && (m_axi_rid == 4'h0);
    assign txdma_rvalid = m_axi_rvalid && (m_axi_rid == 4'h1);
    assign desc_rdata   = m_axi_rdata;
    assign txdma_rdata  = m_axi_rdata;
    assign desc_rresp   = m_axi_rresp;
    assign txdma_rresp  = m_axi_rresp;
    assign desc_rlast   = m_axi_rlast;
    assign txdma_rlast  = m_axi_rlast;
    assign desc_rid     = m_axi_rid;
    assign txdma_rid    = m_axi_rid;
    
    assign m_axi_rready = (m_axi_rid == 4'h0) ? desc_rready :
                          (m_axi_rid == 4'h1) ? txdma_rready : 1'b1;
    
    // Write channel mux
    assign m_axi_awvalid = write_arb_sel ? rxdma_awvalid : desc_awvalid;
    assign m_axi_awaddr  = write_arb_sel ? rxdma_awaddr  : desc_awaddr;
    assign m_axi_awlen   = write_arb_sel ? rxdma_awlen   : desc_awlen;
    assign m_axi_awsize  = write_arb_sel ? rxdma_awsize  : desc_awsize;
    assign m_axi_awburst = write_arb_sel ? rxdma_awburst : desc_awburst;
    assign m_axi_awid    = write_arb_sel ? rxdma_awid    : desc_awid;
    
    assign desc_awready  = !write_arb_sel && m_axi_awready;
    assign rxdma_awready = write_arb_sel  && m_axi_awready;
    
    assign m_axi_wvalid = write_arb_sel ? rxdma_wvalid : desc_wvalid;
    assign m_axi_wdata  = write_arb_sel ? rxdma_wdata  : desc_wdata;
    assign m_axi_wstrb  = write_arb_sel ? rxdma_wstrb  : desc_wstrb;
    assign m_axi_wlast  = write_arb_sel ? rxdma_wlast  : desc_wlast;
    
    assign desc_wready  = !write_arb_sel && m_axi_wready;
    assign rxdma_wready = write_arb_sel  && m_axi_wready;
    
    // Write response demux
    assign desc_bvalid  = m_axi_bvalid && (m_axi_bid == 4'h0);
    assign rxdma_bvalid = m_axi_bvalid && (m_axi_bid == 4'h2);
    assign desc_bresp   = m_axi_bresp;
    assign rxdma_bresp  = m_axi_bresp;
    assign desc_bid     = m_axi_bid;
    assign rxdma_bid    = m_axi_bid;
    
    assign m_axi_bready = (m_axi_bid == 4'h0) ? desc_bready :
                          (m_axi_bid == 4'h2) ? rxdma_bready : 1'b1;

endmodule
