//==============================================================================
// Module: mac_gmii_if
// Description: GMII signal registration at the PHY boundary
//              (one function: I/O signal registration)
//
// Features:
//   - Clean GMII signal grouping
//   - Signal registration for timing closure at the pad boundary
//   - No PHY-specific behavior, technology independent
//
// GMII Specification (IEEE 802.3):
//   - TX: 8-bit data, TX_EN, TX_ER, GTX_CLK (125 MHz from MAC)
//   - RX: 8-bit data, RX_DV, RX_ER, RX_CLK (125 MHz from PHY)
//
// Clock Domains:
//   - TX: gtx_clk (MAC-generated 125 MHz)
//   - RX: rx_clk (PHY-generated 125 MHz)
//
// Note: mac_top routes the TX path through this module, so gmii_tx* outputs
// carry one extra register stage relative to mac_tx (uniform pipeline delay,
// no protocol impact).
//
// Verification Hooks:
//   - Assertion: TX_EN/TX_ER timing relative to GTX_CLK
//   - Assertion: RX_DV/RX_ER timing relative to RX_CLK
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_gmii_if (
    //==========================================================================
    // GMII TX Interface (MAC -> PHY), gtx_clk domain
    //==========================================================================
    input  wire        gtx_clk,        // TX clock (125 MHz, MAC generates)
    input  wire        tx_rst_n,       // TX domain reset (async assert, sync deassert)

    // From MAC TX logic
    input  wire [7:0]  mac_txd,        // TX data from MAC
    input  wire        mac_tx_en,      // TX enable from MAC
    input  wire        mac_tx_er,      // TX error from MAC

    // To PHY (registered at boundary)
    output reg  [7:0]  gmii_txd,       // TX data to PHY
    output reg         gmii_tx_en,     // TX enable to PHY
    output reg         gmii_tx_er,     // TX error to PHY

    //==========================================================================
    // GMII RX Interface (PHY -> MAC), rx_clk domain
    //==========================================================================
    input  wire        rx_clk,         // RX clock (125 MHz, from PHY)
    input  wire        rx_rst_n,       // RX domain reset (async assert, sync deassert)

    // From PHY
    input  wire [7:0]  gmii_rxd,       // RX data from PHY
    input  wire        gmii_rx_dv,     // RX data valid from PHY
    input  wire        gmii_rx_er,     // RX error from PHY

    // To MAC RX logic (registered for timing)
    output reg  [7:0]  mac_rxd,        // RX data to MAC
    output reg         mac_rx_dv,      // RX data valid to MAC
    output reg         mac_rx_er,      // RX error to MAC

    //==========================================================================
    // Optional Carrier/Collision Signals (half-duplex, unused in Phase 0)
    //==========================================================================
    input  wire        gmii_col,       // Collision detect from PHY
    input  wire        gmii_crs,       // Carrier sense from PHY
    output reg         mac_col,        // Collision to MAC (registered)
    output reg         mac_crs         // Carrier sense to MAC (registered)
);

    //==========================================================================
    // TX Signal Registration (gtx_clk)
    //==========================================================================
    always @(posedge gtx_clk or negedge tx_rst_n) begin
        if (!tx_rst_n) begin
            gmii_txd   <= 8'h00;
            gmii_tx_en <= 1'b0;
            gmii_tx_er <= 1'b0;
        end else begin
            gmii_txd   <= mac_txd;
            gmii_tx_en <= mac_tx_en;
            gmii_tx_er <= mac_tx_er;
        end
    end

    //==========================================================================
    // RX Signal Registration (rx_clk)
    //==========================================================================
    always @(posedge rx_clk or negedge rx_rst_n) begin
        if (!rx_rst_n) begin
            mac_rxd   <= 8'h00;
            mac_rx_dv <= 1'b0;
            mac_rx_er <= 1'b0;
        end else begin
            mac_rxd   <= gmii_rxd;
            mac_rx_dv <= gmii_rx_dv;
            mac_rx_er <= gmii_rx_er;
        end
    end

    //==========================================================================
    // Carrier/Collision Signal Registration (rx_clk)
    // Not used in full-duplex operation (Phase 0)
    //==========================================================================
    always @(posedge rx_clk or negedge rx_rst_n) begin
        if (!rx_rst_n) begin
            mac_col <= 1'b0;
            mac_crs <= 1'b0;
        end else begin
            mac_col <= gmii_col;
            mac_crs <= gmii_crs;
        end
    end

endmodule
