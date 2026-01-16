//==============================================================================
// Class: axi_stream_monitor
// Description: UVM Monitor for AXI-Stream interfaces
//
// Purpose:
//   Monitors AXI-Stream transactions on both TX and RX interfaces.
//   Captures complete frames and broadcasts to analysis ports.
//
// Features:
//   - Monitors AXI-Stream handshaking (tvalid/tready)
//   - Captures complete frames delimited by tlast
//   - Captures tuser status (SOF on TX, frame status on RX)
//   - Separate analysis ports for TX and RX
//   - Frame statistics collection
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_stream_monitor extends uvm_monitor;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_component_utils(axi_stream_monitor)

    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual axi_stream_if vif;
    
    //==========================================================================
    // Analysis Ports
    //==========================================================================
    uvm_analysis_port #(axi_stream_txn) tx_ap;   // TX side monitoring
    uvm_analysis_port #(axi_stream_txn) rx_ap;   // RX side monitoring

    //==========================================================================
    // Configuration
    //==========================================================================
    
    // Enable monitoring for each direction
    bit monitor_tx = 1;
    bit monitor_rx = 1;
    
    // Enable verbose logging
    bit verbose = 0;

    //==========================================================================
    // Statistics
    //==========================================================================
    int tx_frame_count = 0;
    int rx_frame_count = 0;
    int rx_good_frames = 0;
    int rx_bad_frames  = 0;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_stream_monitor", uvm_component parent = null);
        super.new(name, parent);
        tx_ap = new("tx_ap", this);
        rx_ap = new("rx_ap", this);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual axi_stream_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not found for axi_stream_monitor")
        end
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    task run_phase(uvm_phase phase);
        // Wait for reset
        @(posedge vif.aclk);
        while (!vif.aresetn) @(posedge vif.aclk);
        repeat (2) @(posedge vif.aclk);
        
        `uvm_info("AXIS_MON", "Monitor started", UVM_MEDIUM)
        
        // Fork TX and RX monitoring threads
        fork
            if (monitor_tx) monitor_tx_stream();
            if (monitor_rx) monitor_rx_stream();
        join
    endtask

    //==========================================================================
    // Monitor TX Stream (into MAC)
    //==========================================================================
    task monitor_tx_stream();
        axi_stream_txn txn;
        bit in_frame = 0;
        bit [7:0] frame_data[$];  // Use queue for collecting bytes
        
        forever begin
            @(posedge vif.aclk);
            
            // Check for valid transfer
            if (vif.tvalid && vif.tready) begin
                
                // Start new frame if not in one
                if (!in_frame) begin
                    txn = axi_stream_txn::type_id::create("tx_txn");
                    txn.frame_type = 0; // TX
                    txn.start_time = $time;
                    in_frame = 1;
                    frame_data.delete();  // Clear the queue
                    
                    if (verbose) begin
                        `uvm_info("AXIS_MON", "TX: Frame start detected", UVM_HIGH)
                    end
                end
                
                // Capture byte into queue
                frame_data.push_back(vif.tdata);
                
                // Check for end of frame
                if (vif.tlast) begin
                    txn.end_time = $time;
                    txn.transfer_complete = 1;
                    in_frame = 0;
                    
                    // Copy queue to dynamic array
                    txn.data = new[frame_data.size()];
                    foreach (frame_data[i]) txn.data[i] = frame_data[i];
                    
                    // Extract MAC header fields if frame is large enough
                    if (txn.data.size() >= 14) begin
                        for (int i = 0; i < 6; i++) begin
                            txn.dst_mac[5-i] = txn.data[i];
                            txn.src_mac[5-i] = txn.data[i+6];
                        end
                        txn.ether_type = {txn.data[12], txn.data[13]};
                        
                        // Extract payload (everything after header, before CRC if present)
                        txn.payload = new[txn.data.size() - 14];
                        for (int i = 14; i < txn.data.size(); i++) begin
                            txn.payload[i-14] = txn.data[i];
                        end
                    end
                    
                    tx_frame_count++;
                    
                    `uvm_info("AXIS_MON", $sformatf("TX Frame #%0d: %0d bytes", 
                              tx_frame_count, txn.data.size()), UVM_MEDIUM)
                    
                    // Broadcast to analysis port
                    tx_ap.write(txn);
                end
            end
        end
    endtask

    //==========================================================================
    // Monitor RX Stream (from MAC)
    //==========================================================================
    task monitor_rx_stream();
        axi_stream_txn txn;
        bit in_frame = 0;
        bit [7:0] frame_data[$];  // Use queue for collecting bytes
        
        forever begin
            @(posedge vif.aclk);
            
            // Check for valid transfer on RX interface
            if (vif.rx_tvalid && vif.rx_tready) begin
                
                // Start new frame if not in one
                if (!in_frame) begin
                    txn = axi_stream_txn::type_id::create("rx_txn");
                    txn.frame_type = 1; // RX
                    txn.start_time = $time;
                    in_frame = 1;
                    frame_data.delete();  // Clear the queue
                    
                    if (verbose) begin
                        `uvm_info("AXIS_MON", "RX: Frame start detected", UVM_HIGH)
                    end
                end
                
                // Capture byte into queue
                frame_data.push_back(vif.rx_tdata);
                
                // Check for end of frame
                if (vif.rx_tlast) begin
                    txn.end_time = $time;
                    txn.transfer_complete = 1;
                    in_frame = 0;
                    
                    // Copy queue to dynamic array
                    txn.data = new[frame_data.size()];
                    foreach (frame_data[i]) txn.data[i] = frame_data[i];
                    
                    // Capture frame status from tuser
                    // rx_tuser[0] = frame_good, rx_tuser[1] = frame_bad
                    if (vif.rx_tuser[0]) begin
                        txn.frame_good = 1;
                        rx_good_frames++;
                    end
                    if (vif.rx_tuser[1]) begin
                        txn.frame_bad = 1;
                        rx_bad_frames++;
                    end
                    
                    // Extract MAC header fields if frame is large enough
                    if (txn.data.size() >= 14) begin
                        for (int i = 0; i < 6; i++) begin
                            txn.dst_mac[5-i] = txn.data[i];
                            txn.src_mac[5-i] = txn.data[i+6];
                        end
                        txn.ether_type = {txn.data[12], txn.data[13]};
                        
                        // Extract payload
                        txn.payload = new[txn.data.size() - 14];
                        for (int i = 14; i < txn.data.size(); i++) begin
                            txn.payload[i-14] = txn.data[i];
                        end
                    end
                    
                    rx_frame_count++;
                    
                    `uvm_info("AXIS_MON", $sformatf("RX Frame #%0d: %0d bytes, good=%0b, bad=%0b", 
                              rx_frame_count, txn.data.size(), txn.frame_good, txn.frame_bad), 
                              UVM_MEDIUM)
                    
                    // Broadcast to analysis port
                    rx_ap.write(txn);
                end
            end
        end
    endtask

    //==========================================================================
    // Report Phase
    //==========================================================================
    function void report_phase(uvm_phase phase);
        `uvm_info("AXIS_MON", "========== AXI-Stream Monitor Statistics ==========", UVM_LOW)
        `uvm_info("AXIS_MON", $sformatf("  TX Frames Monitored:  %0d", tx_frame_count), UVM_LOW)
        `uvm_info("AXIS_MON", $sformatf("  RX Frames Monitored:  %0d", rx_frame_count), UVM_LOW)
        `uvm_info("AXIS_MON", $sformatf("    RX Good Frames:     %0d", rx_good_frames), UVM_LOW)
        `uvm_info("AXIS_MON", $sformatf("    RX Bad Frames:      %0d", rx_bad_frames), UVM_LOW)
        `uvm_info("AXIS_MON", "====================================================", UVM_LOW)
    endfunction

endclass : axi_stream_monitor
