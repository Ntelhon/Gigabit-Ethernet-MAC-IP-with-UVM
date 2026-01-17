//==============================================================================
// Interface: axi_mm_if
// Description: AXI4 Memory Mapped Full Interface
//
// Purpose:
//   SystemVerilog interface for AXI4 full (memory-mapped) protocol used
//   for DMA master access to system memory.
//
// Features:
//   - Full AXI4 protocol support (bursts, IDs)
//   - Parameterized address and data widths
//   - Clock domain support
//   - Clocking blocks for slave and monitor
//   - Protocol assertions
//
// Parameters:
//   - ADDR_WIDTH: Address bus width (default 32)
//   - DATA_WIDTH: Data bus width (default 64)
//   - ID_WIDTH:   Transaction ID width (default 4)
//
// Usage:
//   axi_mm_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64)) axi_mm_vif(clk, rst_n);
//
// Compatibility:
//   - AXI4 Full specification
//   - UVM 1.2
//   - Vivado xsim, Xcelium
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`ifndef AXI_MM_IF_SV
`define AXI_MM_IF_SV

interface axi_mm_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4
)(
    input logic aclk,
    input logic aresetn
);
    
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    
    //==========================================================================
    // Write Address Channel
    //==========================================================================
    logic [ID_WIDTH-1:0]        awid;
    logic [ADDR_WIDTH-1:0]      awaddr;
    logic [7:0]                 awlen;
    logic [2:0]                 awsize;
    logic [1:0]                 awburst;
    logic                       awvalid;
    logic                       awready;
    
    //==========================================================================
    // Write Data Channel
    //==========================================================================
    logic [DATA_WIDTH-1:0]      wdata;
    logic [STRB_WIDTH-1:0]      wstrb;
    logic                       wlast;
    logic                       wvalid;
    logic                       wready;
    
    //==========================================================================
    // Write Response Channel
    //==========================================================================
    logic [ID_WIDTH-1:0]        bid;
    logic [1:0]                 bresp;
    logic                       bvalid;
    logic                       bready;
    
    //==========================================================================
    // Read Address Channel
    //==========================================================================
    logic [ID_WIDTH-1:0]        arid;
    logic [ADDR_WIDTH-1:0]      araddr;
    logic [7:0]                 arlen;
    logic [2:0]                 arsize;
    logic [1:0]                 arburst;
    logic                       arvalid;
    logic                       arready;
    
    //==========================================================================
    // Read Data Channel
    //==========================================================================
    logic [ID_WIDTH-1:0]        rid;
    logic [DATA_WIDTH-1:0]      rdata;
    logic [1:0]                 rresp;
    logic                       rlast;
    logic                       rvalid;
    logic                       rready;

    //==========================================================================
    // Clocking Blocks
    //==========================================================================
    
    // Slave (responder/memory) clocking block
    clocking slave_cb @(posedge aclk);
        default input #1step output #1ns;
        
        // Write address - slave sees master signals as inputs
        input  awid, awaddr, awlen, awsize, awburst, awvalid;
        output awready;
        
        // Write data
        input  wdata, wstrb, wlast, wvalid;
        output wready;
        
        // Write response
        output bid, bresp, bvalid;
        input  bready;
        
        // Read address
        input  arid, araddr, arlen, arsize, arburst, arvalid;
        output arready;
        
        // Read data
        output rid, rdata, rresp, rlast, rvalid;
        input  rready;
    endclocking
    
    // Monitor clocking block (passive observation)
    clocking mon_cb @(posedge aclk);
        default input #1step;
        
        input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking
    
    //==========================================================================
    // Modports
    //==========================================================================
    modport master (
        output awid, awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, rvalid,
        output rready,
        input  aclk, aresetn
    );
    
    modport slave (
        input  awid, awaddr, awlen, awsize, awburst, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, rvalid,
        input  rready,
        input  aclk, aresetn
    );
    
    modport monitor (
        clocking mon_cb,
        input aclk, aresetn
    );

    //==========================================================================
    // Protocol Assertions
    //==========================================================================
    `ifdef UVM_ASSERTIONS
    
    import uvm_pkg::*;
    
    // AW channel: AWVALID must stay high until AWREADY
    property aw_valid_stable;
        @(posedge aclk) disable iff (!aresetn)
        awvalid && !awready |=> awvalid;
    endproperty
    assert property (aw_valid_stable)
        else `uvm_error("AXI_MM_IF", "AWVALID de-asserted before AWREADY")
    
    // W channel: WVALID must stay high until WREADY
    property w_valid_stable;
        @(posedge aclk) disable iff (!aresetn)
        wvalid && !wready |=> wvalid;
    endproperty
    assert property (w_valid_stable)
        else `uvm_error("AXI_MM_IF", "WVALID de-asserted before WREADY")
    
    // B channel: BVALID must stay high until BREADY
    property b_valid_stable;
        @(posedge aclk) disable iff (!aresetn)
        bvalid && !bready |=> bvalid;
    endproperty
    assert property (b_valid_stable)
        else `uvm_error("AXI_MM_IF", "BVALID de-asserted before BREADY")
    
    // AR channel: ARVALID must stay high until ARREADY
    property ar_valid_stable;
        @(posedge aclk) disable iff (!aresetn)
        arvalid && !arready |=> arvalid;
    endproperty
    assert property (ar_valid_stable)
        else `uvm_error("AXI_MM_IF", "ARVALID de-asserted before ARREADY")
    
    // R channel: RVALID must stay high until RREADY
    property r_valid_stable;
        @(posedge aclk) disable iff (!aresetn)
        rvalid && !rready |=> rvalid;
    endproperty
    assert property (r_valid_stable)
        else `uvm_error("AXI_MM_IF", "RVALID de-asserted before RREADY")
    
    `endif // UVM_ASSERTIONS

    //==========================================================================
    // Functional Coverage (Optional)
    //==========================================================================
    `ifdef FUNCTIONAL_COVERAGE
    
    covergroup axi_mm_cg @(posedge aclk);
        option.per_instance = 1;
        
        // Burst types
        aw_burst_type: coverpoint awburst iff (awvalid && awready) {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            bins wrap  = {2'b10};
        }
        
        ar_burst_type: coverpoint arburst iff (arvalid && arready) {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            bins wrap  = {2'b10};
        }
        
        // Burst lengths
        aw_burst_len: coverpoint awlen iff (awvalid && awready) {
            bins single = {0};
            bins short  = {[1:3]};
            bins medium = {[4:15]};
            bins long   = {[16:255]};
        }
        
        ar_burst_len: coverpoint arlen iff (arvalid && arready) {
            bins single = {0};
            bins short  = {[1:3]};
            bins medium = {[4:15]};
            bins long   = {[16:255]};
        }
        
        // Response types
        b_resp: coverpoint bresp iff (bvalid && bready) {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }
        
        r_resp: coverpoint rresp iff (rvalid && rready) {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }
    endgroup : axi_mm_cg
    
    axi_mm_cg axi_mm_coverage = new();
    
    `endif // FUNCTIONAL_COVERAGE

endinterface : axi_mm_if

`endif // AXI_MM_IF_SV
