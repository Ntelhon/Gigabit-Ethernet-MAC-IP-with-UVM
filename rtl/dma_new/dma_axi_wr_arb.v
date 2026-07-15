//==============================================================================
// File: dma_axi_wr_arb.v
// Description: AXI4 Write-Channel Arbiter (N masters -> 1 port)
//
// Purpose:
//   Merges the AW/W/B channels of several internal write masters (descriptor
//   writeback engines, RX data writer) onto the single external AXI write
//   port.
//
// Arbitration:
//   - Round-robin, TRANSACTION-LOCKED: the grant is held from AW acceptance
//     through the last W beat (wlast) AND the B response handshake.
//   - AW payload of the granted master is captured and replayed (registered).
//   - W beats are pass-through muxed from the granted master (standard
//     datapath muxing; adding a skid stage here is a timing-driven option).
//   - The B response is routed back to the granted master.
//
// Port packing: identical convention to dma_axi_rd_arb.
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_axi_wr_arb #(
    parameter N_MASTERS  = 3,       // Number of internal write masters
    parameter ADDR_WIDTH = 64,      // AXI address width
    parameter AXI_DATA_W = 64,      // AXI data width
    parameter AXI_ID_W   = 4        // AXI ID width
)(
    input  wire                              clk,
    input  wire                              rst_n,

    //--------------------------------------------------------------------------
    // Internal (slave-facing) side - packed per master
    //--------------------------------------------------------------------------
    input  wire [N_MASTERS-1:0]              s_awvalid,
    output wire [N_MASTERS-1:0]              s_awready,
    input  wire [N_MASTERS*ADDR_WIDTH-1:0]   s_awaddr,
    input  wire [N_MASTERS*8-1:0]            s_awlen,
    input  wire [N_MASTERS*3-1:0]            s_awsize,
    input  wire [N_MASTERS*2-1:0]            s_awburst,
    input  wire [N_MASTERS*AXI_ID_W-1:0]     s_awid,

    input  wire [N_MASTERS-1:0]              s_wvalid,
    output wire [N_MASTERS-1:0]              s_wready,
    input  wire [N_MASTERS*AXI_DATA_W-1:0]   s_wdata,
    input  wire [N_MASTERS*(AXI_DATA_W/8)-1:0] s_wstrb,
    input  wire [N_MASTERS-1:0]              s_wlast,

    output wire [N_MASTERS-1:0]              s_bvalid,
    input  wire [N_MASTERS-1:0]              s_bready,
    output wire [1:0]                        s_bresp,     // Broadcast
    output wire [AXI_ID_W-1:0]               s_bid,       // Broadcast

    //--------------------------------------------------------------------------
    // External (master) side
    //--------------------------------------------------------------------------
    output reg                               m_axi_awvalid,
    input  wire                              m_axi_awready,
    output reg  [ADDR_WIDTH-1:0]             m_axi_awaddr,
    output reg  [7:0]                        m_axi_awlen,
    output reg  [2:0]                        m_axi_awsize,
    output reg  [1:0]                        m_axi_awburst,
    output reg  [AXI_ID_W-1:0]               m_axi_awid,

    output wire                              m_axi_wvalid,
    input  wire                              m_axi_wready,
    output wire [AXI_DATA_W-1:0]             m_axi_wdata,
    output wire [AXI_DATA_W/8-1:0]           m_axi_wstrb,
    output wire                              m_axi_wlast,

    input  wire                              m_axi_bvalid,
    output wire                              m_axi_bready,
    input  wire [1:0]                        m_axi_bresp,
    input  wire [AXI_ID_W-1:0]               m_axi_bid
);

    localparam WSTRB_W = AXI_DATA_W / 8;
    localparam PTR_W   = (N_MASTERS <= 2) ? 1 :
                         (N_MASTERS <= 4) ? 2 :
                         (N_MASTERS <= 8) ? 3 : 4;

    //--------------------------------------------------------------------------
    // FSM states
    //--------------------------------------------------------------------------
    localparam [1:0] ARB_IDLE = 2'd0,   // Round-robin scan of s_awvalid
                     ARB_ADDR = 2'd1,   // Forward AW of granted master
                     ARB_DATA = 2'd2,   // Route W beats until wlast
                     ARB_RESP = 2'd3;   // Route B to granted master

    reg [1:0]       state;
    reg [PTR_W-1:0] grant;
    reg [PTR_W-1:0] last_grant;

    //--------------------------------------------------------------------------
    // Round-robin selection
    //--------------------------------------------------------------------------
    function integer rr_next;
        input [N_MASTERS-1:0] req;
        input integer         last;
        integer k, idx;
        begin
            rr_next = last;
            for (k = N_MASTERS; k >= 1; k = k - 1) begin
                idx = last + k;
                if (idx >= N_MASTERS) idx = idx - N_MASTERS;
                if (req[idx]) rr_next = idx;
            end
        end
    endfunction

    reg [PTR_W-1:0] gnext;
    always @(*) begin
        gnext = rr_next(s_awvalid, {{(32-PTR_W){1'b0}}, last_grant});
    end

    //--------------------------------------------------------------------------
    // AW handshake with the granted internal master
    //--------------------------------------------------------------------------
    assign s_awready = (state == ARB_IDLE && (|s_awvalid)) ?
                       ({{(N_MASTERS-1){1'b0}}, 1'b1} << gnext) :
                       {N_MASTERS{1'b0}};

    //--------------------------------------------------------------------------
    // FSM + AW payload capture
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ARB_IDLE;
            grant         <= {PTR_W{1'b0}};
            last_grant    <= {PTR_W{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_awsize  <= 3'd0;
            m_axi_awburst <= 2'd0;
            m_axi_awid    <= {AXI_ID_W{1'b0}};
        end else begin
            case (state)
                ARB_IDLE: begin
                    if (|s_awvalid) begin
                        grant         <= gnext;
                        m_axi_awaddr  <= s_awaddr [gnext*ADDR_WIDTH +: ADDR_WIDTH];
                        m_axi_awlen   <= s_awlen  [gnext*8          +: 8];
                        m_axi_awsize  <= s_awsize [gnext*3          +: 3];
                        m_axi_awburst <= s_awburst[gnext*2          +: 2];
                        m_axi_awid    <= s_awid   [gnext*AXI_ID_W   +: AXI_ID_W];
                        m_axi_awvalid <= 1'b1;
                        state         <= ARB_ADDR;
                    end
                end

                ARB_ADDR: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        state         <= ARB_DATA;
                    end
                end

                ARB_DATA: begin
                    if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                        state <= ARB_RESP;
                    end
                end

                ARB_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        last_grant <= grant;
                        state      <= ARB_IDLE;
                    end
                end

                default: begin
                    state <= ARB_IDLE;
                end
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // W channel pass-through mux (grant-locked)
    //--------------------------------------------------------------------------
    assign m_axi_wvalid = (state == ARB_DATA) ? s_wvalid[grant] : 1'b0;
    assign m_axi_wdata  = s_wdata[grant*AXI_DATA_W +: AXI_DATA_W];
    assign m_axi_wstrb  = s_wstrb[grant*WSTRB_W    +: WSTRB_W];
    assign m_axi_wlast  = s_wlast[grant];

    assign s_wready = (state == ARB_DATA && m_axi_wready) ?
                      ({{(N_MASTERS-1){1'b0}}, 1'b1} << grant) :
                      {N_MASTERS{1'b0}};

    //--------------------------------------------------------------------------
    // B channel routing
    //--------------------------------------------------------------------------
    assign s_bvalid = (state == ARB_RESP && m_axi_bvalid) ?
                      ({{(N_MASTERS-1){1'b0}}, 1'b1} << grant) :
                      {N_MASTERS{1'b0}};

    assign m_axi_bready = (state == ARB_RESP) ? s_bready[grant] : 1'b0;

    assign s_bresp = m_axi_bresp;
    assign s_bid   = m_axi_bid;

endmodule
