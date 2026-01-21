//==============================================================================
// Module: tb_top
// Description: UVM testbench top module for Gigabit Ethernet MAC IP
//
// Purpose:
//   Top-level testbench that instantiates the DUT, interfaces, and runs
//   UVM tests. Provides clock/reset generation and interface connections.
//
// Components:
//   - Clock generators (125 MHz GMII, 100 MHz AXI)
//   - Reset generation
//   - DUT instantiation (mac_top)
//   - Interface instantiation (GMII, AXI-Lite)
//   - UVM configuration and test launch
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//   - No DPI
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`timescale 1ns/1ps

module tb_top;

    //==========================================================================
    // Import Packages
    //==========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import gmii_agent_pkg::*;
    import axi_lite_agent_pkg::*;
    import axi_stream_agent_pkg::*;
    import axi_mm_agent_pkg::*;
    import mac_scoreboard_pkg::*;
    import dma_scoreboard_pkg::*;
    import eth_env_pkg::*;
    import eth_test_pkg::*;

    //==========================================================================
    // Clock and Reset Signals
    //==========================================================================
    
    // GMII clock (125 MHz for 1 Gbps)
    logic gmii_clk;
    
    // AXI-Lite clock (100 MHz typical)
    logic axi_clk;
    
    // Resets (active high)
    logic gmii_rst;
    logic axi_rst;

    //==========================================================================
    // Clock Generation
    //==========================================================================
    
    // GMII clock: 125 MHz (8 ns period)
    initial begin
        gmii_clk = 0;
        forever #4ns gmii_clk = ~gmii_clk;
    end
    
    // AXI clock: 100 MHz (10 ns period)
    initial begin
        axi_clk = 0;
        forever #5ns axi_clk = ~axi_clk;
    end

    //==========================================================================
    // Reset Generation
    //==========================================================================
    
    initial begin
        gmii_rst = 1;
        axi_rst  = 1;
        
        // Hold reset for 100 ns
        #100ns;
        
        // Deassert resets synchronously
        @(posedge gmii_clk);
        gmii_rst = 0;
        
        @(posedge axi_clk);
        axi_rst = 0;
    end

    //==========================================================================
    // Interface Instantiation
    //==========================================================================
    
    // GMII interface
    gmii_if gmii_vif(
        .tx_clk(gmii_clk),
        .rx_clk(gmii_clk)
    );
    
    // AXI-Lite interface
    axi_lite_if #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) axi_vif(
        .aclk(axi_clk),
        .aresetn(~axi_rst)
    );

    // AXI-Stream interface (for TX and RX)
    axi_stream_if axis_vif(
        .aclk(axi_clk),
        .aresetn(~axi_rst)
    );

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    mac_top #(
        .AXI_ADDR_WIDTH(32),
        .AXI_DATA_WIDTH(32),
        .TX_FIFO_DEPTH(12),   // 2^12 = 4096 entries for store-and-forward (jumbo frames)
        .RX_FIFO_DEPTH(12)    // 2^12 = 4096 entries for store-and-forward
    ) dut (
        //------------------------------------------------------------------
        // System Clock Domain
        //------------------------------------------------------------------
        .sys_clk        (axi_clk),
        .sys_rst_n      (~axi_rst),
        
        //------------------------------------------------------------------
        // GMII TX Clock Domain
        //------------------------------------------------------------------
        .gtx_clk        (gmii_clk),
        .gtx_rst_n      (~gmii_rst),
        
        //------------------------------------------------------------------
        // GMII RX Clock Domain
        //------------------------------------------------------------------
        .rx_clk         (gmii_clk),  // Using same clock for simplicity
        .rx_rst_n       (~gmii_rst),
        
        //------------------------------------------------------------------
        // AXI-Lite Register Interface
        //------------------------------------------------------------------
        
        // Write address channel
        .s_axi_awaddr   (axi_vif.awaddr),
        .s_axi_awvalid  (axi_vif.awvalid),
        .s_axi_awready  (axi_vif.awready),
        
        // Write data channel
        .s_axi_wdata    (axi_vif.wdata),
        .s_axi_wstrb    (axi_vif.wstrb),
        .s_axi_wvalid   (axi_vif.wvalid),
        .s_axi_wready   (axi_vif.wready),
        
        // Write response channel
        .s_axi_bresp    (axi_vif.bresp),
        .s_axi_bvalid   (axi_vif.bvalid),
        .s_axi_bready   (axi_vif.bready),
        
        // Read address channel
        .s_axi_araddr   (axi_vif.araddr),
        .s_axi_arvalid  (axi_vif.arvalid),
        .s_axi_arready  (axi_vif.arready),
        
        // Read data channel
        .s_axi_rdata    (axi_vif.rdata),
        .s_axi_rresp    (axi_vif.rresp),
        .s_axi_rvalid   (axi_vif.rvalid),
        .s_axi_rready   (axi_vif.rready),
        
        //------------------------------------------------------------------
        // TX Data Interface
        //------------------------------------------------------------------
        .tx_axis_tdata  (axis_vif.tdata),
        .tx_axis_tvalid (axis_vif.tvalid),
        .tx_axis_tlast  (axis_vif.tlast),
        .tx_axis_tuser  (axis_vif.tuser),
        .tx_axis_tready (axis_vif.tready),
        
        //------------------------------------------------------------------
        // RX Data Interface
        //------------------------------------------------------------------
        .rx_axis_tdata  (axis_vif.rx_tdata),
        .rx_axis_tvalid (axis_vif.rx_tvalid),
        .rx_axis_tlast  (axis_vif.rx_tlast),
        .rx_axis_tuser  (axis_vif.rx_tuser),
        .rx_axis_tready (axis_vif.rx_tready),
        
        //------------------------------------------------------------------
        // GMII TX Interface (MAC to PHY)
        //------------------------------------------------------------------
        .gmii_txd       (gmii_vif.txd),
        .gmii_tx_en     (gmii_vif.tx_en),
        .gmii_tx_er     (gmii_vif.tx_er),
        
        //------------------------------------------------------------------
        // GMII RX Interface (PHY to MAC)
        //------------------------------------------------------------------
        .gmii_rxd       (gmii_vif.rxd),
        .gmii_rx_dv     (gmii_vif.rx_dv),
        .gmii_rx_er     (gmii_vif.rx_er),
        
        //------------------------------------------------------------------
        // GMII Control Signals
        //------------------------------------------------------------------
        .gmii_col       (1'b0),     // No collision in tests
        .gmii_crs       (1'b0),     // No carrier sense in tests
        
        //------------------------------------------------------------------
        // Interrupt
        //------------------------------------------------------------------
        .irq            ()  // Not connected for basic tests
    );

    //==========================================================================
    // Interface Binding to UVM Config DB
    //==========================================================================
    
    initial begin
        // Set GMII interface (updated path for hierarchical env)
        uvm_config_db#(virtual gmii_if)::set(
            null, "uvm_test_top.env.mac_env.gmii_agt*", "vif", gmii_vif
        );
        
        // Set AXI-Lite interface (updated path - now at top level)
        uvm_config_db#(virtual axi_lite_if#(32,32))::set(
            null, "uvm_test_top.env.axi_lite_agt*", "vif", axi_vif
        );
        
        // Also set at top level for flexibility
        uvm_config_db#(virtual gmii_if)::set(
            null, "*", "gmii_vif", gmii_vif
        );
        
        uvm_config_db#(virtual axi_lite_if#(32,32))::set(
            null, "*", "axi_vif", axi_vif
        );
        
        // Set AXI-Stream interface (updated path for MAC sub-env)
        uvm_config_db#(virtual axi_stream_if)::set(
            null, "uvm_test_top.env.mac_env.axis_agt*", "vif", axis_vif
        );
        
        uvm_config_db#(virtual axi_stream_if)::set(
            null, "*", "axis_vif", axis_vif
        );
    end

    //==========================================================================
    // UVM Test Launch
    //==========================================================================
    
    initial begin
        // Print simulation start
        $display("==============================================================================");
        $display("Gigabit Ethernet MAC UVM Testbench");
        $display("Simulator: Vivado xsim");
        $display("UVM Version: 1.2");
        $display("==============================================================================");
        
        // Run UVM test
        run_test();
    end

    //==========================================================================
    // Simulation Timeout (Safety)
    //==========================================================================
    
    initial begin
        #10ms;
        $display("==============================================================================");
        $display("SIMULATION TIMEOUT - 10ms reached");
        $display("==============================================================================");
        $finish;
    end

    //==========================================================================
    // Waveform Dumping (Optional, controlled by plusarg)
    //==========================================================================
    
    initial begin
        // For VCD dumping (if needed instead of WDB)
        // $dumpfile("mac_sim.vcd");
        // $dumpvars(0, tb_top);
    end

    //==========================================================================
    // GMII TX Monitor (Debug - enabled with +define+DEBUG)
    //==========================================================================
    `ifdef DEBUG
    int gmii_byte_cnt = 0;
    bit in_gmii_frame = 0;
    
    always @(posedge gmii_clk) begin
        if (gmii_vif.tx_en) begin
            if (!in_gmii_frame) begin
                $display("[GMII_TX] @%0t: FRAME START", $time);
                in_gmii_frame = 1;
                gmii_byte_cnt = 0;
            end
            $display("[GMII_TX] @%0t: TX_EN=1 TXD=%02h (byte %0d)", 
                     $time, gmii_vif.txd, gmii_byte_cnt);
            gmii_byte_cnt++;
        end else if (in_gmii_frame) begin
            $display("[GMII_TX] @%0t: FRAME END (total %0d bytes)", $time, gmii_byte_cnt);
            in_gmii_frame = 0;
        end
    end
    `endif

endmodule : tb_top
