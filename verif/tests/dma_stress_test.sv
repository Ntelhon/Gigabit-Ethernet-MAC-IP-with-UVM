//==============================================================================
// File: dma_stress_test.sv
// Description: DMA stress test with high traffic and edge cases
//==============================================================================

class dma_stress_test extends dma_base_test;

    `uvm_component_utils(dma_stress_test)

    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int num_tx_packets = 50;
    int num_rx_packets = 50;
    int min_packet_len = 64;
    int max_packet_len = 1518;
    int test_duration_us = 100000;

    //--------------------------------------------------------------------------
    // Statistics
    //--------------------------------------------------------------------------
    int tx_queued = 0;
    int tx_completed = 0;
    int rx_injected = 0;
    int rx_completed = 0;

    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_stress_test", uvm_component parent = null);
        super.new(name, parent);
        test_timeout = 200000;  // Extended timeout
    endfunction

    //--------------------------------------------------------------------------
    // Run Phase
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        super.run_phase(phase);
        
        `uvm_info("TEST", "========================================", UVM_NONE)
        `uvm_info("TEST", "    DMA Stress Test Starting", UVM_NONE)
        `uvm_info("TEST", $sformatf("    TX packets: %0d", num_tx_packets), UVM_NONE)
        `uvm_info("TEST", $sformatf("    RX packets: %0d", num_rx_packets), UVM_NONE)
        `uvm_info("TEST", "========================================", UVM_NONE)
        
        // Initialize
        #100ns;
        
        // Configure DMA with full ring
        configure_dma(.enable_tx(1), .enable_rx(1), .enable_irq(1));
        setup_rx_buffers(desc_count);
        
        // Run stress traffic
        fork
            tx_stress_traffic();
            rx_stress_traffic();
            monitor_progress();
        join_any
        
        // Wait for completion
        #50us;
        
        // Final report
        report_results();
        
        phase.drop_objection(this);
    endtask

    //--------------------------------------------------------------------------
    // TX Stress Traffic
    //--------------------------------------------------------------------------
    virtual task tx_stress_traffic();
        bit [7:0] pkt_data[$];
        bit [31:0] tail, head;
        int pkt_len;
        
        while (tx_queued < num_tx_packets) begin
            // Check for available descriptor space
            env.axi_lite_agt.read(32'h021C, head);
            env.axi_lite_agt.read(32'h0220, tail);
            
            // Calculate available space
            int available = (head > tail) ? (head - tail - 1) : (desc_count - tail + head - 1);
            
            if (available > 0) begin
                // Generate random packet
                pkt_len = $urandom_range(min_packet_len, max_packet_len);
                generate_packet(pkt_len, pkt_data);
                pkt_data[20] = tx_queued[7:0];
                pkt_data[21] = tx_queued[15:8];
                
                // Queue packet
                queue_tx_packet(pkt_data, tail);
                
                // Update tail
                tail = (tail + 1) % desc_count;
                env.axi_lite_agt.write(32'h0220, tail);
                
                tx_queued++;
                
                if (tx_queued % 10 == 0)
                    `uvm_info("TEST", $sformatf("TX: Queued %0d packets", tx_queued), UVM_MEDIUM)
            end
            
            // Random delay
            #($urandom_range(100, 500) * 1ns);
        end
        
        `uvm_info("TEST", $sformatf("TX: All %0d packets queued", tx_queued), UVM_MEDIUM)
        
        // Wait for all TX to complete
        while (tx_completed < tx_queued) begin
            env.axi_lite_agt.read(32'h021C, head);
            tx_completed = head;
            #1us;
        end
    endtask

    //--------------------------------------------------------------------------
    // RX Stress Traffic
    //--------------------------------------------------------------------------
    virtual task rx_stress_traffic();
        gmii_frame frame;
        int pkt_len;
        
        while (rx_injected < num_rx_packets) begin
            // Generate random frame
            pkt_len = $urandom_range(min_packet_len, max_packet_len);
            
            frame = gmii_frame::type_id::create("rx_frame");
            frame.dst_mac = 48'h001122334455;
            frame.src_mac = 48'hAABB00000000 | rx_injected;
            frame.ether_type = 16'h0800;
            frame.payload = new[pkt_len - 18];
            foreach (frame.payload[i]) frame.payload[i] = $urandom;
            frame.has_fcs = 1;
            frame.inject_fcs_error = 0;
            
            // Inject frame
            env.gmii_agt.send_frame(frame);
            rx_injected++;
            
            if (rx_injected % 10 == 0)
                `uvm_info("TEST", $sformatf("RX: Injected %0d frames", rx_injected), UVM_MEDIUM)
            
            // Random inter-frame gap
            #($urandom_range(500, 2000) * 1ns);
        end
        
        `uvm_info("TEST", $sformatf("RX: All %0d frames injected", rx_injected), UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Monitor Progress
    //--------------------------------------------------------------------------
    virtual task monitor_progress();
        bit [31:0] tx_head, rx_head;
        int timeout = test_duration_us;
        int prev_tx = 0, prev_rx = 0;
        int stall_count = 0;
        
        while (timeout > 0) begin
            #10us;
            timeout -= 10;
            
            env.axi_lite_agt.read(32'h021C, tx_head);
            env.axi_lite_agt.read(32'h024C, rx_head);
            
            tx_completed = tx_head;
            rx_completed = rx_head;
            
            // Check for stalls
            if (tx_completed == prev_tx && rx_completed == prev_rx) begin
                stall_count++;
                if (stall_count > 100) begin
                    `uvm_warning("TEST", $sformatf("Possible stall: TX=%0d RX=%0d", tx_completed, rx_completed))
                    stall_count = 0;
                end
            end else begin
                stall_count = 0;
            end
            
            prev_tx = tx_completed;
            prev_rx = rx_completed;
            
            // Check if done
            if (tx_completed >= tx_queued && rx_completed >= rx_injected) begin
                `uvm_info("TEST", "All traffic completed", UVM_MEDIUM)
                return;
            end
        end
        
        `uvm_warning("TEST", "Monitor timeout - test may not have completed")
    endtask

    //--------------------------------------------------------------------------
    // Report Results
    //--------------------------------------------------------------------------
    virtual task report_results();
        bit [31:0] tx_pkt_cnt, tx_byte_cnt;
        bit [31:0] rx_pkt_cnt, rx_byte_cnt;
        bit [31:0] status, irq_status;
        int errors = 0;
        
        env.axi_lite_agt.read(32'h0204, status);
        env.axi_lite_agt.read(32'h020C, irq_status);
        env.axi_lite_agt.read(32'h0260, tx_pkt_cnt);
        env.axi_lite_agt.read(32'h0264, tx_byte_cnt);
        env.axi_lite_agt.read(32'h0270, rx_pkt_cnt);
        env.axi_lite_agt.read(32'h0274, rx_byte_cnt);
        
        `uvm_info("TEST", "========================================", UVM_NONE)
        `uvm_info("TEST", "           STRESS TEST RESULTS", UVM_NONE)
        `uvm_info("TEST", "========================================", UVM_NONE)
        `uvm_info("TEST", $sformatf("DMA Status:    0x%08h", status), UVM_NONE)
        `uvm_info("TEST", $sformatf("IRQ Status:    0x%08h", irq_status), UVM_NONE)
        `uvm_info("TEST", "----------------------------------------", UVM_NONE)
        `uvm_info("TEST", $sformatf("TX Queued:     %0d", tx_queued), UVM_NONE)
        `uvm_info("TEST", $sformatf("TX Completed:  %0d", tx_completed), UVM_NONE)
        `uvm_info("TEST", $sformatf("TX HW Count:   %0d", tx_pkt_cnt), UVM_NONE)
        `uvm_info("TEST", $sformatf("TX Bytes:      %0d", tx_byte_cnt), UVM_NONE)
        `uvm_info("TEST", "----------------------------------------", UVM_NONE)
        `uvm_info("TEST", $sformatf("RX Injected:   %0d", rx_injected), UVM_NONE)
        `uvm_info("TEST", $sformatf("RX Completed:  %0d", rx_completed), UVM_NONE)
        `uvm_info("TEST", $sformatf("RX HW Count:   %0d", rx_pkt_cnt), UVM_NONE)
        `uvm_info("TEST", $sformatf("RX Bytes:      %0d", rx_byte_cnt), UVM_NONE)
        `uvm_info("TEST", "========================================", UVM_NONE)
        
        // Verify counts
        if (tx_pkt_cnt != tx_queued) begin
            `uvm_error("TEST", $sformatf("TX count mismatch: queued=%0d hw=%0d", tx_queued, tx_pkt_cnt))
            errors++;
        end
        
        if (rx_pkt_cnt != rx_injected) begin
            `uvm_error("TEST", $sformatf("RX count mismatch: injected=%0d hw=%0d", rx_injected, rx_pkt_cnt))
            errors++;
        end
        
        // Check for error interrupts
        if (irq_status & 32'h0000_0300) begin
            `uvm_error("TEST", $sformatf("Error interrupts detected: 0x%08h", irq_status))
            errors++;
        end
        
        if (errors == 0) begin
            `uvm_info("TEST", "STRESS TEST PASSED", UVM_NONE)
        end else begin
            `uvm_error("TEST", $sformatf("STRESS TEST FAILED with %0d errors", errors))
        end
    endtask

endclass : dma_stress_test
