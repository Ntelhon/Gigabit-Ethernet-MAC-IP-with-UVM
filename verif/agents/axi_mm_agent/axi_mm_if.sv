//==============================================================================
// AXI4 Memory Interface
//==============================================================================

`ifndef AXI_MM_IF_SV
`define AXI_MM_IF_SV

interface axi_mm_if #(
    parameter int ADDR_WIDTH = 64,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4
)(
    input logic clk,
    input logic rst_n
);
    
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    
    //--------------------------------------------------------------------------
    // Write Address Channel
    //--------------------------------------------------------------------------
    logic                       awvalid;
    logic                       awready;
    logic [ADDR_WIDTH-1:0]      awaddr;
    logic [7:0]                 awlen;
    logic [2:0]                 awsize;
    logic [1:0]                 awburst;
    logic [ID_WIDTH-1:0]        awid;
    
    //--------------------------------------------------------------------------
    // Write Data Channel
    //--------------------------------------------------------------------------
    logic                       wvalid;
    logic                       wready;
    logic [DATA_WIDTH-1:0]      wdata;
    logic [STRB_WIDTH-1:0]      wstrb;
    logic                       wlast;
    
    //--------------------------------------------------------------------------
    // Write Response Channel
    //--------------------------------------------------------------------------
    logic                       bvalid;
    logic                       bready;
    logic [1:0]                 bresp;
    logic [ID_WIDTH-1:0]        bid;
    
    //--------------------------------------------------------------------------
    // Read Address Channel
    //--------------------------------------------------------------------------
    logic                       arvalid;
    logic                       arready;
    logic [ADDR_WIDTH-1:0]      araddr;
    logic [7:0]                 arlen;
    logic [2:0]                 arsize;
    logic [1:0]                 arburst;
    logic [ID_WIDTH-1:0]        arid;
    
    //--------------------------------------------------------------------------
    // Read Data Channel
    //--------------------------------------------------------------------------
    logic                       rvalid;
    logic                       rready;
    logic [DATA_WIDTH-1:0]      rdata;
    logic [1:0]                 rresp;
    logic                       rlast;
    logic [ID_WIDTH-1:0]        rid;
    
    //--------------------------------------------------------------------------
    // Clocking Blocks
    //--------------------------------------------------------------------------
    
    // Slave (responder) clocking block
    clocking slave_cb @(posedge clk);
        default input #1step output #1ns;
        
        // Write address - slave sees these as inputs
        input  awvalid, awaddr, awlen, awsize, awburst, awid;
        output awready;
        
        // Write data
        input  wvalid, wdata, wstrb, wlast;
        output wready;
        
        // Write response
        output bvalid, bresp, bid;
        input  bready;
        
        // Read address
        input  arvalid, araddr, arlen, arsize, arburst, arid;
        output arready;
        
        // Read data
        output rvalid, rdata, rresp, rlast, rid;
        input  rready;
    endclocking
    
    // Monitor clocking block
    clocking mon_cb @(posedge clk);
        default input #1step;
        
        input awvalid, awready, awaddr, awlen, awsize, awburst, awid;
        input wvalid, wready, wdata, wstrb, wlast;
        input bvalid, bready, bresp, bid;
        input arvalid, arready, araddr, arlen, arsize, arburst, arid;
        input rvalid, rready, rdata, rresp, rlast, rid;
    endclocking
    
    //--------------------------------------------------------------------------
    // Modports
    //--------------------------------------------------------------------------
    modport slave (clocking slave_cb, input clk, input rst_n);
    modport monitor (clocking mon_cb, input clk, input rst_n);
    
    //--------------------------------------------------------------------------
    // Assertions
    //--------------------------------------------------------------------------
    
    // AW channel: valid must stay high until ready
    property aw_valid_stable;
        @(posedge clk) disable iff (!rst_n)
        awvalid && !awready |=> awvalid;
    endproperty
    assert property (aw_valid_stable)
        else `uvm_error("AXI_MM_IF", "AWVALID de-asserted before AWREADY")
    
    // W channel: valid must stay high until ready
    property w_valid_stable;
        @(posedge clk) disable iff (!rst_n)
        wvalid && !wready |=> wvalid;
    endproperty
    assert property (w_valid_stable)
        else `uvm_error("AXI_MM_IF", "WVALID de-asserted before WREADY")
    
    // AR channel: valid must stay high until ready
    property ar_valid_stable;
        @(posedge clk) disable iff (!rst_n)
        arvalid && !arready |=> arvalid;
    endproperty
    assert property (ar_valid_stable)
        else `uvm_error("AXI_MM_IF", "ARVALID de-asserted before ARREADY")
    
endinterface : axi_mm_if

`endif // AXI_MM_IF_SV
