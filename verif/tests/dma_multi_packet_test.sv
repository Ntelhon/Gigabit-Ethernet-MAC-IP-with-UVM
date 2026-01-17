//==============================================================================
// File: dma_multi_packet_test.sv
// Description: DMA multiple packet burst verification test
//==============================================================================

class dma_multi_packet_test extends dma_base_test;

    `uvm_component_utils(dma_multi_packet_test)

    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int burst_size = 8;  // Number of packets to queue at once
    int num_bursts = 2;  // Number of bursts

    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_multi_packet_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // Run Phase
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        bit [7:0] pkt_data[$];
        bit [31:0] tail, head;
        int total_tx = 0;
        int total_rx = 0;
        
        phase.raise_objection(this);
        super.run_phase(phase);
        
        `uvm_info("TEST", "========================================", UVM_NONE)
        `uvm_info("TEST", "    DMA Multiple Packet Burst Test", UVM_NONE)
        `uvm_info("TEST", "========================================", UVM_NONE)
        
        // Initialize
        #100ns;
        
        // Configure DMA
        configure_dma(.enable_tx(1), .enable_rx(1), .enable_irq(1));
        setup_rx_buffers(desc_count);
        
        // ========== TX Burst Test ==========
        `uvm_info("TEST", "--- TX Burst Test ---", UVM_MEDIUM)
        
        for (int burst = 0; burst < num_bursts; burst++) begin
            `uvm_info("TEST", $sformatf("TX Burst %0d: queuing %0d packets", burst+1, burst_size), UVM_MEDIUM)
            
            // Queue all packets in burst
            env.axi_lite_agt.read(32'h0220, tail);
            
            for (int i = 0; i < burst_size; i++) begin
                int pkt_len = 64 + (i * 64);  // Varying sizes
                if (pkt_len > 1518) pkt_len = 1518;
                
                generate_packet(pkt_len, pkt_data);
                pkt_data[20] = (burst * burst_size + i)[7:0];
                
                queue_tx_packet(pkt_data, (tail + i) % desc_count);
            end
            
            // Update tail once for entire burst
            tail = (tail + burst_size) % desc_count;
            env.axi_lite_agt.write(32'h0220, tail);
            
            total_tx += burst_size;
            
            // Wait for burst completion
            #20us;
            
            // Check head pointer progress
            env.axi_lite_agt.read(32'h021C, head);
            `uvm_info("TEST", $sformatf("TX head=%0d tail=%0d", head, tail), UVM_MEDIUM)
        end
        
        // ========== RX Burst Test ==========
        `uvm_info("TEST", "--- RX Burst Test ---", UVM_MEDIUM)
        
        for (int burst = 0; burst < num_bursts; burst++) begin
            `uvm_info("TEST", $sformatf("RX Burst %0d: injecting %0d frames", burst+1, burst_size), UVM_MEDIUM)
            
            // Inject frames rapidly
            for (int i = 0; i < burst_size; i++) begin
                gmii_frame frame;
                int pkt_len = 64 + (i * 32);
                if (pkt_len > 1518) pkt_len = 1518;
                
                frame = gmii_frame::type_id::create("rx_frame");
                frame.dst_mac = 48'h001122334455;
                frame.src_mac = 48'hAABBCCDDEEFF;
                frame.ether_type = 16'h0800;
                frame.payload = new[pkt_len - 18];
                foreach (frame.payload[j]) frame.payload[j] = j[7:0];
                frame.has_fcs = 1;
                
                env.gmii_agt.send_frame(frame);
                #500ns;  // Minimal gap
            end
            
            total_rx += burst_size;
            
            // Wait for processing
            #20us;
            
            // Check RX head
            env.axi_lite_agt.read(32'h024C, head);
            `uvm_info("TEST", $sformatf("RX head=%0d", head), UVM_MEDIUM)
        end
        
        // Final verification
        #10us;
        verify_statistics(total_tx, total_rx);
        
        phase.drop_objection(this);
    endtask

    //--------------------------------------------------------------------------
    // Verify Statistics
    //--------------------------------------------------------------------------
    virtual task verify_statistics(int expected_tx, int expected_rx);
        bit [31:0] tx_cnt, rx_cnt;
        
        env.axi_lite_agt.read(32'h0260, tx_cnt);
        env.axi_lite_agt.read(32'h0270, rx_cnt);
        
        `uvm_info("TEST", "========================================", UVM_MEDIUM)
        `uvm_info("TEST", $sformatf("Expected TX: %0d  Actual: %0d", expected_tx, tx_cnt), UVM_MEDIUM)
        `uvm_info("TEST", $sformatf("Expected RX: %0d  Actual: %0d", expected_rx, rx_cnt), UVM_MEDIUM)
        `uvm_info("TEST", "========================================", UVM_MEDIUM)
        
        if (tx_cnt != expected_tx)
            `uvm_error("TEST", "TX count mismatch")
        if (rx_cnt != expected_rx)
            `uvm_error("TEST", "RX count mismatch")
    endtask

endclass : dma_multi_packet_test
