//==============================================================================
// Sequence: axi_stream_tx_frame_seq
// Description: UVM Sequence for sending Ethernet frames via AXI-Stream TX
//
// Purpose:
//   Generates and sends Ethernet frames through the AXI-Stream TX interface
//   to the MAC. Supports various frame sizes and error injection.
//
// Features:
//   - Configurable destination/source MAC addresses
//   - Configurable EtherType
//   - Configurable payload size (auto-generates random data)
//   - Optional CRC generation (MAC can also compute CRC)
//   - Error injection (undersized, no tlast, etc.)
//   - Multiple frames per sequence
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_stream_tx_frame_seq extends mac_base_seq #(axi_stream_txn);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_object_utils(axi_stream_tx_frame_seq)

    //==========================================================================
    // Sequence Configuration
    //==========================================================================
    
    // Frame parameters
    bit [47:0] dst_mac     = 48'hDA_AD_BE_EF_00_01;
    bit [47:0] src_mac     = 48'h5A_5A_5A_5A_00_01;
    bit [15:0] ether_type  = 16'h0800;              // IPv4
    
    // Payload control
    int        payload_size = 46;                    // Minimum payload for Ethernet
    bit        random_payload = 1;                   // Generate random payload
    byte       payload_pattern = 8'hA5;              // Pattern if not random
    
    // CRC control (if MAC should compute, set to 0)
    bit        include_crc = 0;                      // Don't include CRC - let MAC compute
    
    // Frame count
    int        num_frames = 1;
    
    // Inter-frame gap (in clock cycles)
    int        ifg_cycles = 12;
    
    // Error injection
    bit        inject_runt = 0;                      // Send frame < 64 bytes
    bit        inject_no_tlast = 0;                  // Omit tlast on last byte
    bit        inject_early_tlast = 0;               // tlast before full frame

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_stream_tx_frame_seq");
        super.new(name);
    endfunction

    //==========================================================================
    // Body
    //==========================================================================
    task body();
        axi_stream_txn txn;
        
        `uvm_info("AXIS_TX_SEQ", $sformatf("Starting sequence: %0d frames, payload=%0d bytes", 
                  num_frames, payload_size), UVM_MEDIUM)
        
        for (int frame_idx = 0; frame_idx < num_frames; frame_idx++) begin
            // Create transaction
            txn = axi_stream_txn::type_id::create($sformatf("tx_frame_%0d", frame_idx));
            
            // Start transaction
            start_item(txn);
            
            // Configure frame
            txn.dst_mac    = dst_mac;
            txn.src_mac    = src_mac;
            txn.ether_type = ether_type;
            txn.frame_type = 0;  // TX
            
            // Generate payload
            if (inject_runt) begin
                // Runt frame: very small payload (< minimum)
                txn.payload = new[4];  // Will result in < 64 byte frame
                for (int i = 0; i < 4; i++) begin
                    txn.payload[i] = $urandom_range(0, 255);
                end
            end else begin
                // Normal payload
                txn.payload = new[payload_size];
                for (int i = 0; i < payload_size; i++) begin
                    if (random_payload) begin
                        txn.payload[i] = $urandom_range(0, 255);
                    end else begin
                        txn.payload[i] = payload_pattern;
                    end
                end
            end
            
            // Build the complete frame
            txn.build_frame(include_crc);
            
            // Error injection
            txn.inject_no_tlast = inject_no_tlast;
            
            if (inject_early_tlast && txn.data.size() > 20) begin
                // Truncate frame data for early tlast
                txn.data = new[20](txn.data);
            end
            
            // Inter-frame gap
            txn.ifg_cycles = ifg_cycles;
            
            `uvm_info("AXIS_TX_SEQ", $sformatf("Frame %0d/%0d: DA=%h, SA=%h, Type=%h, %0d bytes", 
                      frame_idx + 1, num_frames, dst_mac, src_mac, ether_type, txn.data.size()),
                      UVM_HIGH)
            
            // Complete transaction
            finish_item(txn);
        end
        
        `uvm_info("AXIS_TX_SEQ", $sformatf("Sequence complete: sent %0d frames", num_frames), 
                  UVM_MEDIUM)
    endtask

endclass : axi_stream_tx_frame_seq


//==============================================================================
// Sequence: axi_stream_multi_frame_seq
// Description: Send multiple frames with varying sizes
//==============================================================================

class axi_stream_multi_frame_seq extends uvm_sequence #(axi_stream_txn);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_object_utils(axi_stream_multi_frame_seq)

    //==========================================================================
    // Sequence Configuration
    //==========================================================================
    
    // Frame parameters
    bit [47:0] dst_mac     = 48'hDA_AD_BE_EF_00_01;
    bit [47:0] src_mac     = 48'h5A_5A_5A_5A_00_01;
    bit [15:0] ether_type  = 16'h0800;
    
    // Frame count and size range
    int        num_frames  = 10;
    int        min_payload = 46;
    int        max_payload = 1500;
    
    // CRC control
    bit        include_crc = 0;
    
    // Inter-frame gap
    int        ifg_cycles  = 12;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_stream_multi_frame_seq");
        super.new(name);
    endfunction

    //==========================================================================
    // Body
    //==========================================================================
    task body();
        axi_stream_txn txn;
        int payload_size;
        
        `uvm_info("AXIS_MULTI_SEQ", $sformatf("Starting multi-frame sequence: %0d frames", 
                  num_frames), UVM_MEDIUM)
        
        for (int frame_idx = 0; frame_idx < num_frames; frame_idx++) begin
            // Create transaction
            txn = axi_stream_txn::type_id::create($sformatf("tx_frame_%0d", frame_idx));
            
            // Start transaction
            start_item(txn);
            
            // Configure frame
            txn.dst_mac    = dst_mac;
            txn.src_mac    = src_mac;
            txn.ether_type = ether_type;
            txn.frame_type = 0;  // TX
            
            // Random payload size
            payload_size = $urandom_range(min_payload, max_payload);
            txn.payload = new[payload_size];
            
            for (int i = 0; i < payload_size; i++) begin
                txn.payload[i] = $urandom_range(0, 255);
            end
            
            // Build frame
            txn.build_frame(include_crc);
            
            // Inter-frame gap
            txn.ifg_cycles = ifg_cycles;
            
            `uvm_info("AXIS_MULTI_SEQ", $sformatf("Frame %0d/%0d: %0d bytes payload", 
                      frame_idx + 1, num_frames, payload_size), UVM_HIGH)
            
            // Complete transaction
            finish_item(txn);
        end
        
        `uvm_info("AXIS_MULTI_SEQ", $sformatf("Multi-frame sequence complete: sent %0d frames", 
                  num_frames), UVM_MEDIUM)
    endtask

endclass : axi_stream_multi_frame_seq


//==============================================================================
// Sequence: axi_stream_stress_seq
// Description: Stress test with back-to-back frames
//==============================================================================

class axi_stream_stress_seq extends uvm_sequence #(axi_stream_txn);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_object_utils(axi_stream_stress_seq)

    //==========================================================================
    // Sequence Configuration
    //==========================================================================
    
    // Frame parameters
    bit [47:0] dst_mac     = 48'hDA_AD_BE_EF_00_01;
    bit [47:0] src_mac     = 48'h5A_5A_5A_5A_00_01;
    
    // Stress parameters
    int        num_frames  = 100;
    int        fixed_payload = 64;    // Fixed small payload for speed
    int        ifg_cycles  = 1;       // Minimal IFG

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_stream_stress_seq");
        super.new(name);
    endfunction

    //==========================================================================
    // Body
    //==========================================================================
    task body();
        axi_stream_txn txn;
        
        `uvm_info("AXIS_STRESS_SEQ", $sformatf("Starting stress sequence: %0d frames, min IFG", 
                  num_frames), UVM_MEDIUM)
        
        for (int frame_idx = 0; frame_idx < num_frames; frame_idx++) begin
            // Create transaction
            txn = axi_stream_txn::type_id::create($sformatf("stress_frame_%0d", frame_idx));
            
            // Start transaction
            start_item(txn);
            
            // Configure frame
            txn.dst_mac    = dst_mac;
            txn.src_mac    = src_mac;
            txn.ether_type = 16'h0800;
            txn.frame_type = 0;
            
            // Fixed payload
            txn.payload = new[fixed_payload];
            for (int i = 0; i < fixed_payload; i++) begin
                txn.payload[i] = frame_idx[7:0] + i[7:0];  // Pattern with frame index
            end
            
            // Build frame (no CRC - MAC computes)
            txn.build_frame(0);
            
            // Minimal IFG
            txn.ifg_cycles = ifg_cycles;
            
            // Complete transaction
            finish_item(txn);
        end
        
        `uvm_info("AXIS_STRESS_SEQ", $sformatf("Stress sequence complete: sent %0d frames", 
                  num_frames), UVM_MEDIUM)
    endtask

endclass : axi_stream_stress_seq
