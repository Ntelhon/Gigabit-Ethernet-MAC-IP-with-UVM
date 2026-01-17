//==============================================================================
// File: dma_tx_rx_test.sv
// Description: DMA bidirectional TX and RX verification test
//==============================================================================

class dma_tx_rx_test extends dma_base_test;

    `uvm_component_utils(dma_tx_rx_test)

    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int num_tx_packets = 4;
    int num_rx_packets = 4;
    int packet_length = 256;

    //--------------------------------------------------------------------------
    // Packet Storage
    //--------------------------------------------------------------------------
    bit [7:0] tx_sent_packets[$][$];
    bit [7:0] rx_received_packets[$][$];

    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_tx_rx_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // Run Phase
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        super.run_phase(phase);
        
        `uvm_info("TEST", "========================================", UVM_NONE)
        `uvm_info("TEST", "    DMA TX-RX Bidirectional Test", UVM_NONE)
        `uvm_info("TEST", "========================================", UVM_NONE)
        
        // Initialize
        #100ns;
        
        // Configure DMA (both TX and RX)
        configure_dma(.enable_tx(1), .enable_rx(1), .enable_irq(1));
        
        // Setup RX buffers
        setup_rx_buffers(desc_count);
        
        // Run TX and RX traffic in parallel
        fork
            run_tx_traffic();
            run_rx_traffic();
        join
        
        // Wait for completions
        #20us;
        
        // Verify statistics
        verify_all_stats();
        
        #10us;
        phase.drop_objection(this);
    endtask

    //--------------------------------------------------------------------------
    // TX Traffic
    //--------------------------------------------------------------------------
    virtual task run_tx_traffic();
        bit [7:0] pkt_data[$];
        bit [31:0] tail;
        
        `uvm_info("TEST", "Starting TX traffic", UVM_MEDIUM)
        
        for (int i = 0; i < num_tx_packets; i++) begin
            // Generate unique packet
            generate_packet(packet_length, pkt_data);
            pkt_data[20] = i[7:0];  // Unique ID in payload
            
            // Store for verification
            tx_sent_packets.push_back(pkt_data);
            
            // Get tail
            env.axi_lite_agt.read(32'h0220, tail);
            
            // Queue packet
            queue_tx_packet(pkt_data, tail);
            
            // Update tail
            tail = (tail + 1) % desc_count;
            env.axi_lite_agt.write(32'h0220, tail);
            
            `uvm_info("TEST", $sformatf("TX: Queued packet %0d", i+1), UVM_HIGH)
            
            // Inter-packet delay
            #2us;
        end
        
        // Wait for all TX completions
        for (int i = 0; i < num_tx_packets; i++) begin
            wait_tx_complete(5000);
        end
        
        `uvm_info("TEST", "TX traffic complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // RX Traffic
    //--------------------------------------------------------------------------
    virtual task run_rx_traffic();
        gmii_frame frame;
        
        `uvm_info("TEST", "Starting RX traffic injection", UVM_MEDIUM)
        
        for (int i = 0; i < num_rx_packets; i++) begin
            // Create frame
            frame = gmii_frame::type_id::create("rx_frame");
            frame.dst_mac = 48'h001122334455;
            frame.src_mac = 48'hBBCCDDEEFF00 + i;
            frame.ether_type = 16'h0800;
            frame.payload = new[packet_length - 18];
            for (int j = 0; j < frame.payload.size(); j++) begin
                frame.payload[j] = j[7:0];
            end
            frame.payload[6] = i[7:0];  // Unique ID
            frame.has_fcs = 1;
            
            // Send
            env.gmii_agt.send_frame(frame);
            `uvm_info("TEST", $sformatf("RX: Injected frame %0d", i+1), UVM_HIGH)
            
            // Inter-frame delay
            #3us;
        end
        
        // Wait for RX completions
        #10us;
        for (int i = 0; i < num_rx_packets; i++) begin
            wait_rx_complete(5000);
        end
        
        `uvm_info("TEST", "RX traffic injection complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Verify All Statistics
    //--------------------------------------------------------------------------
    virtual task verify_all_stats();
        bit [31:0] tx_pkt_cnt, tx_byte_cnt;
        bit [31:0] rx_pkt_cnt, rx_byte_cnt;
        int errors = 0;
        
        env.axi_lite_agt.read(32'h0260, tx_pkt_cnt);
        env.axi_lite_agt.read(32'h0264, tx_byte_cnt);
        env.axi_lite_agt.read(32'h0270, rx_pkt_cnt);
        env.axi_lite_agt.read(32'h0274, rx_byte_cnt);
        
        `uvm_info("TEST", "========================================", UVM_MEDIUM)
        `uvm_info("TEST", $sformatf("TX: packets=%0d bytes=%0d", tx_pkt_cnt, tx_byte_cnt), UVM_MEDIUM)
        `uvm_info("TEST", $sformatf("RX: packets=%0d bytes=%0d", rx_pkt_cnt, rx_byte_cnt), UVM_MEDIUM)
        `uvm_info("TEST", "========================================", UVM_MEDIUM)
        
        if (tx_pkt_cnt != num_tx_packets) begin
            `uvm_error("TEST", $sformatf("TX packet count mismatch: expected=%0d got=%0d", 
                num_tx_packets, tx_pkt_cnt))
            errors++;
        end
        
        if (rx_pkt_cnt != num_rx_packets) begin
            `uvm_error("TEST", $sformatf("RX packet count mismatch: expected=%0d got=%0d", 
                num_rx_packets, rx_pkt_cnt))
            errors++;
        end
        
        if (errors == 0) begin
            `uvm_info("TEST", "All statistics verified successfully", UVM_MEDIUM)
        end
    endtask

endclass : dma_tx_rx_test
