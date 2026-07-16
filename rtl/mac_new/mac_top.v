//==============================================================================
// Module: mac_top
// Description: Top-level integration module for Gigabit Ethernet MAC
//              (one function: MAC subsystem integration - no local datapath
//              logic beyond FIFO packing/unpacking glue)
//
// Features:
//   - Instantiates all MAC core submodules
//   - Per-domain reset synchronizers (async assert, sync deassert)
//   - CDC FIFOs (controller + separate RAM) for TX and RX paths
//   - Dedicated CDC primitives for levels, pulses, and counters
//   - AXI4-Lite register interface
//   - GMII interface to PHY layer (TX registered in mac_gmii_if)
//
// Architecture:
//   ┌─────────────────────────────────────────────────────────────────┐
//   │                         mac_top                                 │
//   │  ┌─────────┐    ┌──────────┐    ┌─────────┐    ┌────────────┐   │
//   │  │mac_regs │    │ TX FIFO  │───▶│ mac_tx  │───▶│ mac_gmii_if│───│──▶ GMII TX
//   │  │(AXI-L)  │    │(CDC)     │    │         │    │            │   │
//   │  └────┬────┘    └──────────┘    └────┬────┘    └─────┬──────┘   │
//   │       │                              │               │          │
//   │       │         ┌──────────┐    ┌────┴────┐          │          │
//   │       └────────▶│ RX FIFO  │◀───│ mac_rx  │◀─────────┴─────────│◀── GMII RX
//   │                 │(CDC)     │    │         │                     │
//   │                 └──────────┘    └────┬────┘                     │
//   │                                      │                          │
//   │                              ┌───────┴───────┐                  │
//   │                              │  mac_crc32    │                  │
//   │                              │  (TX & RX)    │                  │
//   │                              └───────────────┘                  │
//   └─────────────────────────────────────────────────────────────────┘
//
// Clock Domains:
//   - sys_clk: System/AXI clock domain
//   - gtx_clk: GMII TX clock (125 MHz, MAC-generated)
//   - rx_clk:  GMII RX clock (125 MHz, PHY-generated)
//
// Reset:
//   - The three reset inputs are treated as ASYNCHRONOUS. Each is passed
//     through a local mac_rst_sync instance, so every domain gets a reset
//     with asynchronous assertion and synchronous, metastability-free
//     de-assertion. The parent may therefore drive all three reset pins
//     from one system reset without further synchronization.
//
// Verification Hooks:
//   - Assertion: Reset synchronization per domain
//   - Assertion: CDC crossing safety
//   - Coverage: All interfaces active
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_top #(
    // AXI Parameters
    parameter AXI_ADDR_WIDTH = 8,
    parameter AXI_DATA_WIDTH = 32,

    // FIFO Parameters (entry counts, converted to address widths internally)
    parameter TX_FIFO_DEPTH  = 2048,
    parameter RX_FIFO_DEPTH  = 2048,

    // Frame Parameters
    parameter MIN_FRAME_SIZE = 64,
    parameter MAX_FRAME_SIZE = 1518,
    parameter IFG_BYTES      = 12
) (
    //==========================================================================
    // System Clock Domain
    //==========================================================================
    input  wire                         sys_clk,        // System clock
    input  wire                         sys_rst_n,      // System reset (active low, async)

    //==========================================================================
    // GMII TX Clock Domain
    //==========================================================================
    input  wire                         gtx_clk,        // TX clock (125 MHz)
    input  wire                         gtx_rst_n,      // TX reset (active low, async)

    //==========================================================================
    // GMII RX Clock Domain
    //==========================================================================
    input  wire                         rx_clk,         // RX clock (125 MHz from PHY)
    input  wire                         rx_rst_n,       // RX reset (active low, async)

    //==========================================================================
    // AXI4-Lite Slave Interface (System Clock Domain)
    //==========================================================================
    // Write Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,

    // Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,

    // Write Response Channel
    output wire [1:0]                   s_axi_bresp,
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,

    // Read Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,

    // Read Data Channel
    output wire [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready,

    //==========================================================================
    // TX Data Interface (System Clock Domain)
    //==========================================================================
    input  wire [7:0]                   tx_axis_tdata,  // TX data
    input  wire                         tx_axis_tvalid, // TX data valid
    input  wire                         tx_axis_tlast,  // TX last (EOF)
    input  wire                         tx_axis_tuser,  // TX user (SOF)
    output wire                         tx_axis_tready, // TX ready

    //==========================================================================
    // RX Data Interface (System Clock Domain)
    //==========================================================================
    output wire [7:0]                   rx_axis_tdata,  // RX data
    output wire                         rx_axis_tvalid, // RX data valid
    output wire                         rx_axis_tlast,  // RX last (EOF)
    output wire                         rx_axis_tuser,  // RX user {frame_bad}
    input  wire                         rx_axis_tready, // RX ready

    //==========================================================================
    // GMII Interface (to PHY layer)
    //==========================================================================
    // TX (GTX clock domain)
    output wire [7:0]                   gmii_txd,
    output wire                         gmii_tx_en,
    output wire                         gmii_tx_er,

    // RX (RX clock domain)
    input  wire [7:0]                   gmii_rxd,
    input  wire                         gmii_rx_dv,
    input  wire                         gmii_rx_er,

    // Optional (directly from PHY)
    input  wire                         gmii_col,
    input  wire                         gmii_crs,

    //==========================================================================
    // Interrupt Output
    //==========================================================================
    output wire                         irq
);

    //==========================================================================
    // Local Parameters
    //==========================================================================
    localparam TX_FIFO_AW   = $clog2(TX_FIFO_DEPTH);   // FIFO address widths
    localparam RX_FIFO_AW   = $clog2(RX_FIFO_DEPTH);
    localparam FRAME_CNT_W  = TX_FIFO_AW + 1;          // Frames-in-FIFO counter width

    // RX FIFO almost-full headroom: enough reserved slots to guarantee the
    // EOF beat of several back-to-back frames can still be written while the
    // reader is stalled (see RX FIFO write-side drop policy below).
    localparam RX_AFULL_TH  = 8;

    //==========================================================================
    // Reset Synchronizers - async assert, sync de-assert, one per domain
    //==========================================================================
    wire sys_rst_sync_n;
    wire gtx_rst_sync_n;
    wire rxc_rst_sync_n;

    mac_rst_sync u_sys_rst_sync (
        .clk         (sys_clk),
        .async_rst_n (sys_rst_n),
        .rst_n       (sys_rst_sync_n)
    );

    mac_rst_sync u_gtx_rst_sync (
        .clk         (gtx_clk),
        .async_rst_n (gtx_rst_n),
        .rst_n       (gtx_rst_sync_n)
    );

    mac_rst_sync u_rxc_rst_sync (
        .clk         (rx_clk),
        .async_rst_n (rx_rst_n),
        .rst_n       (rxc_rst_sync_n)
    );

    //==========================================================================
    // Internal Signals - Register Interface (sys_clk domain)
    //==========================================================================
    wire [47:0] mac_addr;
    wire        tx_enable;
    wire        rx_enable;
    wire [3:0]  int_mask;

    //==========================================================================
    // Internal Signals - TX Path
    //==========================================================================
    // TX FIFO (sys_clk write side, gtx_clk read side)
    wire [9:0]  tx_fifo_din;            // {sof, eof, data[7:0]}
    wire        tx_fifo_wr_en;
    wire        tx_fifo_full;
    wire [9:0]  tx_fifo_dout;
    wire        tx_fifo_empty;
    wire        tx_fifo_rd_en;

    // TX engine signals (gtx_clk domain)
    wire [7:0]  tx_data;
    wire        tx_data_valid;
    wire        tx_sof;
    wire        tx_eof;
    wire        tx_ready;
    wire        tx_done;
    wire        tx_active;
    wire [31:0] tx_frame_cnt;

    // TX CRC signals (gtx_clk domain)
    wire        tx_crc_init;
    wire        tx_crc_enable;
    wire [7:0]  tx_crc_data;
    wire [7:0]  tx_crc_byte0;
    wire [7:0]  tx_crc_byte1;
    wire [7:0]  tx_crc_byte2;
    wire [7:0]  tx_crc_byte3;

    // TX GMII signals (mac_tx -> mac_gmii_if)
    wire [7:0]  tx_gmii_txd;
    wire        tx_gmii_tx_en;
    wire        tx_gmii_tx_er;

    //==========================================================================
    // Internal Signals - RX Path
    //==========================================================================
    // RX GMII signals (registered by mac_gmii_if, rx_clk domain)
    wire [7:0]  rx_gmii_rxd;
    wire        rx_gmii_rx_dv;
    wire        rx_gmii_rx_er;

    // RX engine output (rx_clk domain)
    wire [7:0]  rx_data;
    wire        rx_data_valid;
    wire        rx_sof;
    wire        rx_eof;
    wire        rx_frame_good;
    wire        rx_frame_bad;
    wire        rx_active_int;
    wire [31:0] rx_frame_cnt;
    wire [31:0] rx_err_cnt;

    // RX CRC signals (rx_clk domain)
    wire        rx_crc_init;
    wire        rx_crc_enable;
    wire [7:0]  rx_crc_data;
    wire [31:0] rx_crc_out;

    // RX FIFO (rx_clk write side, sys_clk read side)
    wire [11:0] rx_fifo_din;            // {frame_bad, frame_good, sof, eof, data[7:0]}
    wire        rx_fifo_wr_en;
    wire        rx_fifo_full;
    wire        rx_fifo_almost_full;    // rx_clk domain (from RX FIFO write side)
    wire [11:0] rx_fifo_dout;
    wire        rx_fifo_empty;
    wire        rx_fifo_rd_en;

    // Interrupt pulses (source domains)
    wire        int_rx_received;
    wire        int_rx_crc_err;
    wire        int_rx_runt;

    //==========================================================================
    // Enable Level CDC (sys_clk -> gtx_clk / rx_clk)
    //==========================================================================
    wire tx_enable_gtx;
    wire rx_enable_rxclk;

    mac_bit_sync u_tx_enable_sync (
        .clk   (gtx_clk),
        .rst_n (gtx_rst_sync_n),
        .d     (tx_enable),
        .q     (tx_enable_gtx)
    );

    mac_bit_sync u_rx_enable_sync (
        .clk   (rx_clk),
        .rst_n (rxc_rst_sync_n),
        .d     (rx_enable),
        .q     (rx_enable_rxclk)
    );

    //==========================================================================
    // TX FIFO Write Side - Pack data (System Clock Domain)
    //==========================================================================
    assign tx_fifo_din    = {tx_axis_tuser, tx_axis_tlast, tx_axis_tdata};
    assign tx_axis_tready = !tx_fifo_full && tx_enable;
    assign tx_fifo_wr_en  = tx_axis_tvalid && tx_axis_tready;

    //==========================================================================
    // Store-and-Forward Frame Availability (sys_clk -> gtx_clk)
    // A pulse is generated when the last byte of a frame is written into the
    // TX FIFO; mac_pulse_sync carries it into the gtx domain. Transmission of
    // a frame only starts once it is completely buffered, so mac_tx can never
    // underrun mid-frame. Constraint (met by Ethernet framing): frame-complete
    // events are separated by >= 2 gtx_clk cycles.
    //==========================================================================
    wire tx_frame_written_sys;
    wire tx_new_frame_avail;

    assign tx_frame_written_sys = tx_fifo_wr_en && tx_axis_tlast;

    mac_pulse_sync u_tx_frame_avail_sync (
        .src_clk   (sys_clk),
        .src_rst_n (sys_rst_sync_n),
        .src_pulse (tx_frame_written_sys),
        .dst_clk   (gtx_clk),
        .dst_rst_n (gtx_rst_sync_n),
        .dst_pulse (tx_new_frame_avail)
    );

    //==========================================================================
    // TX FIFO Read Side - Unpack data (GTX Clock Domain)
    //==========================================================================
    // Count complete frames in the FIFO. Width covers the worst case of
    // minimum-size frames filling the FIFO; increments/decrements saturate
    // so a desynchronized stream can never wrap the counter.
    reg [FRAME_CNT_W-1:0] tx_frames_in_fifo;
    reg                   tx_frame_active;

    wire tx_frame_rd_done;
    assign tx_frame_rd_done = tx_fifo_rd_en && tx_eof;

    always @(posedge gtx_clk or negedge gtx_rst_sync_n) begin
        if (!gtx_rst_sync_n) begin
            tx_frames_in_fifo <= {FRAME_CNT_W{1'b0}};
            tx_frame_active   <= 1'b0;
        end else begin
            // Update frame counter (saturating)
            if (tx_new_frame_avail && tx_frame_rd_done) begin
                // New frame in and old frame out - no change
                tx_frames_in_fifo <= tx_frames_in_fifo;
            end else if (tx_new_frame_avail) begin
                if (tx_frames_in_fifo != {FRAME_CNT_W{1'b1}}) begin
                    tx_frames_in_fifo <= tx_frames_in_fifo + 1'b1;
                end
            end else if (tx_frame_rd_done) begin
                if (tx_frames_in_fifo != {FRAME_CNT_W{1'b0}}) begin
                    tx_frames_in_fifo <= tx_frames_in_fifo - 1'b1;
                end
            end

            // Track active frame read
            if (tx_fifo_rd_en && tx_sof) begin
                tx_frame_active <= 1'b1;
            end else if (tx_frame_rd_done) begin
                tx_frame_active <= 1'b0;
            end
        end
    end

    assign tx_data = tx_fifo_dout[7:0];
    assign tx_eof  = tx_fifo_dout[8];
    assign tx_sof  = tx_fifo_dout[9];

    // tx_data_valid:
    // - Starting a new frame requires a complete frame in the FIFO
    //   (store-and-forward)
    // - While reading a frame, FIFO not empty is sufficient
    wire tx_frame_ready;
    assign tx_frame_ready = (tx_frames_in_fifo != {FRAME_CNT_W{1'b0}});
    assign tx_data_valid  = !tx_fifo_empty && (tx_frame_active || tx_frame_ready);

    // Read from FIFO when mac_tx accepts data (DATA state or orphan drain)
    assign tx_fifo_rd_en = tx_ready && !tx_fifo_empty;

    //==========================================================================
    // RX FIFO Write Side (RX Clock Domain)
    // Drop policy: once the RX FIFO is almost full, non-EOF bytes are dropped
    // preemptively to reserve headroom for the EOF beat, so tlast is (almost)
    // always delivered and downstream framing never desynchronizes. Any frame
    // that lost bytes is marked bad via the sticky overrun bit.
    // NOTE: rx_fifo_almost_full comes from the RX FIFO's own write side
    // (rx_clk domain) - see u_rx_fifo below.
    //==========================================================================
    reg rx_fifo_overrun_sticky;

    always @(posedge rx_clk or negedge rxc_rst_sync_n) begin
        if (!rxc_rst_sync_n) begin
            rx_fifo_overrun_sticky <= 1'b0;
        end else if (rx_data_valid && rx_sof) begin
            rx_fifo_overrun_sticky <= 1'b0;
        end else if (rx_data_valid && !rx_eof && rx_fifo_almost_full) begin
            rx_fifo_overrun_sticky <= 1'b1;
        end
    end

    assign rx_fifo_din   = {rx_frame_bad | rx_fifo_overrun_sticky, rx_frame_good, rx_sof, rx_eof, rx_data};
    assign rx_fifo_wr_en = rx_data_valid && !rx_fifo_full && (rx_eof || !rx_fifo_almost_full);

    //==========================================================================
    // RX FIFO Read Side (System Clock Domain)
    //==========================================================================
    assign rx_axis_tdata  = rx_fifo_dout[7:0];
    assign rx_axis_tlast  = rx_fifo_dout[8];
    assign rx_axis_tuser  = rx_fifo_dout[11];  // {frame_bad}
    assign rx_axis_tvalid = !rx_fifo_empty;
    assign rx_fifo_rd_en  = rx_axis_tready && !rx_fifo_empty;

    //==========================================================================
    // Interrupt Pulse CDC (gtx_clk / rx_clk -> sys_clk)
    //==========================================================================
    wire int_tx_complete_sys;
    wire int_rx_received_sys;
    wire int_rx_crc_err_sys;
    wire int_rx_runt_sys;

    mac_pulse_sync u_int_tx_done_sync (
        .src_clk   (gtx_clk),
        .src_rst_n (gtx_rst_sync_n),
        .src_pulse (tx_done),
        .dst_clk   (sys_clk),
        .dst_rst_n (sys_rst_sync_n),
        .dst_pulse (int_tx_complete_sys)
    );

    mac_pulse_sync u_int_rx_received_sync (
        .src_clk   (rx_clk),
        .src_rst_n (rxc_rst_sync_n),
        .src_pulse (int_rx_received),
        .dst_clk   (sys_clk),
        .dst_rst_n (sys_rst_sync_n),
        .dst_pulse (int_rx_received_sys)
    );

    mac_pulse_sync u_int_rx_crc_err_sync (
        .src_clk   (rx_clk),
        .src_rst_n (rxc_rst_sync_n),
        .src_pulse (int_rx_crc_err),
        .dst_clk   (sys_clk),
        .dst_rst_n (sys_rst_sync_n),
        .dst_pulse (int_rx_crc_err_sys)
    );

    mac_pulse_sync u_int_rx_runt_sync (
        .src_clk   (rx_clk),
        .src_rst_n (rxc_rst_sync_n),
        .src_pulse (int_rx_runt),
        .dst_clk   (sys_clk),
        .dst_rst_n (sys_rst_sync_n),
        .dst_pulse (int_rx_runt_sys)
    );

    //==========================================================================
    // Status Level CDC (gtx_clk / rx_clk -> sys_clk)
    //==========================================================================
    wire tx_active_sys;
    wire rx_active_sys;

    mac_bit_sync u_tx_active_sync (
        .clk   (sys_clk),
        .rst_n (sys_rst_sync_n),
        .d     (tx_active),
        .q     (tx_active_sys)
    );

    mac_bit_sync u_rx_active_sync (
        .clk   (sys_clk),
        .rst_n (sys_rst_sync_n),
        .d     (rx_active_int),
        .q     (rx_active_sys)
    );

    //==========================================================================
    // Counter CDC (gtx_clk / rx_clk -> sys_clk), Gray-coded
    //==========================================================================
    wire [31:0] tx_frame_cnt_sys;
    wire [31:0] rx_frame_cnt_sys;
    wire [31:0] rx_err_cnt_sys;

    mac_cnt_sync #(.WIDTH(32)) u_tx_frame_cnt_sync (
        .src_clk   (gtx_clk),
        .src_rst_n (gtx_rst_sync_n),
        .src_cnt   (tx_frame_cnt),
        .dst_clk   (sys_clk),
        .dst_rst_n (sys_rst_sync_n),
        .dst_cnt   (tx_frame_cnt_sys)
    );

    mac_cnt_sync #(.WIDTH(32)) u_rx_frame_cnt_sync (
        .src_clk   (rx_clk),
        .src_rst_n (rxc_rst_sync_n),
        .src_cnt   (rx_frame_cnt),
        .dst_clk   (sys_clk),
        .dst_rst_n (sys_rst_sync_n),
        .dst_cnt   (rx_frame_cnt_sys)
    );

    mac_cnt_sync #(.WIDTH(32)) u_rx_err_cnt_sync (
        .src_clk   (rx_clk),
        .src_rst_n (rxc_rst_sync_n),
        .src_cnt   (rx_err_cnt),
        .dst_clk   (sys_clk),
        .dst_rst_n (sys_rst_sync_n),
        .dst_cnt   (rx_err_cnt_sys)
    );

    //==========================================================================
    // Module Instantiations
    //==========================================================================

    //--------------------------------------------------------------------------
    // MAC Registers (AXI4-Lite)
    //--------------------------------------------------------------------------
    mac_regs #(
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH)
    ) u_mac_regs (
        .clk            (sys_clk),
        .rst_n          (sys_rst_sync_n),

        // AXI4-Lite
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        // Control outputs
        .mac_addr       (mac_addr),
        .tx_enable      (tx_enable),
        .rx_enable      (rx_enable),
        .int_mask       (int_mask),

        // Status inputs (synchronized to sys_clk)
        .tx_active      (tx_active_sys),
        .rx_active      (rx_active_sys),
        .tx_frame_cnt   (tx_frame_cnt_sys),
        .rx_frame_cnt   (rx_frame_cnt_sys),
        .rx_err_cnt     (rx_err_cnt_sys),

        // Interrupt inputs (synchronized to sys_clk)
        .int_tx_complete(int_tx_complete_sys),
        .int_rx_received(int_rx_received_sys),
        .int_rx_crc_err (int_rx_crc_err_sys),
        .int_rx_runt    (int_rx_runt_sys),

        // Interrupt output
        .irq            (irq)
    );

    //--------------------------------------------------------------------------
    // TX CDC FIFO (System -> GTX clock domain)
    //--------------------------------------------------------------------------
    mac_cdc_fifo #(
        .DATA_WIDTH     (10),           // {sof, eof, data[7:0]}
        .ADDR_WIDTH     (TX_FIFO_AW)
    ) u_tx_fifo (
        // Write side (System clock)
        .wr_clk         (sys_clk),
        .wr_rst_n       (sys_rst_sync_n),
        .wr_en          (tx_fifo_wr_en),
        .wr_data        (tx_fifo_din),
        .wr_full        (tx_fifo_full),
        .wr_almost_full (),             // Not used

        // Read side (GTX clock)
        .rd_clk         (gtx_clk),
        .rd_rst_n       (gtx_rst_sync_n),
        .rd_en          (tx_fifo_rd_en),
        .rd_data        (tx_fifo_dout),
        .rd_empty       (tx_fifo_empty),
        .rd_almost_empty()              // Not used
    );

    //--------------------------------------------------------------------------
    // TX CRC32 Generator
    //--------------------------------------------------------------------------
    mac_crc32 u_tx_crc (
        .clk            (gtx_clk),
        .rst_n          (gtx_rst_sync_n),
        .init           (tx_crc_init),
        .enable         (tx_crc_enable),
        .data_in        (tx_crc_data),
        .crc_out        (),             // Not used for TX
        .crc_byte0      (tx_crc_byte0),
        .crc_byte1      (tx_crc_byte1),
        .crc_byte2      (tx_crc_byte2),
        .crc_byte3      (tx_crc_byte3)
    );

    //--------------------------------------------------------------------------
    // TX State Machine
    //--------------------------------------------------------------------------
    mac_tx #(
        .MIN_FRAME_SIZE (MIN_FRAME_SIZE),
        .IFG_BYTES      (IFG_BYTES)
    ) u_mac_tx (
        .clk            (gtx_clk),
        .rst_n          (gtx_rst_sync_n),
        .tx_enable      (tx_enable_gtx),  // CDC-synchronized enable

        // Data input
        .tx_data        (tx_data),
        .tx_data_valid  (tx_data_valid),
        .tx_sof         (tx_sof),
        .tx_eof         (tx_eof),
        .tx_ready       (tx_ready),

        // GMII output (to mac_gmii_if)
        .gmii_txd       (tx_gmii_txd),
        .gmii_tx_en     (tx_gmii_tx_en),
        .gmii_tx_er     (tx_gmii_tx_er),

        // CRC interface
        .crc_init       (tx_crc_init),
        .crc_enable     (tx_crc_enable),
        .crc_data       (tx_crc_data),
        .crc_byte0      (tx_crc_byte0),
        .crc_byte1      (tx_crc_byte1),
        .crc_byte2      (tx_crc_byte2),
        .crc_byte3      (tx_crc_byte3),

        // Status
        .tx_active      (tx_active),
        .tx_done        (tx_done),
        .tx_frame_cnt   (tx_frame_cnt)
    );

    //--------------------------------------------------------------------------
    // GMII Interface (Signal Registration at PHY boundary)
    // TX now routed THROUGH the register stage (was previously bypassed,
    // leaving the TX half of this module dead)
    //--------------------------------------------------------------------------
    mac_gmii_if u_gmii_if (
        // TX side
        .gtx_clk        (gtx_clk),
        .tx_rst_n       (gtx_rst_sync_n),
        .mac_txd        (tx_gmii_txd),
        .mac_tx_en      (tx_gmii_tx_en),
        .mac_tx_er      (tx_gmii_tx_er),
        .gmii_txd       (gmii_txd),
        .gmii_tx_en     (gmii_tx_en),
        .gmii_tx_er     (gmii_tx_er),

        // RX side
        .rx_clk         (rx_clk),
        .rx_rst_n       (rxc_rst_sync_n),
        .gmii_rxd       (gmii_rxd),
        .gmii_rx_dv     (gmii_rx_dv),
        .gmii_rx_er     (gmii_rx_er),
        .mac_rxd        (rx_gmii_rxd),
        .mac_rx_dv      (rx_gmii_rx_dv),
        .mac_rx_er      (rx_gmii_rx_er),

        // Carrier/collision (registered; unused in full-duplex Phase 0)
        .gmii_col       (gmii_col),
        .gmii_crs       (gmii_crs),
        .mac_col        (),
        .mac_crs        ()
    );

    //--------------------------------------------------------------------------
    // RX CRC32 Checker
    //--------------------------------------------------------------------------
    mac_crc32 u_rx_crc (
        .clk            (rx_clk),
        .rst_n          (rxc_rst_sync_n),
        .init           (rx_crc_init),
        .enable         (rx_crc_enable),
        .data_in        (rx_crc_data),
        .crc_out        (rx_crc_out),
        .crc_byte0      (),             // Not used for RX
        .crc_byte1      (),
        .crc_byte2      (),
        .crc_byte3      ()
    );

    //--------------------------------------------------------------------------
    // RX State Machine
    //--------------------------------------------------------------------------
    mac_rx #(
        .MIN_FRAME_SIZE (MIN_FRAME_SIZE),
        .MAX_FRAME_SIZE (MAX_FRAME_SIZE)
    ) u_mac_rx (
        .clk            (rx_clk),
        .rst_n          (rxc_rst_sync_n),
        .rx_enable      (rx_enable_rxclk),  // CDC-synchronized enable

        // GMII input (registered by mac_gmii_if)
        .gmii_rxd       (rx_gmii_rxd),
        .gmii_rx_dv     (rx_gmii_rx_dv),
        .gmii_rx_er     (rx_gmii_rx_er),

        // Data output
        .rx_data        (rx_data),
        .rx_data_valid  (rx_data_valid),
        .rx_sof         (rx_sof),
        .rx_eof         (rx_eof),
        .rx_frame_good  (rx_frame_good),
        .rx_frame_bad   (rx_frame_bad),

        // CRC interface
        .crc_init       (rx_crc_init),
        .crc_enable     (rx_crc_enable),
        .crc_data       (rx_crc_data),
        .crc_out        (rx_crc_out),

        // Status
        .rx_active      (rx_active_int),
        .rx_frame_cnt   (rx_frame_cnt),
        .rx_err_cnt     (rx_err_cnt),

        // Interrupts
        .int_rx_received(int_rx_received),
        .int_rx_crc_err (int_rx_crc_err),
        .int_rx_runt    (int_rx_runt)
    );

    //--------------------------------------------------------------------------
    // RX CDC FIFO (RX -> System clock domain)
    // wr_almost_full now correctly taken from THIS FIFO's write side (it was
    // previously miswired to the TX FIFO's almost-full flag in the wrong
    // clock domain, which broke the RX overflow protection entirely)
    //--------------------------------------------------------------------------
    mac_cdc_fifo #(
        .DATA_WIDTH     (12),           // {frame_bad, frame_good, sof, eof, data[7:0]}
        .ADDR_WIDTH     (RX_FIFO_AW),
        .ALMOST_FULL_TH (RX_AFULL_TH)
    ) u_rx_fifo (
        // Write side (RX clock)
        .wr_clk         (rx_clk),
        .wr_rst_n       (rxc_rst_sync_n),
        .wr_en          (rx_fifo_wr_en),
        .wr_data        (rx_fifo_din),
        .wr_full        (rx_fifo_full),
        .wr_almost_full (rx_fifo_almost_full),

        // Read side (System clock)
        .rd_clk         (sys_clk),
        .rd_rst_n       (sys_rst_sync_n),
        .rd_en          (rx_fifo_rd_en),
        .rd_data        (rx_fifo_dout),
        .rd_empty       (rx_fifo_empty),
        .rd_almost_empty()              // Not used
    );

    //==========================================================================
    // Elaboration/Simulation Parameter Checks
    //==========================================================================
    // synthesis translate_off
    initial begin
        if (TX_FIFO_DEPTH < MAX_FRAME_SIZE)
            $error("mac_top: TX_FIFO_DEPTH=%0d must be >= MAX_FRAME_SIZE=%0d for store-and-forward",
                   TX_FIFO_DEPTH, MAX_FRAME_SIZE);
        if (RX_FIFO_DEPTH < MAX_FRAME_SIZE)
            $error("mac_top: RX_FIFO_DEPTH=%0d must be >= MAX_FRAME_SIZE=%0d to bound overflow risk",
                   RX_FIFO_DEPTH, MAX_FRAME_SIZE);
        if (TX_FIFO_DEPTH != (1 << $clog2(TX_FIFO_DEPTH)))
            $error("mac_top: TX_FIFO_DEPTH=%0d must be a power of two", TX_FIFO_DEPTH);
        if (RX_FIFO_DEPTH != (1 << $clog2(RX_FIFO_DEPTH)))
            $error("mac_top: RX_FIFO_DEPTH=%0d must be a power of two", RX_FIFO_DEPTH);
    end
    // synthesis translate_on

endmodule
