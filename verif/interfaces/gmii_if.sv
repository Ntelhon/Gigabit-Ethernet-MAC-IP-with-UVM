//==============================================================================
// Interface: gmii_if
// Description: GMII (Gigabit Media Independent Interface) for UVM verification
//
// Purpose:
//   Provides a clean signal abstraction layer for connecting UVM agents
//   to the DUT's GMII interface. Supports both TX and RX directions with
//   appropriate modports and clocking blocks.
//
// Signal Directions (from MAC perspective):
//   TX: MAC drives TXD, TX_EN, TX_ER; PHY receives
//   RX: PHY drives RXD, RX_DV, RX_ER; MAC receives
//
// Clocking Blocks:
//   - tx_mon_cb: TX monitor samples on TX clock rising edge
//   - rx_drv_cb: RX driver drives on RX clock rising edge
//   - rx_mon_cb: RX monitor samples on RX clock rising edge
//
// Modports:
//   - mac_tx: MAC transmit port (drives TX signals)
//   - mac_rx: MAC receive port (samples RX signals)
//   - phy_tx: PHY transmit port (samples TX signals from MAC)
//   - phy_rx: PHY receive port (drives RX signals to MAC)
//   - monitor: Passive observation of all signals
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//   - No DPI or vendor libraries
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

interface gmii_if (
    input logic tx_clk,     // TX clock (125 MHz, from MAC/GTX_CLK)
    input logic rx_clk      // RX clock (125 MHz, from PHY)
);

    //==========================================================================
    // TX Signals (MAC -> PHY direction)
    // These signals are driven by the MAC on the rising edge of tx_clk
    //==========================================================================
    logic [7:0] txd;        // Transmit data (8 bits)
    logic       tx_en;      // Transmit enable
    logic       tx_er;      // Transmit error

    //==========================================================================
    // RX Signals (PHY -> MAC direction)
    // These signals are driven by the PHY on the rising edge of rx_clk
    //==========================================================================
    logic [7:0] rxd;        // Receive data (8 bits)
    logic       rx_dv;      // Receive data valid
    logic       rx_er;      // Receive error

    //==========================================================================
    // Optional Status Signals (directly from PHY)
    // Used for half-duplex mode (not typically needed for 1Gbps full-duplex)
    //==========================================================================
    logic       col;        // Collision detect
    logic       crs;        // Carrier sense

    //==========================================================================
    // Clocking Block: TX Monitor
    // Used by TX monitor to sample transmitted data
    // Samples on rising edge of tx_clk with 1-step input skew
    //==========================================================================
    clocking tx_mon_cb @(posedge tx_clk);
        default input #1step output #1step;
        input txd;
        input tx_en;
        input tx_er;
    endclocking

    //==========================================================================
    // Clocking Block: RX Driver
    // Used by RX driver (PHY BFM) to drive received data to MAC
    // Drives on rising edge of rx_clk
    //==========================================================================
    clocking rx_drv_cb @(posedge rx_clk);
        default input #1step output #1step;
        output rxd;
        output rx_dv;
        output rx_er;
        output col;
        output crs;
    endclocking

    //==========================================================================
    // Clocking Block: RX Monitor
    // Used by RX monitor to sample received data
    // Samples on rising edge of rx_clk with 1-step input skew
    //==========================================================================
    clocking rx_mon_cb @(posedge rx_clk);
        default input #1step output #1step;
        input rxd;
        input rx_dv;
        input rx_er;
    endclocking

    //==========================================================================
    // Clocking Block: TX Driver (for loopback or special testing)
    // Used if testbench needs to drive TX signals directly
    //==========================================================================
    clocking tx_drv_cb @(posedge tx_clk);
        default input #1step output #1step;
        output txd;
        output tx_en;
        output tx_er;
    endclocking

    //==========================================================================
    // Modport: MAC TX
    // Used when connecting to MAC's transmit side
    // MAC drives: txd, tx_en, tx_er
    //==========================================================================
    modport mac_tx (
        input  tx_clk,
        output txd,
        output tx_en,
        output tx_er
    );

    //==========================================================================
    // Modport: MAC RX
    // Used when connecting to MAC's receive side
    // MAC samples: rxd, rx_dv, rx_er, col, crs
    //==========================================================================
    modport mac_rx (
        input rx_clk,
        input rxd,
        input rx_dv,
        input rx_er,
        input col,
        input crs
    );

    //==========================================================================
    // Modport: PHY TX
    // Used by PHY model or TX monitor
    // PHY samples: txd, tx_en, tx_er (from MAC)
    //==========================================================================
    modport phy_tx (
        input tx_clk,
        input txd,
        input tx_en,
        input tx_er
    );

    //==========================================================================
    // Modport: PHY RX
    // Used by PHY model or RX driver
    // PHY drives: rxd, rx_dv, rx_er, col, crs (to MAC)
    //==========================================================================
    modport phy_rx (
        input  rx_clk,
        output rxd,
        output rx_dv,
        output rx_er,
        output col,
        output crs
    );

    //==========================================================================
    // Modport: Monitor
    // Passive observation of all signals (for scoreboard/coverage)
    //==========================================================================
    modport monitor (
        input tx_clk,
        input rx_clk,
        input txd,
        input tx_en,
        input tx_er,
        input rxd,
        input rx_dv,
        input rx_er,
        input col,
        input crs
    );

    //==========================================================================
    // Modport: TX Monitor with Clocking Block
    // For UVM monitor using clocking block
    //==========================================================================
    modport tx_monitor (
        input tx_clk,
        clocking tx_mon_cb
    );

    //==========================================================================
    // Modport: RX Driver with Clocking Block
    // For UVM driver using clocking block
    //==========================================================================
    modport rx_driver (
        input rx_clk,
        clocking rx_drv_cb
    );

    //==========================================================================
    // Modport: RX Monitor with Clocking Block
    // For UVM monitor using clocking block
    //==========================================================================
    modport rx_monitor (
        input rx_clk,
        clocking rx_mon_cb
    );

    //==========================================================================
    // Signal Initialization Task
    // Call during reset to initialize all signals to known state
    //==========================================================================
    task automatic init_rx_signals();
        rxd   <= 8'h00;
        rx_dv <= 1'b0;
        rx_er <= 1'b0;
        col   <= 1'b0;
        crs   <= 1'b0;
    endtask

    task automatic init_tx_signals();
        txd   <= 8'h00;
        tx_en <= 1'b0;
        tx_er <= 1'b0;
    endtask

endinterface : gmii_if
