//==============================================================================
// Interface: axi_stream_if
// Description: AXI-Stream interface for MAC data path
//
// Purpose:
//   Provides signal abstraction for AXI-Stream TX and RX interfaces.
//   Used by UVM agents to drive and monitor Ethernet frame transfers.
//
// Signal Definitions:
//   - tdata[7:0]:  Data byte
//   - tvalid:      Data valid
//   - tready:      Ready for data (backpressure)
//   - tlast:       Last byte of frame (EOF)
//   - tuser:       User sideband (SOF for TX, error for RX)
//
// Clocking:
//   Synchronous to aclk (AXI clock domain)
//
// Usage:
//   - TX: Testbench drives tdata/tvalid/tlast/tuser, DUT drives tready
//   - RX: DUT drives tdata/tvalid/tlast/tuser, testbench drives tready
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//   - Cadence Xcelium
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

interface axi_stream_if #(
    parameter DATA_WIDTH = 8,
    parameter USER_WIDTH = 1
) (
    input logic aclk,       // AXI clock
    input logic aresetn     // AXI reset (active low)
);

    //==========================================================================
    // AXI-Stream TX Signals (Testbench → MAC)
    //==========================================================================
    logic [DATA_WIDTH-1:0] tdata;      // Data
    logic                  tvalid;     // Data valid
    logic                  tready;     // Ready (backpressure)
    logic                  tlast;      // Last byte of frame
    logic [USER_WIDTH-1:0] tuser;      // User sideband
    
    //==========================================================================
    // AXI-Stream RX Signals (MAC → Testbench)
    //==========================================================================
    logic [DATA_WIDTH-1:0] rx_tdata;   // RX Data
    logic                  rx_tvalid;  // RX Data valid
    logic                  rx_tready;  // RX Ready (backpressure from TB)
    logic                  rx_tlast;   // RX Last byte of frame
    logic [1:0]            rx_tuser;   // RX User sideband {frame_bad, frame_good}

    //==========================================================================
    // Clocking Block: Master Driver (TX - driving into DUT)
    // For testbench driving data TO the MAC
    //==========================================================================
    clocking mst_drv_cb @(posedge aclk);
        default input #1step output #1step;
        output tdata;
        output tvalid;
        output tlast;
        output tuser;
        input  tready;
    endclocking

    //==========================================================================
    // Clocking Block: Slave Driver (RX - receiving from DUT)
    // For testbench receiving data FROM the MAC
    //==========================================================================
    clocking slv_drv_cb @(posedge aclk);
        default input #1step output #1step;
        input  tdata;
        input  tvalid;
        input  tlast;
        input  tuser;
        output tready;
    endclocking

    //==========================================================================
    // Clocking Block: Monitor
    // For passive observation of transactions
    //==========================================================================
    clocking mon_cb @(posedge aclk);
        default input #1step output #1step;
        input tdata;
        input tvalid;
        input tready;
        input tlast;
        input tuser;
    endclocking

    //==========================================================================
    // Modports
    //==========================================================================
    
    // Master modport (TX - drives data into DUT)
    modport master (
        clocking mst_drv_cb,
        input aclk,
        input aresetn
    );
    
    // Slave modport (RX - receives data from DUT)
    modport slave (
        clocking slv_drv_cb,
        input aclk,
        input aresetn
    );
    
    // Monitor modport (passive observation)
    modport monitor (
        clocking mon_cb,
        input aclk,
        input aresetn
    );
    
    // DUT TX port (receives data from testbench)
    modport dut_tx (
        input  tdata,
        input  tvalid,
        input  tlast,
        input  tuser,
        output tready
    );
    
    // DUT RX port (sends data to testbench)
    modport dut_rx (
        output tdata,
        output tvalid,
        output tlast,
        output tuser,
        input  tready
    );

    //==========================================================================
    // Reset Initialization
    //==========================================================================
    initial begin
        // TX signals
        tdata  = '0;
        tvalid = 1'b0;
        tready = 1'b0;
        tlast  = 1'b0;
        tuser  = '0;
        // RX signals
        rx_tdata  = '0;
        rx_tvalid = 1'b0;
        rx_tready = 1'b1;  // Default ready to receive
        rx_tlast  = 1'b0;
        rx_tuser  = 2'b00;
    end

    //==========================================================================
    // Task: Wait for reset release
    //==========================================================================
    task automatic wait_reset_done();
        @(posedge aclk);
        while (!aresetn) @(posedge aclk);
        repeat (2) @(posedge aclk);
    endtask

    //==========================================================================
    // Task: Drive idle on master side
    //==========================================================================
    task automatic master_idle();
        @(posedge aclk);
        tvalid <= 1'b0;
        tlast  <= 1'b0;
        tuser  <= '0;
    endtask

    //==========================================================================
    // Task: Assert ready on slave side
    //==========================================================================
    task automatic slave_ready(input bit ready_val = 1'b1);
        @(posedge aclk);
        tready <= ready_val;
    endtask

endinterface : axi_stream_if

