//==============================================================================
// File: dma_axi_rd_arb.v
// Description: AXI4 Read-Channel Arbiter (N masters -> 1 port)
//
// Purpose:
//   Merges the AR/R channels of several internal read masters (descriptor
//   engines, TX data fetch) onto the single external AXI read port.
//
// Arbitration:
//   - Round-robin, TRANSACTION-LOCKED: the grant is held from AR acceptance
//     until the rlast beat of that burst is accepted. Exactly one read
//     transaction is outstanding at any time (simple and AXI-safe; future
//     enhancement: ID-based interleaving).
//   - The AR payload of the granted master is captured into registers and
//     replayed on the master port (registered AXI outputs).
//   - R beats are routed to the granted master; rdata/rresp/rlast/rid are
//     broadcast, rvalid is demuxed by the grant.
//
// Port packing (Verilog-2001): per-master fields are packed vectors indexed
// with [i*W +: W]; master i=0 occupies the least significant slice.
//
// Reset: asynchronous active-low rst_n.
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module dma_axi_rd_arb #(
    parameter N_MASTERS  = 3,       // Number of internal read masters
    parameter ADDR_WIDTH = 64,      // AXI address width
    parameter AXI_DATA_W = 64,      // AXI data width
    parameter AXI_ID_W   = 4        // AXI ID width
)(
    input  wire                              clk,
    input  wire                              rst_n,

    //--------------------------------------------------------------------------
    // Internal (slave-facing) side - packed per master
    //--------------------------------------------------------------------------
    input  wire [N_MASTERS-1:0]              s_arvalid,
    output wire [N_MASTERS-1:0]              s_arready,
    input  wire [N_MASTERS*ADDR_WIDTH-1:0]   s_araddr,
    input  wire [N_MASTERS*8-1:0]            s_arlen,
    input  wire [N_MASTERS*3-1:0]            s_arsize,
    input  wire [N_MASTERS*2-1:0]            s_arburst,
    input  wire [N_MASTERS*AXI_ID_W-1:0]     s_arid,

    output wire [N_MASTERS-1:0]              s_rvalid,
    input  wire [N_MASTERS-1:0]              s_rready,
    output wire [AXI_DATA_W-1:0]             s_rdata,     // Broadcast
    output wire [1:0]                        s_rresp,     // Broadcast
    output wire                              s_rlast,     // Broadcast
    output wire [AXI_ID_W-1:0]               s_rid,       // Broadcast

    //--------------------------------------------------------------------------
    // External (master) side
    //--------------------------------------------------------------------------
    output reg                               m_axi_arvalid,
    input  wire                              m_axi_arready,
    output reg  [ADDR_WIDTH-1:0]             m_axi_araddr,
    output reg  [7:0]                        m_axi_arlen,
    output reg  [2:0]                        m_axi_arsize,
    output reg  [1:0]                        m_axi_arburst,
    output reg  [AXI_ID_W-1:0]               m_axi_arid,

    input  wire                              m_axi_rvalid,
    output wire                              m_axi_rready,
    input  wire [AXI_DATA_W-1:0]             m_axi_rdata,
    input  wire [1:0]                        m_axi_rresp,
    input  wire                              m_axi_rlast,
    input  wire [AXI_ID_W-1:0]               m_axi_rid
);

    localparam PTR_W = (N_MASTERS <= 2) ? 1 :
                       (N_MASTERS <= 4) ? 2 :
                       (N_MASTERS <= 8) ? 3 : 4;

    //--------------------------------------------------------------------------
    // FSM states
    //--------------------------------------------------------------------------
    localparam [1:0] ARB_IDLE = 2'd0,   // Round-robin scan of s_arvalid
                     ARB_ADDR = 2'd1,   // Forward AR of granted master
                     ARB_DATA = 2'd2;   // Route R beats until rlast

    reg [1:0]       state;
    reg [PTR_W-1:0] grant;
    reg [PTR_W-1:0] last_grant;

    //--------------------------------------------------------------------------
    // Round-robin selection (closest requester after last_grant wins)
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
        gnext = rr_next(s_arvalid, {{(32-PTR_W){1'b0}}, last_grant});
    end

    //--------------------------------------------------------------------------
    // AR handshake with the granted internal master (accepted at grant time)
    //--------------------------------------------------------------------------
    assign s_arready = (state == ARB_IDLE && (|s_arvalid)) ?
                       ({{(N_MASTERS-1){1'b0}}, 1'b1} << gnext) :
                       {N_MASTERS{1'b0}};

    //--------------------------------------------------------------------------
    // FSM + AR payload capture
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ARB_IDLE;
            grant         <= {PTR_W{1'b0}};
            last_grant    <= {PTR_W{1'b0}};
            m_axi_arvalid <= 1'b0;
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen   <= 8'd0;
            m_axi_arsize  <= 3'd0;
            m_axi_arburst <= 2'd0;
            m_axi_arid    <= {AXI_ID_W{1'b0}};
        end else begin
            case (state)
                ARB_IDLE: begin
                    if (|s_arvalid) begin
                        grant         <= gnext;
                        m_axi_araddr  <= s_araddr [gnext*ADDR_WIDTH +: ADDR_WIDTH];
                        m_axi_arlen   <= s_arlen  [gnext*8          +: 8];
                        m_axi_arsize  <= s_arsize [gnext*3          +: 3];
                        m_axi_arburst <= s_arburst[gnext*2          +: 2];
                        m_axi_arid    <= s_arid   [gnext*AXI_ID_W   +: AXI_ID_W];
                        m_axi_arvalid <= 1'b1;
                        state         <= ARB_ADDR;
                    end
                end

                ARB_ADDR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state         <= ARB_DATA;
                    end
                end

                ARB_DATA: begin
                    if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
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
    // R channel routing (grant-locked, single outstanding => RID not needed)
    //--------------------------------------------------------------------------
    assign s_rvalid = (state == ARB_DATA && m_axi_rvalid) ?
                      ({{(N_MASTERS-1){1'b0}}, 1'b1} << grant) :
                      {N_MASTERS{1'b0}};

    assign m_axi_rready = (state == ARB_DATA) ? s_rready[grant] : 1'b0;

    assign s_rdata = m_axi_rdata;
    assign s_rresp = m_axi_rresp;
    assign s_rlast = m_axi_rlast;
    assign s_rid   = m_axi_rid;

endmodule
