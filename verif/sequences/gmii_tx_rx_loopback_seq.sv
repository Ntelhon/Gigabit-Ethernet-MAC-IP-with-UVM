//==============================================================================
// Sequence: gmii_tx_rx_loopback_seq
// Description: Loopback sequence that captures GMII TX and reinjects to GMII RX
//
// Purpose:
//   Monitors frames transmitted by the MAC on the GMII TX interface,
//   captures them, and reinjects them into the GMII RX interface.
//   This enables full TX-RX loopback testing without external PHY.
//
// Data Flow:
//   1. TX frame sent via AXI-Stream TX interface
//   2. MAC processes and outputs on GMII TX (with preamble + CRC)
//   3. This sequence captures the complete GMII TX frame
//   4. Reinjects the captured frame to GMII RX
//   5. MAC receives via GMII RX and outputs on AXI-Stream RX
//
// Usage:
//   Run this sequence in parallel with mac_tx_frame_seq to create
//   a loopback test environment.
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_tx_rx_loopback_seq extends uvm_sequence #(gmii_frame);

    `uvm_object_utils(gmii_tx_rx_loopback_seq)

    //==========================================================================
    // Configuration
    //==========================================================================
    
    // Number of frames to loopback
    int unsigned num_frames = 1;
    
    // Timeout waiting for TX frame (in clock cycles)
    int unsigned timeout_cycles = 100000;
    
    // Add inter-frame gap before reinjection
    int unsigned reinjection_delay = 12;  // IFG in bytes worth of clocks
    
    // Virtual interfaces
    virtual gmii_if gmii_vif;

    //==========================================================================
    // Internal Storage - raw byte arrays instead of gmii_frame
    //==========================================================================
    
    // Queue to store captured TX frames as raw bytes
    typedef logic [7:0] frame_bytes_t[];
    frame_bytes_t tx_frame_queue[$];
    
    // Flag to stop capture
    bit stop_capture = 0;

    //==========================================================================
    // Constructor
    //==========================================================================
    
    function new(string name = "gmii_tx_rx_loopback_seq");
        super.new(name);
    endfunction

    //==========================================================================
    // Body
    //==========================================================================
    
    virtual task body();
        frame_bytes_t captured_bytes;
        int frames_captured = 0;
        int frames_reinjected = 0;
        
        // Get virtual interface
        if (!uvm_config_db#(virtual gmii_if)::get(null, "*", "gmii_vif", gmii_vif)) begin
            `uvm_fatal("LOOPBACK_SEQ", "Failed to get gmii_vif from config_db")
        end
        
        `uvm_info("LOOPBACK_SEQ", $sformatf("Starting loopback for %0d frames", 
                  num_frames), UVM_MEDIUM)
        
        // Fork capture and reinjection processes
        fork
            // Capture TX frames
            begin
                while (frames_captured < num_frames && !stop_capture) begin
                    capture_tx_frame(captured_bytes);
                    if (captured_bytes.size() > 0) begin
                        tx_frame_queue.push_back(captured_bytes);
                        frames_captured++;
                        `uvm_info("LOOPBACK_SEQ", $sformatf("Captured TX frame %0d, len=%0d", 
                                  frames_captured, captured_bytes.size()), UVM_HIGH)
                    end
                end
            end
            
            // Reinject to RX
            begin
                while (frames_reinjected < num_frames) begin
                    // Wait for frame in queue
                    while (tx_frame_queue.size() == 0) begin
                        @(posedge gmii_vif.tx_clk);
                        if (stop_capture && tx_frame_queue.size() == 0) break;
                    end
                    
                    if (tx_frame_queue.size() > 0) begin
                        captured_bytes = tx_frame_queue.pop_front();
                        
                        // Inter-frame gap before reinjection
                        repeat (reinjection_delay) @(posedge gmii_vif.rx_clk);
                        
                        // Reinject to RX
                        reinject_to_rx(captured_bytes);
                        frames_reinjected++;
                        `uvm_info("LOOPBACK_SEQ", $sformatf("Reinjected frame %0d to RX", 
                                  frames_reinjected), UVM_HIGH)
                    end
                end
            end
        join
        
        `uvm_info("LOOPBACK_SEQ", $sformatf("Loopback complete: captured=%0d, reinjected=%0d", 
                  frames_captured, frames_reinjected), UVM_MEDIUM)
    endtask

    //==========================================================================
    // Capture TX Frame
    // Monitors GMII TX and captures complete frame including preamble + CRC
    //==========================================================================
    
    virtual task capture_tx_frame(output frame_bytes_t frame_bytes);
        logic [7:0] frame_data[$];
        int timeout_cnt = 0;
        
        frame_data.delete();
        
        `uvm_info("LOOPBACK_SEQ", "Waiting for TX frame (tx_en)...", UVM_MEDIUM)
        
        // Wait for tx_en to assert (start of preamble)
        // Use direct signal access instead of clocking block for better reliability
        while (!gmii_vif.tx_en) begin
            @(posedge gmii_vif.tx_clk);
            timeout_cnt++;
            if (timeout_cnt > timeout_cycles) begin
                `uvm_warning("LOOPBACK_SEQ", "Timeout waiting for TX frame")
                frame_bytes = new[0];
                return;
            end
        end
        
        `uvm_info("LOOPBACK_SEQ", "TX frame detected, capturing...", UVM_MEDIUM)
        
        // Capture preamble + SFD + frame + CRC while tx_en is high
        // Use direct signal access for reliability
        while (gmii_vif.tx_en) begin
            frame_data.push_back(gmii_vif.txd);
            @(posedge gmii_vif.tx_clk);
        end
        
        `uvm_info("LOOPBACK_SEQ", $sformatf("Captured %0d bytes", frame_data.size()), UVM_MEDIUM)
        
        // Convert queue to dynamic array
        if (frame_data.size() > 0) begin
            frame_bytes = new[frame_data.size()];
            foreach (frame_data[i]) begin
                frame_bytes[i] = frame_data[i];
            end
        end else begin
            frame_bytes = new[0];
        end
    endtask

    //==========================================================================
    // Reinject to RX
    // Sends captured frame (with preamble + CRC) to GMII RX interface
    //==========================================================================
    
    virtual task reinject_to_rx(input frame_bytes_t frame_bytes);
        if (frame_bytes.size() == 0) begin
            `uvm_warning("LOOPBACK_SEQ", "Empty frame, skipping reinjection")
            return;
        end
        
        `uvm_info("LOOPBACK_SEQ", $sformatf("Reinjecting %0d bytes to RX", frame_bytes.size()), UVM_MEDIUM)
        
        // Drive each byte on RX interface using direct access
        for (int i = 0; i < frame_bytes.size(); i++) begin
            @(posedge gmii_vif.rx_clk);
            gmii_vif.rxd   <= frame_bytes[i];
            gmii_vif.rx_dv <= 1'b1;
            gmii_vif.rx_er <= 1'b0;
        end
        
        // Deassert rx_dv
        @(posedge gmii_vif.rx_clk);
        gmii_vif.rx_dv <= 1'b0;
        gmii_vif.rxd   <= 8'h00;
    endtask

    //==========================================================================
    // Stop Capture
    //==========================================================================
    
    virtual function void stop();
        stop_capture = 1;
    endfunction

endclass : gmii_tx_rx_loopback_seq