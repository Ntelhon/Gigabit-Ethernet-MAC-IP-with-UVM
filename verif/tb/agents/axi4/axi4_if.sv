// File: axi4_if.sv
interface axi4_if #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 64,
  parameter int ID_WIDTH   = 4,
  parameter int USER_WIDTH = 1
)(
  input logic clk,
  input logic rst_n
);
  logic [ID_WIDTH-1:0]    awid;
  logic [ADDR_WIDTH-1:0]  awaddr;
  logic [7:0]             awlen;
  logic [2:0]             awsize;
  logic [1:0]             awburst;
  logic                   awlock;
  logic [3:0]             awcache;
  logic [2:0]             awprot;
  logic [3:0]             awqos;
  logic [3:0]             awregion;
  logic [USER_WIDTH-1:0]  awuser;
  logic                   awvalid;
  logic                   awready;
  logic [DATA_WIDTH-1:0]     wdata;
  logic [(DATA_WIDTH/8)-1:0] wstrb;
  logic                      wlast;
  logic [USER_WIDTH-1:0]     wuser;
  logic                      wvalid;
  logic                      wready;
  logic [ID_WIDTH-1:0]   bid;
  logic [1:0]            bresp;
  logic [USER_WIDTH-1:0] buser;
  logic                  bvalid;
  logic                  bready;
  logic [ID_WIDTH-1:0]    arid;
  logic [ADDR_WIDTH-1:0]  araddr;
  logic [7:0]             arlen;
  logic [2:0]             arsize;
  logic [1:0]             arburst;
  logic                   arlock;
  logic [3:0]             arcache;
  logic [2:0]             arprot;
  logic [3:0]             arqos;
  logic [3:0]             arregion;
  logic [USER_WIDTH-1:0]  aruser;
  logic                   arvalid;
  logic                   arready;
  logic [ID_WIDTH-1:0]   rid;
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rlast;
  logic [USER_WIDTH-1:0] ruser;
  logic                  rvalid;
  logic                  rready;
  clocking master_driver_cb @(posedge clk);
    default input #1step output #1ns;
    output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser, awvalid;
    input  awready;
    output wdata, wstrb, wlast, wuser, wvalid;
    input  wready;
    input  bid, bresp, buser, bvalid;
    output bready;
    output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser, arvalid;
    input  arready;
    input  rid, rdata, rresp, rlast, ruser, rvalid;
    output rready;
  endclocking
  clocking monitor_cb @(posedge clk);
    default input #1step output #1ns;
    input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser, awvalid, awready;
    input wdata, wstrb, wlast, wuser, wvalid, wready;
    input bid, bresp, buser, bvalid, bready;
    input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser, arvalid, arready;
    input rid, rdata, rresp, rlast, ruser, rvalid, rready;
  endclocking
  modport master_driver (clocking master_driver_cb, input rst_n);
  modport monitor (clocking monitor_cb, input rst_n);
endinterface : axi4_if
