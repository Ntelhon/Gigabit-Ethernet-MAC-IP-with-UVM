//==============================================================================
// Sequence: axi_stream_tx_seq
// Description: Send data over AXI-Stream interface
//==============================================================================

class axi_stream_tx_seq extends uvm_sequence #(axi_stream_txn);
    
    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_object_utils(axi_stream_tx_seq)

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
    function new(string name = "axi_stream_tx_seq");
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

endclass : axi_stream_tx_seq
