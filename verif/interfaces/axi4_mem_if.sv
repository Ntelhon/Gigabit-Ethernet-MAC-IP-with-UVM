//==============================================================================
// Interface: axi4_mem_if
// Description: AXI4 Full (Memory-Mapped) interface
//
// Parameterizable AXI4 interface for memory operations
//==============================================================================

interface axi4_mem_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH = 4
) (
    input logic clk,
    input logic rst_n
);

    // Write Address Channel
    logic [ID_WIDTH-1:0]     awid;
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic [7:0]              awlen;
    logic [2:0]              awsize;
    logic [1:0]              awburst;
    logic                    awlock;
    logic [3:0]              awcache;
    logic [2:0]              awprot;
    logic                    awvalid;
    logic                    awready;

    // Write Data Channel
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wlast;
    logic                    wvalid;
    logic                    wready;

    // Write Response Channel
    logic [ID_WIDTH-1:0]     bid;
    logic [1:0]              bresp;
    logic                    bvalid;
    logic                    bready;

    // Read Address Channel
    logic [ID_WIDTH-1:0]     arid;
    logic [ADDR_WIDTH-1:0]   araddr;
    logic [7:0]              arlen;
    logic [2:0]              arsize;
    logic [1:0]              arburst;
    logic                    arlock;
    logic [3:0]              arcache;
    logic [2:0]              arprot;
    logic                    arvalid;
    logic                    arready;

    // Read Data Channel
    logic [ID_WIDTH-1:0]     rid;
    logic [DATA_WIDTH-1:0]   rdata;
    logic [1:0]              rresp;
    logic                    rlast;
    logic                    rvalid;
    logic                    rready;

    // Clocking blocks for driver/monitor
    clocking master_cb @(posedge clk);
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid;
        input  awready;
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        input  bid, bresp, bvalid;
        output bready;
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    clocking slave_cb @(posedge clk);
        input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid;
        output awready;
        input  wdata, wstrb, wlast, wvalid;
        output wready;
        output bid, bresp, bvalid;
        input  bready;
        input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid;
        output arready;
        output rid, rdata, rresp, rlast, rvalid;
        input  rready;
    endclocking

    clocking monitor_cb @(posedge clk);
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    modport master (clocking master_cb);
    modport slave (clocking slave_cb);
    modport monitor (clocking monitor_cb);

endinterface : axi4_mem_if
