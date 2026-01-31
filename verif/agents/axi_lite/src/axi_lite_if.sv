// File: tb/env/eth_controller/axi_lite_agent/axi_lite_if.sv
interface axi_lite_if #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input logic clk,
  input logic rst_n
);

  // Write Address Channel
  logic [ADDR_WIDTH-1:0] awaddr;
  logic [2:0]            awprot;
  logic                  awvalid;
  logic                  awready;

  // Write Data Channel
  logic [DATA_WIDTH-1:0]     wdata;
  logic [(DATA_WIDTH/8)-1:0] wstrb;
  logic                      wvalid;
  logic                      wready;

  // Write Response Channel
  logic [1:0] bresp;
  logic       bvalid;
  logic       bready;

  // Read Address Channel
  logic [ADDR_WIDTH-1:0] araddr;
  logic [2:0]            arprot;
  logic                  arvalid;
  logic                  arready;

  // Read Data Channel
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rvalid;
  logic                  rready;

  // Clocking blocks
  clocking master_driver_cb @(posedge clk);
    default input #1step output #1ns;
    output awaddr, awprot, awvalid;
    input  awready;
    output wdata, wstrb, wvalid;
    input  wready;
    input  bresp, bvalid;
    output bready;
    output araddr, arprot, arvalid;
    input  arready;
    input  rdata, rresp, rvalid;
    output rready;
  endclocking

  clocking monitor_cb @(posedge clk);
    default input #1step output #1ns;
    input awaddr, awprot, awvalid, awready;
    input wdata, wstrb, wvalid, wready;
    input bresp, bvalid, bready;
    input araddr, arprot, arvalid, arready;
    input rdata, rresp, rvalid, rready;
  endclocking

  // Modports
  modport master_driver (clocking master_driver_cb, input rst_n);
  modport monitor (clocking monitor_cb, input rst_n);

  //============================================================================
  // Protocol Assertions (Optional but recommended)
  //============================================================================
  `ifdef ENABLE_ASSERTIONS
  
  // Write address channel stability
  property p_awvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    awvalid && !awready |=> $stable(awaddr) && $stable(awprot) && awvalid;
  endproperty
  aw_stable: assert property(p_awvalid_stable)
    else $error("AWVALID changed before AWREADY");

  // Write data channel stability
  property p_wvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    wvalid && !wready |=> $stable(wdata) && $stable(wstrb) && wvalid;
  endproperty
  w_stable: assert property(p_wvalid_stable)
    else $error("WVALID changed before WREADY");

  // Write response stability
  property p_bvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    bvalid && !bready |=> $stable(bresp) && bvalid;
  endproperty
  b_stable: assert property(p_bvalid_stable)
    else $error("BVALID changed before BREADY");

  // Read address channel stability
  property p_arvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    arvalid && !arready |=> $stable(araddr) && $stable(arprot) && arvalid;
  endproperty
  ar_stable: assert property(p_arvalid_stable)
    else $error("ARVALID changed before ARREADY");

  // Read data channel stability
  property p_rvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    rvalid && !rready |=> $stable(rdata) && $stable(rresp) && rvalid;
  endproperty
  r_stable: assert property(p_rvalid_stable)
    else $error("RVALID changed before RREADY");
  
  `endif
endinterface : axi_lite_if
