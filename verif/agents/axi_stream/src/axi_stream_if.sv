// File: tb/agents/axi_stream/axi_stream_if.sv
interface axi_stream_if #(
  parameter int DATA_WIDTH = 32,
  parameter int USER_WIDTH = 1,
  parameter int DEST_WIDTH = 1,
  parameter int ID_WIDTH   = 1
)(
  input logic clk,
  input logic rst_n
);

  // AXI-Stream signals
  logic                      tvalid;
  logic                      tready;
  logic [DATA_WIDTH-1:0]     tdata;
  logic [(DATA_WIDTH/8)-1:0] tstrb;
  logic [(DATA_WIDTH/8)-1:0] tkeep;
  logic                      tlast;
  logic [USER_WIDTH-1:0]     tuser;
  logic [DEST_WIDTH-1:0]     tdest;
  logic [ID_WIDTH-1:0]       tid;

  // Clocking blocks for driver and monitor
  clocking driver_cb @(posedge clk);
    default input #1step output #1ns;
    output tvalid, tdata, tstrb, tkeep, tlast, tuser, tdest, tid;
    input  tready;
  endclocking

  clocking monitor_cb @(posedge clk);
    default input #1step output #1ns;
    input tvalid, tready, tdata, tstrb, tkeep, tlast, tuser, tdest, tid;
  endclocking

  // Modports
  modport driver (clocking driver_cb, input rst_n);
  modport monitor (clocking monitor_cb, input rst_n);
  modport dut_master (input tready, output tvalid, tdata, tstrb, tkeep, tlast, tuser, tdest, tid);
  modport dut_slave (output tready, input tvalid, tdata, tstrb, tkeep, tlast, tuser, tdest, tid);

endinterface : axi_stream_if
