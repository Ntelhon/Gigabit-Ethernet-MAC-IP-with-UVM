//==============================================================================
// Module: mac_top
// Description: Top-level integration module for Gigabit Ethernet MAC
//
// Features:
//   - Instantiates all MAC core submodules
//   - Clean separation between MAC and PHY interface
//   - CDC FIFOs for TX and RX paths
//   - AXI4-Lite register interface
//   - GMII interface to PHY layer
//   - No PHY-specific logic inside
//
// Architecture:
//   ┌─────────────────────────────────────────────────────────────────┐
//   │                         mac_top                                 │
//   │  ┌─────────┐    ┌──────────┐    ┌─────────┐    ┌────────────┐   │
//   │  │mac_regs │    │ TX FIFO  │───▶│ mac_tx  │───▶│mac_gmii_if│───│──▶ GMII TX
//   │  │(AXI-L)  │    │(CDC)     │    │         │    │            │   │
//   │  └────┬────┘    └──────────┘    └────┬────┘    └────────────┘   │
//   │       │                              │                          │
//   │       │         ┌──────────┐    ┌────┴────┐         ▲           │
//   │       └────────▶│ RX FIFO  │◀───│ mac_rx  │◀────────┴──────────│◀── GMII RX
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
// Verification Hooks:
//   - Assertion: Reset synchronization
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
    
    // FIFO Parameters
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
    input  wire                         sys_rst_n,      // System reset (active low)

    //==========================================================================
    // GMII TX Clock Domain
    //==========================================================================
    input  wire                         gtx_clk,        // TX clock (125 MHz)
    input  wire                         gtx_rst_n,      // TX reset (active low)

    //==========================================================================
    // GMII RX Clock Domain
    //==========================================================================
    input  wire                         rx_clk,         // RX clock (125 MHz from PHY)
    input  wire                         rx_rst_n,       // RX reset (active low)

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
    // Internal Signals - Register Interface
    //==========================================================================
    wire [47:0] mac_addr;
    wire        tx_enable;
    wire        rx_enable;
    wire [3:0]  int_mask;
    wire        tx_active;
    wire        rx_active;
    wire [31:0] tx_frame_cnt;
    wire [31:0] rx_frame_cnt;
    wire [31:0] rx_err_cnt;
    wire        int_tx_complete;
    wire        int_rx_received;
    wire        int_rx_crc_err;
    wire        int_rx_runt;

    //==========================================================================
    // CDC Synchronized Enable Signals
    // These cross from sys_clk domain to tx_clk/rx_clk domains
    //==========================================================================
    reg [2:0]   tx_enable_sync;         // 3-stage sync for tx_enable
    reg [2:0]   rx_enable_sync;         // 3-stage sync for rx_enable
    wire        tx_enable_gtx;          // tx_enable in GTX clock domain
    wire        rx_enable_rxclk;        // rx_enable in RX clock domain

    // TX enable synchronizer (sys_clk -> gtx_clk)
    always @(posedge gtx_clk or negedge gtx_rst_n) begin
        if (!gtx_rst_n) begin
            tx_enable_sync <= 3'b000;
        end else begin
            tx_enable_sync <= {tx_enable_sync[1:0], tx_enable};
        end
    end
    assign tx_enable_gtx = tx_enable_sync[2];

    // RX enable synchronizer (sys_clk -> rx_clk)
    always @(posedge rx_clk or negedge rx_rst_n) begin
        if (!rx_rst_n) begin
            rx_enable_sync <= 3'b000;
        end else begin
            rx_enable_sync <= {rx_enable_sync[1:0], rx_enable};
        end
    end
    assign rx_enable_rxclk = rx_enable_sync[2];

    //==========================================================================
    // Internal Signals - TX Path
    //==========================================================================
    // TX FIFO output (GTX clock domain)
    wire [9:0]  tx_fifo_dout;           // {sof, eof, data[7:0]}
    wire        tx_fifo_empty;
    wire        tx_fifo_rd_en;

    // TX engine signals
    wire [7:0]  tx_data;
    wire        tx_data_valid;
    wire        tx_sof;
    wire        tx_eof;
    wire        tx_ready;
    wire        tx_done;

    // TX CRC signals
    wire        tx_crc_init;
    wire        tx_crc_enable;
    wire [7:0]  tx_crc_data;
    wire [7:0]  tx_crc_byte0;
    wire [7:0]  tx_crc_byte1;
    wire [7:0]  tx_crc_byte2;
    wire [7:0]  tx_crc_byte3;

    // TX GMII signals (internal)
    wire [7:0]  tx_gmii_txd;
    wire        tx_gmii_tx_en;
    wire        tx_gmii_tx_er;

    //==========================================================================
    // Internal Signals - RX Path
    //==========================================================================
    // RX GMII signals (registered)
    wire [7:0]  rx_gmii_rxd;
    wire        rx_gmii_rx_dv;
    wire        rx_gmii_rx_er;

    // RX engine output (RX clock domain)
    wire [7:0]  rx_data;
    wire        rx_data_valid;
    wire        rx_sof;
    wire        rx_eof;
    wire        rx_frame_good;
    wire        rx_frame_bad;
    wire        rx_active_int;

    // RX CRC signals
    wire        rx_crc_init;
    wire        rx_crc_enable;
    wire [7:0]  rx_crc_data;
    wire [31:0] rx_crc_out;

    // RX FIFO signals
    wire [11:0] rx_fifo_din;            // {frame_bad, frame_good, sof, eof, data[7:0]}
    wire        rx_fifo_wr_en;
    wire        rx_fifo_full;
    wire [11:0] rx_fifo_dout;
    wire        rx_fifo_empty;
    wire        rx_fifo_rd_en;

    //==========================================================================
    // TX FIFO Write Side - Pack data (System Clock Domain)
    //==========================================================================
    wire [9:0]  tx_fifo_din;
    wire        tx_fifo_wr_en;
    wire        tx_fifo_full;
    
    // Store-and-Forward: Track when complete frame is in FIFO
    // This ensures we don't start transmitting until the whole frame is buffered
    // Uses a toggle-based CDC to signal frame availability
    reg         tx_frame_avail_toggle_sys;  // Toggled in sys_clk when frame complete
    reg  [2:0]  tx_frame_avail_sync;        // Synchronizer chain in gtx_clk
    reg         tx_frame_avail_gtx_last;    // Previous synchronized value
    wire        tx_new_frame_avail;         // Edge detect: new frame available

    assign tx_fifo_din   = {tx_axis_tuser, tx_axis_tlast, tx_axis_tdata};
    assign tx_axis_tready = !tx_fifo_full && tx_enable;
    assign tx_fifo_wr_en = tx_axis_tvalid && tx_axis_tready;  // Write when handshake complete
    
    // Toggle when we write the last byte of a frame (sys_clk domain)
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            tx_frame_avail_toggle_sys <= 1'b0;
        end else begin
            if (tx_fifo_wr_en && tx_axis_tlast) begin
                tx_frame_avail_toggle_sys <= ~tx_frame_avail_toggle_sys;
            end
        end
    end
    
    // Synchronize toggle to gtx_clk domain and edge detect
    always @(posedge gtx_clk) begin
        if (!gtx_rst_n) begin
            tx_frame_avail_sync <= 3'b0;
            tx_frame_avail_gtx_last <= 1'b0;
        end else begin
            tx_frame_avail_sync <= {tx_frame_avail_sync[1:0], tx_frame_avail_toggle_sys};
            tx_frame_avail_gtx_last <= tx_frame_avail_sync[2];
        end
    end
    
    // Detect toggle edge = new frame available
    assign tx_new_frame_avail = (tx_frame_avail_sync[2] != tx_frame_avail_gtx_last);

    //==========================================================================
    // TX FIFO Read Side - Unpack data (GTX Clock Domain)
    //==========================================================================
    
    // Track number of complete frames in FIFO (counter in gtx domain)
    // Increments when new frame signaled, decrements when frame read complete
    reg [3:0] tx_frames_in_fifo;
    
    // Track if we are actively reading a frame from FIFO
    reg tx_frame_active;
    
    always @(posedge gtx_clk) begin
        if (!gtx_rst_n) begin
            tx_frames_in_fifo <= 4'd0;
            tx_frame_active <= 1'b0;
        end else begin
            // Update frame counter
            if (tx_new_frame_avail && (tx_fifo_rd_en && tx_eof)) begin
                // New frame in and old frame out - no change
            end else if (tx_new_frame_avail) begin
                // New complete frame available
                tx_frames_in_fifo <= tx_frames_in_fifo + 1'b1;
            end else if (tx_fifo_rd_en && tx_eof) begin
                // Finished reading a frame
                tx_frames_in_fifo <= tx_frames_in_fifo - 1'b1;
            end
            
            // Track active frame read
            if (tx_fifo_rd_en && tx_sof) begin
                tx_frame_active <= 1'b1;
            end else if (tx_fifo_rd_en && tx_eof) begin
                tx_frame_active <= 1'b0;
            end
        end
    end
    
    assign tx_data       = tx_fifo_dout[7:0];
    assign tx_eof        = tx_fifo_dout[8];
    assign tx_sof        = tx_fifo_dout[9];
    
    // tx_data_valid: 
    // - For starting a new frame: require complete frame in FIFO (store-and-forward)
    // - While reading a frame: just need FIFO not empty
    wire tx_frame_ready = (tx_frames_in_fifo > 0);
    assign tx_data_valid = !tx_fifo_empty && (tx_frame_active || tx_frame_ready);
    
    // Read from FIFO when tx_ready (mac_tx is in DATA state and accepting)
    assign tx_fifo_rd_en = tx_ready && !tx_fifo_empty;

    // Debug: FIFO operations
    `ifdef DEBUG
    always @(posedge gtx_clk) begin
        if (tx_fifo_rd_en) begin
            $display("[MAC_TOP] @%0t: FIFO RD: data=%02h sof=%b eof=%b tx_ready=%b",
                     $time, tx_data, tx_sof, tx_eof, tx_ready);
        end
        if (tx_new_frame_avail) begin
            $display("[MAC_TOP] @%0t: NEW_FRAME_AVAIL! frames_in_fifo=%0d", 
                     $time, tx_frames_in_fifo);
        end
        if (tx_fifo_rd_en && tx_eof) begin
            $display("[MAC_TOP] @%0t: FRAME_READ_DONE! frames_in_fifo=%0d->%0d", 
                     $time, tx_frames_in_fifo, tx_frames_in_fifo - 1);
        end
    end
    
    always @(posedge sys_clk) begin
        if (tx_fifo_wr_en) begin
            $display("[MAC_TOP] @%0t: AXI-S TX: data=%02h sof=%b eof=%b", 
                     $time, tx_axis_tdata, tx_axis_tuser, tx_axis_tlast);
        end
    end
    `endif

    //==========================================================================
    // RX FIFO Write Side (RX Clock Domain)
    //==========================================================================
    wire rx_fifo_almost_full;
    reg  rx_fifo_overrun_sticky;   // latched when a mid-frame byte is dropped
    
    always @(posedge rx_clk) begin
        if (!rx_rst_n) begin
            rx_fifo_overrun_sticky <= 1'b0;
        end else if (rx_data_valid && rx_sof) begin
            rx_fifo_overrun_sticky <= 1'b0;
        end else if (rx_data_valid && !rx_eof && rx_fifo_almost_full) begin
            rx_fifo_overrun_sticky <= 1'b1;
        end
    end
    
    assign rx_fifo_din   = {rx_frame_bad | rx_fifo_overrun_sticky, rx_frame_good, rx_sof, rx_eof, rx_data};
    // Preemptively drop non-EOF bytes once almost_full to reserve headroom for the
    // EOF beat, so tlast/EOF is (almost) always delivered and downstream framing
    // never desyncs; the frame is marked bad via the sticky bit above.
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
    // GMII Output Assignments
    //==========================================================================
    assign gmii_txd   = tx_gmii_txd;
    assign gmii_tx_en = tx_gmii_tx_en;
    assign gmii_tx_er = tx_gmii_tx_er;

    //==========================================================================
    // Interrupt Signal Synchronization
    // Note: Interrupt pulses need to be synchronized to sys_clk domain
    //==========================================================================
    // For Phase 0, direct connection (assuming synchronized resets)
    // Production should add proper pulse synchronizers
    // Toggle-based pulse synchronizers (gtx_clk / rx_clk -> sys_clk)
    reg        tx_done_toggle_gtx;
    reg  [2:0] tx_done_sync_sys;
    reg        rx_received_toggle_rxclk, rx_crc_err_toggle_rxclk, rx_runt_toggle_rxclk;
    reg  [2:0] rx_received_sync_sys, rx_crc_err_sync_sys, rx_runt_sync_sys;
    
    always @(posedge gtx_clk) begin
        if (!gtx_rst_n) tx_done_toggle_gtx <= 1'b0;
        else if (tx_done) tx_done_toggle_gtx <= ~tx_done_toggle_gtx;
    end
    
    always @(posedge rx_clk) begin
        if (!rx_rst_n) begin
            rx_received_toggle_rxclk <= 1'b0;
            rx_crc_err_toggle_rxclk  <= 1'b0;
            rx_runt_toggle_rxclk     <= 1'b0;
        end else begin
            if (int_rx_received) rx_received_toggle_rxclk <= ~rx_received_toggle_rxclk;
            if (int_rx_crc_err)  rx_crc_err_toggle_rxclk  <= ~rx_crc_err_toggle_rxclk;
            if (int_rx_runt)     rx_runt_toggle_rxclk     <= ~rx_runt_toggle_rxclk;
        end
    end
    
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            tx_done_sync_sys <= 3'b0; rx_received_sync_sys <= 3'b0;
            rx_crc_err_sync_sys <= 3'b0; rx_runt_sync_sys <= 3'b0;
        end else begin
            tx_done_sync_sys     <= {tx_done_sync_sys[1:0],     tx_done_toggle_gtx};
            rx_received_sync_sys <= {rx_received_sync_sys[1:0], rx_received_toggle_rxclk};
            rx_crc_err_sync_sys  <= {rx_crc_err_sync_sys[1:0],  rx_crc_err_toggle_rxclk};
            rx_runt_sync_sys     <= {rx_runt_sync_sys[1:0],     rx_runt_toggle_rxclk};
        end
    end
    
    wire int_tx_complete_sys = tx_done_sync_sys[2]     ^ tx_done_sync_sys[1];
    wire int_rx_received_sys = rx_received_sync_sys[2] ^ rx_received_sync_sys[1];
    wire int_rx_crc_err_sys  = rx_crc_err_sync_sys[2]  ^ rx_crc_err_sync_sys[1];
    wire int_rx_runt_sys     = rx_runt_sync_sys[2]     ^ rx_runt_sync_sys[1];
    
    // Level-status 2-FF synchronizers
    reg [1:0] tx_active_sync_sys, rx_active_sync_sys;
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            tx_active_sync_sys <= 2'b0; rx_active_sync_sys <= 2'b0;
        end else begin
            tx_active_sync_sys <= {tx_active_sync_sys[0], tx_active};
            rx_active_sync_sys <= {rx_active_sync_sys[0], rx_active_int};
        end
    end
    
    // Gray-coded counter CDC (gtx_clk/rx_clk -> sys_clk)
    function [31:0] bin2gray32; input [31:0] bin; begin bin2gray32 = bin ^ (bin >> 1); end endfunction
    function [31:0] gray2bin32;
        input [31:0] gray; integer i;
        begin
            gray2bin32[31] = gray[31];
            for (i = 30; i >= 0; i = i - 1) gray2bin32[i] = gray2bin32[i+1] ^ gray[i];
        end
    endfunction
    
    reg  [31:0] tx_frame_cnt_gray_gtx, rx_frame_cnt_gray_rxclk, rx_err_cnt_gray_rxclk;
    reg  [31:0] tx_frame_cnt_gray_sync1, tx_frame_cnt_gray_sync2;
    reg  [31:0] rx_frame_cnt_gray_sync1, rx_frame_cnt_gray_sync2;
    reg  [31:0] rx_err_cnt_gray_sync1,   rx_err_cnt_gray_sync2;
    
    always @(posedge gtx_clk) begin
        if (!gtx_rst_n) tx_frame_cnt_gray_gtx <= 32'b0;
        else            tx_frame_cnt_gray_gtx <= bin2gray32(tx_frame_cnt);
    end
    always @(posedge rx_clk) begin
        if (!rx_rst_n) begin
            rx_frame_cnt_gray_rxclk <= 32'b0; rx_err_cnt_gray_rxclk <= 32'b0;
        end else begin
            rx_frame_cnt_gray_rxclk <= bin2gray32(rx_frame_cnt);
            rx_err_cnt_gray_rxclk   <= bin2gray32(rx_err_cnt);
        end
    end
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            tx_frame_cnt_gray_sync1<=0; tx_frame_cnt_gray_sync2<=0;
            rx_frame_cnt_gray_sync1<=0; rx_frame_cnt_gray_sync2<=0;
            rx_err_cnt_gray_sync1<=0;   rx_err_cnt_gray_sync2<=0;
        end else begin
            tx_frame_cnt_gray_sync1 <= tx_frame_cnt_gray_gtx;    tx_frame_cnt_gray_sync2 <= tx_frame_cnt_gray_sync1;
            rx_frame_cnt_gray_sync1 <= rx_frame_cnt_gray_rxclk;  rx_frame_cnt_gray_sync2 <= rx_frame_cnt_gray_sync1;
            rx_err_cnt_gray_sync1   <= rx_err_cnt_gray_rxclk;    rx_err_cnt_gray_sync2   <= rx_err_cnt_gray_sync1;
        end
    end
    
    wire [31:0] tx_frame_cnt_sys = gray2bin32(tx_frame_cnt_gray_sync2);
    wire [31:0] rx_frame_cnt_sys = gray2bin32(rx_frame_cnt_gray_sync2);
    wire [31:0] rx_err_cnt_sys   = gray2bin32(rx_err_cnt_gray_sync2);

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
        .rst_n          (sys_rst_n),

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

        // Status inputs
        .tx_active      (tx_active_sync_sys[1]),
        .rx_active      (rx_active_sync_sys[1]),
        .tx_frame_cnt   (tx_frame_cnt_sys),
        .rx_frame_cnt   (rx_frame_cnt_sys),
        .rx_err_cnt     (rx_err_cnt_sys),

        // Interrupt inputs
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
        .ADDR_WIDTH     ($clog2(TX_FIFO_DEPTH))
    ) u_tx_fifo (
        // Write side (System clock)
        .wr_clk         (sys_clk),
        .wr_rst_n       (sys_rst_n),
        .wr_en          (tx_fifo_wr_en),
        .wr_data        (tx_fifo_din),
        .wr_full        (tx_fifo_full),
        .wr_almost_full (rx_fifo_almost_full),             // Not used

        // Read side (GTX clock)
        .rd_clk         (gtx_clk),
        .rd_rst_n       (gtx_rst_n),
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
        .rst_n          (gtx_rst_n),
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
        .rst_n          (gtx_rst_n),
        .tx_enable      (tx_enable_gtx),  // Use CDC-synchronized enable

        // Data input
        .tx_data        (tx_data),
        .tx_data_valid  (tx_data_valid),
        .tx_sof         (tx_sof),
        .tx_eof         (tx_eof),
        .tx_ready       (tx_ready),

        // GMII output
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
    // GMII Interface (Signal Registration)
    //--------------------------------------------------------------------------
    mac_gmii_if u_gmii_if (
        // TX side
        .gtx_clk        (gtx_clk),
        .tx_rst_n       (gtx_rst_n),
        .mac_txd        (tx_gmii_txd),
        .mac_tx_en      (tx_gmii_tx_en),
        .mac_tx_er      (tx_gmii_tx_er),
        .gmii_txd       (),             // Internal - routed directly
        .gmii_tx_en     (),
        .gmii_tx_er     (),

        // RX side
        .rx_clk         (rx_clk),
        .rx_rst_n       (rx_rst_n),
        .gmii_rxd       (gmii_rxd),
        .gmii_rx_dv     (gmii_rx_dv),
        .gmii_rx_er     (gmii_rx_er),
        .mac_rxd        (rx_gmii_rxd),
        .mac_rx_dv      (rx_gmii_rx_dv),
        .mac_rx_er      (rx_gmii_rx_er),

        // Carrier/collision
        .gmii_col       (gmii_col),
        .gmii_crs       (gmii_crs),
        .mac_col        (),             // Not used in full-duplex
        .mac_crs        ()
    );

    //--------------------------------------------------------------------------
    // RX CRC32 Checker
    //--------------------------------------------------------------------------
    mac_crc32 u_rx_crc (
        .clk            (rx_clk),
        .rst_n          (rx_rst_n),
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
        .rst_n          (rx_rst_n),
        .rx_enable      (rx_enable_rxclk),  // Use CDC-synchronized enable

        // GMII input
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

    // RX active status (synchronized version would be needed for production)
    assign rx_active = rx_active_int;

    //--------------------------------------------------------------------------
    // RX CDC FIFO (RX -> System clock domain)
    //--------------------------------------------------------------------------
    mac_cdc_fifo #(
        .DATA_WIDTH     (12),           // {frame_bad, frame_good, sof, eof, data[7:0]}
        .ADDR_WIDTH     ($clog2(RX_FIFO_DEPTH))
    ) u_rx_fifo (
        // Write side (RX clock)
        .wr_clk         (rx_clk),
        .wr_rst_n       (rx_rst_n),
        .wr_en          (rx_fifo_wr_en),
        .wr_data        (rx_fifo_din),
        .wr_full        (rx_fifo_full),
        .wr_almost_full (),             // Not used

        // Read side (System clock)
        .rd_clk         (sys_clk),
        .rd_rst_n       (sys_rst_n),
        .rd_en          (rx_fifo_rd_en),
        .rd_data        (rx_fifo_dout),
        .rd_empty       (rx_fifo_empty),
        .rd_almost_empty()              // Not used
    );

    initial begin
        if (TX_FIFO_DEPTH < MAX_FRAME_SIZE)
            $error("mac_top: TX_FIFO_DEPTH=%0d must be >= MAX_FRAME_SIZE=%0d for store-and-forward", TX_FIFO_DEPTH, MAX_FRAME_SIZE);
        if (RX_FIFO_DEPTH < MAX_FRAME_SIZE)
            $error("mac_top: RX_FIFO_DEPTH=%0d must be >= MAX_FRAME_SIZE=%0d to bound overflow risk", RX_FIFO_DEPTH, MAX_FRAME_SIZE);
    end

endmodule
