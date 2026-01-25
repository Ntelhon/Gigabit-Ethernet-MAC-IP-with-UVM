// File: gmii_if.sv
interface gmii_if (
  input logic gtx_clk,
  input logic rx_clk,
  input logic rst_n
);
  // Transmit signals
  logic [7:0] txd;
  logic       tx_en;
  logic       tx_er;
  // Receive signals
  logic [7:0] rxd;
  logic       rx_dv;
  logic       rx_er;
  // Management signals
  logic       mdc;
  logic       mdio_o;
  logic       mdio_i;
  logic       mdio_t;

  // Transmit driver clocking block
  clocking tx_driver_cb @(posedge gtx_clk);
    default input #1step output #1ns;
    output txd, tx_en, tx_er;
  endclocking

  // Receive driver clocking block
  clocking rx_driver_cb @(posedge rx_clk);
    default input #1step output #1ns;
    output rxd, rx_dv, rx_er;
  endclocking

  // Transmit monitor clocking block
  clocking tx_monitor_cb @(posedge gtx_clk);
    default input #1step output #1ns;
    input txd, tx_en, tx_er;
  endclocking

  // Receive monitor clocking block
  clocking rx_monitor_cb @(posedge rx_clk);
    default input #1step output #1ns;
    input rxd, rx_dv, rx_er;
  endclocking

  // Modports for driver and monitor
  modport TX_DRIVER (clocking tx_driver_cb, input rst_n);
  modport RX_DRIVER (clocking rx_driver_cb, input rst_n);
  modport TX_MONITOR (clocking tx_monitor_cb, input rst_n);
  modport RX_MONITOR (clocking rx_monitor_cb, input rst_n);
endinterface : gmii_if
