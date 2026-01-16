//==============================================================================
// Module: mac_gmii_if
// Description: GMII signal interface and clock domain boundary for MAC core
//
// Features:
//   - Clean GMII signal grouping
//   - Clock domain boundary definition
//   - Signal registration for timing closure
//   - No PHY-specific behavior
//   - Technology independent
//
// GMII Specification (IEEE 802.3):
//   - TX: 8-bit data, TX_EN, TX_ER, GTX_CLK (125 MHz from MAC)
//   - RX: 8-bit data, RX_DV, RX_ER, RX_CLK (125 MHz from PHY)
//   - Management: MDIO, MDC (optional, not included in Phase 0)
//
// Clock Domains:
//   - TX: Uses GTX_CLK (MAC-generated 125 MHz)
//   - RX: Uses RX_CLK (PHY-generated 125 MHz)
//   - System: sys_clk (for register interface)
//
// Verification Hooks:
//   - Assertion: TX_EN/TX_ER timing relative to GTX_CLK
//   - Assertion: RX_DV/RX_ER timing relative to RX_CLK
//   - Coverage: All signal combinations
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_gmii_if (
    //==========================================================================
    // GMII TX Interface (MAC -> PHY)
    // Clock domain: gtx_clk (125 MHz, sourced by MAC)
    //==========================================================================
    input  wire        gtx_clk,        // TX clock (125 MHz, MAC generates)
    input  wire        tx_rst_n,       // TX domain reset (active low)
    
    // From MAC TX logic
    input  wire [7:0]  mac_txd,        // TX data from MAC
    input  wire        mac_tx_en,      // TX enable from MAC
    input  wire        mac_tx_er,      // TX error from MAC
    
    // To PHY (directly routed, registered at boundary)
    output reg  [7:0]  gmii_txd,       // TX data to PHY
    output reg         gmii_tx_en,     // TX enable to PHY
    output reg         gmii_tx_er,     // TX error to PHY

    //==========================================================================
    // GMII RX Interface (PHY -> MAC)
    // Clock domain: rx_clk (125 MHz, sourced by PHY)
    //==========================================================================
    input  wire        rx_clk,         // RX clock (125 MHz, from PHY)
    input  wire        rx_rst_n,       // RX domain reset (active low)
    
    // From PHY
    input  wire [7:0]  gmii_rxd,       // RX data from PHY
    input  wire        gmii_rx_dv,     // RX data valid from PHY
    input  wire        gmii_rx_er,     // RX error from PHY
    
    // To MAC RX logic (registered for timing)
    output reg  [7:0]  mac_rxd,        // RX data to MAC
    output reg         mac_rx_dv,      // RX data valid to MAC
    output reg         mac_rx_er,      // RX error to MAC

    //==========================================================================
    // Optional Carrier/Collision Signals (for half-duplex, unused in Phase 0)
    //==========================================================================
    input  wire        gmii_col,       // Collision detect from PHY
    input  wire        gmii_crs,       // Carrier sense from PHY
    output reg         mac_col,        // Collision to MAC (registered)
    output reg         mac_crs         // Carrier sense to MAC (registered)
);

    //==========================================================================
    // TX Signal Registration
    // Registered on GTX_CLK rising edge for clean timing to PHY
    //==========================================================================
    always @(posedge gtx_clk) begin
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
    // RX Signal Registration
    // Registered on RX_CLK rising edge for metastability protection
    // Note: This provides a clean sampling point for MAC RX logic
    //==========================================================================
    always @(posedge rx_clk) begin
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
    // Carrier/Collision Signal Registration
    // These are asynchronous from PHY, registered on RX clock
    // Note: Not used in full-duplex operation (Phase 0)
    //==========================================================================
    always @(posedge rx_clk) begin
        if (!rx_rst_n) begin
            mac_col <= 1'b0;
            mac_crs <= 1'b0;
        end else begin
            mac_col <= gmii_col;
            mac_crs <= gmii_crs;
        end
    end

endmodule
