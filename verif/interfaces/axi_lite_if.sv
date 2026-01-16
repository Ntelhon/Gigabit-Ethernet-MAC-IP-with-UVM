//==============================================================================
// Interface: axi_lite_if
// Description: AXI4-Lite interface for UVM verification
//
// Purpose:
//   Provides a clean signal abstraction layer for connecting UVM agents
//   to the DUT's AXI4-Lite slave interface. Supports all five AXI channels
//   with appropriate modports and clocking blocks.
//
// AXI4-Lite Channels:
//   - AW: Write Address Channel
//   - W:  Write Data Channel
//   - B:  Write Response Channel
//   - AR: Read Address Channel
//   - R:  Read Data Channel
//
// Parameters:
//   - ADDR_WIDTH: Address width (default 32 bits)
//   - DATA_WIDTH: Data width (default 32 bits)
//
// Modports:
//   - master: AXI master (initiator) - drives address/data, receives response
//   - slave:  AXI slave (target) - receives address/data, drives response
//   - monitor: Passive observation of all signals
//
// Clocking Block:
//   - drv_cb: For master driver with proper timing
//   - mon_cb: For monitor with proper sampling
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//   - No DPI or vendor libraries
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

interface axi_lite_if #(
    parameter int ADDR_WIDTH = 32,      // Address width
    parameter int DATA_WIDTH = 32       // Data width (must be 32 or 64 for AXI4-Lite)
) (
    input logic aclk,                   // AXI clock
    input logic aresetn                 // AXI reset (active low)
);

    //==========================================================================
    // Local Parameters
    //==========================================================================
    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    //==========================================================================
    // Write Address Channel (AW)
    // Master -> Slave
    //==========================================================================
    logic [ADDR_WIDTH-1:0]  awaddr;     // Write address
    logic [2:0]             awprot;     // Protection type (optional, usually tied)
    logic                   awvalid;    // Write address valid
    logic                   awready;    // Write address ready

    //==========================================================================
    // Write Data Channel (W)
    // Master -> Slave
    //==========================================================================
    logic [DATA_WIDTH-1:0]  wdata;      // Write data
    logic [STRB_WIDTH-1:0]  wstrb;      // Write strobes (byte enables)
    logic                   wvalid;     // Write data valid
    logic                   wready;     // Write data ready

    //==========================================================================
    // Write Response Channel (B)
    // Slave -> Master
    //==========================================================================
    logic [1:0]             bresp;      // Write response (OKAY, EXOKAY, SLVERR, DECERR)
    logic                   bvalid;     // Write response valid
    logic                   bready;     // Write response ready

    //==========================================================================
    // Read Address Channel (AR)
    // Master -> Slave
    //==========================================================================
    logic [ADDR_WIDTH-1:0]  araddr;     // Read address
    logic [2:0]             arprot;     // Protection type (optional, usually tied)
    logic                   arvalid;    // Read address valid
    logic                   arready;    // Read address ready

    //==========================================================================
    // Read Data Channel (R)
    // Slave -> Master
    //==========================================================================
    logic [DATA_WIDTH-1:0]  rdata;      // Read data
    logic [1:0]             rresp;      // Read response
    logic                   rvalid;     // Read data valid
    logic                   rready;     // Read data ready

    //==========================================================================
    // AXI Response Encoding (for reference)
    //==========================================================================
    // localparam RESP_OKAY   = 2'b00;  // Normal access success
    // localparam RESP_EXOKAY = 2'b01;  // Exclusive access success
    // localparam RESP_SLVERR = 2'b10;  // Slave error
    // localparam RESP_DECERR = 2'b11;  // Decode error

    //==========================================================================
    // Clocking Block: Master Driver
    // Used by UVM driver to drive master-side signals
    //==========================================================================
    clocking drv_cb @(posedge aclk);
        default input #1step output #1step;
        
        // Write Address Channel (Master drives)
        output awaddr;
        output awprot;
        output awvalid;
        input  awready;
        
        // Write Data Channel (Master drives)
        output wdata;
        output wstrb;
        output wvalid;
        input  wready;
        
        // Write Response Channel (Master receives)
        input  bresp;
        input  bvalid;
        output bready;
        
        // Read Address Channel (Master drives)
        output araddr;
        output arprot;
        output arvalid;
        input  arready;
        
        // Read Data Channel (Master receives)
        input  rdata;
        input  rresp;
        input  rvalid;
        output rready;
    endclocking

    //==========================================================================
    // Clocking Block: Monitor
    // Used by UVM monitor to sample all signals
    //==========================================================================
    clocking mon_cb @(posedge aclk);
        default input #1step output #1step;
        
        // Write Address Channel
        input awaddr;
        input awprot;
        input awvalid;
        input awready;
        
        // Write Data Channel
        input wdata;
        input wstrb;
        input wvalid;
        input wready;
        
        // Write Response Channel
        input bresp;
        input bvalid;
        input bready;
        
        // Read Address Channel
        input araddr;
        input arprot;
        input arvalid;
        input arready;
        
        // Read Data Channel
        input rdata;
        input rresp;
        input rvalid;
        input rready;
    endclocking

    //==========================================================================
    // Clocking Block: Slave Driver
    // Used by slave BFM to drive slave-side signals
    //==========================================================================
    clocking slv_cb @(posedge aclk);
        default input #1step output #1step;
        
        // Write Address Channel (Slave receives)
        input  awaddr;
        input  awprot;
        input  awvalid;
        output awready;
        
        // Write Data Channel (Slave receives)
        input  wdata;
        input  wstrb;
        input  wvalid;
        output wready;
        
        // Write Response Channel (Slave drives)
        output bresp;
        output bvalid;
        input  bready;
        
        // Read Address Channel (Slave receives)
        input  araddr;
        input  arprot;
        input  arvalid;
        output arready;
        
        // Read Data Channel (Slave drives)
        output rdata;
        output rresp;
        output rvalid;
        input  rready;
    endclocking

    //==========================================================================
    // Modport: Master
    // Used when connecting to AXI master (initiator side)
    //==========================================================================
    modport master (
        input  aclk,
        input  aresetn,
        
        // Write Address Channel
        output awaddr,
        output awprot,
        output awvalid,
        input  awready,
        
        // Write Data Channel
        output wdata,
        output wstrb,
        output wvalid,
        input  wready,
        
        // Write Response Channel
        input  bresp,
        input  bvalid,
        output bready,
        
        // Read Address Channel
        output araddr,
        output arprot,
        output arvalid,
        input  arready,
        
        // Read Data Channel
        input  rdata,
        input  rresp,
        input  rvalid,
        output rready
    );

    //==========================================================================
    // Modport: Slave
    // Used when connecting to AXI slave (target side - the DUT)
    //==========================================================================
    modport slave (
        input  aclk,
        input  aresetn,
        
        // Write Address Channel
        input  awaddr,
        input  awprot,
        input  awvalid,
        output awready,
        
        // Write Data Channel
        input  wdata,
        input  wstrb,
        input  wvalid,
        output wready,
        
        // Write Response Channel
        output bresp,
        output bvalid,
        input  bready,
        
        // Read Address Channel
        input  araddr,
        input  arprot,
        input  arvalid,
        output arready,
        
        // Read Data Channel
        output rdata,
        output rresp,
        output rvalid,
        input  rready
    );

    //==========================================================================
    // Modport: Monitor
    // Passive observation of all signals (for scoreboard/coverage)
    //==========================================================================
    modport monitor (
        input aclk,
        input aresetn,
        input awaddr,
        input awprot,
        input awvalid,
        input awready,
        input wdata,
        input wstrb,
        input wvalid,
        input wready,
        input bresp,
        input bvalid,
        input bready,
        input araddr,
        input arprot,
        input arvalid,
        input arready,
        input rdata,
        input rresp,
        input rvalid,
        input rready
    );

    //==========================================================================
    // Modport: Master Driver with Clocking Block
    // For UVM driver using clocking block
    //==========================================================================
    modport master_drv (
        input aclk,
        input aresetn,
        clocking drv_cb
    );

    //==========================================================================
    // Modport: Slave Driver with Clocking Block
    // For UVM slave driver/responder using clocking block
    //==========================================================================
    modport slave_drv (
        input aclk,
        input aresetn,
        clocking slv_cb
    );

    //==========================================================================
    // Modport: Monitor with Clocking Block
    // For UVM monitor using clocking block
    //==========================================================================
    modport mon (
        input aclk,
        input aresetn,
        clocking mon_cb
    );

    //==========================================================================
    // Signal Initialization Task
    // Call during reset to initialize all master-driven signals
    //==========================================================================
    task automatic init_master_signals();
        awaddr  <= {ADDR_WIDTH{1'b0}};
        awprot  <= 3'b000;
        awvalid <= 1'b0;
        wdata   <= {DATA_WIDTH{1'b0}};
        wstrb   <= {STRB_WIDTH{1'b0}};
        wvalid  <= 1'b0;
        bready  <= 1'b0;
        araddr  <= {ADDR_WIDTH{1'b0}};
        arprot  <= 3'b000;
        arvalid <= 1'b0;
        rready  <= 1'b0;
    endtask

    //==========================================================================
    // Signal Initialization Task
    // Call during reset to initialize all slave-driven signals
    //==========================================================================
    task automatic init_slave_signals();
        awready <= 1'b0;
        wready  <= 1'b0;
        bresp   <= 2'b00;
        bvalid  <= 1'b0;
        arready <= 1'b0;
        rdata   <= {DATA_WIDTH{1'b0}};
        rresp   <= 2'b00;
        rvalid  <= 1'b0;
    endtask

    //==========================================================================
    // Helper Task: Wait for clock cycles
    //==========================================================================
    task automatic wait_clks(input int num_clks);
        repeat (num_clks) @(posedge aclk);
    endtask

    //==========================================================================
    // Helper Task: Wait for reset de-assertion
    //==========================================================================
    task automatic wait_for_reset();
        @(posedge aresetn);
        @(posedge aclk);
    endtask

endinterface : axi_lite_if
