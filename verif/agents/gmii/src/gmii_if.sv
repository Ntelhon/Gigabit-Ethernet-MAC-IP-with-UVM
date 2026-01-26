// File: tb/agents/gmii/gmii_if.sv
interface gmii_if(
  input logic gtx_clk,  // TX clock (125 MHz for Gigabit)
  input logic rx_clk,   // RX clock (recovered from PHY)
  input logic rst_n
);

  // TX signals
  logic       tx_en;
  logic       tx_er;
  logic [7:0] txd;

  // RX signals
  logic       rx_dv;
  logic       rx_er;
  logic [7:0] rxd;

  // Management interface (MDIO)
  logic       mdc;
  logic       mdio_o;
  logic       mdio_i;
  logic       mdio_t;  // Tristate control

  // Clocking blocks
  clocking tx_driver_cb @(posedge gtx_clk);
    default input #1step output #1ns;
    output tx_en, tx_er, txd;
  endclocking

  clocking rx_driver_cb @(posedge rx_clk);
    default input #1step output #1ns;
    output rx_dv, rx_er, rxd;
  endclocking

  clocking tx_monitor_cb @(posedge gtx_clk);
    default input #1step output #1ns;
    input tx_en, tx_er, txd;
  endclocking

  clocking rx_monitor_cb @(posedge rx_clk);
    default input #1step output #1ns;
    input rx_dv, rx_er, rxd;
  endclocking

  // Modports
  modport tx_driver (clocking tx_driver_cb, input rst_n);
  modport rx_driver (clocking rx_driver_cb, input rst_n);
  modport tx_monitor (clocking tx_monitor_cb, input rst_n);
  modport rx_monitor (clocking rx_monitor_cb, input rst_n);

endinterface : gmii_if
