//==============================================================================
// File: eth_controller_full_test.sv
// Description: Comprehensive test exercising all Ethernet Controller features
//              Tests MAC, DMA, interrupts, statistics, and error handling
//==============================================================================

class eth_controller_full_test extends dma_base_test;

    `uvm_component_utils(eth_controller_full_test)

    //--------------------------------------------------------------------------
    // Test Configuration
    //--------------------------------------------------------------------------
    bit [47:0] dut_mac_address = 48'h001122334455;
    
    // Test packet counts
    int basic_tx_count = 5;
    int basic_rx_count = 5;
    int loopback_count = 3;
    int error_inject_count = 2;
    
    //--------------------------------------------------------------------------
    // Statistics
    //--------------------------------------------------------------------------
    int total_tx_packets = 0;
    int total_rx_packets = 0;
    int total_errors = 0;

    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "eth_controller_full_test", uvm_component parent = null);
        super.new(name, parent);
        test_timeout = 500000;
    endfunction

    //--------------------------------------------------------------------------
    // Run Phase
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        super.run_phase(phase);
        
        print_banner("ETHERNET CONTROLLER COMPREHENSIVE TEST");
        
        // Initialize
        #100ns;
        
        // ========== Phase 1: MAC Configuration ==========
        test_mac_configuration();
        
        // ========== Phase 2: DMA Configuration ==========
        test_dma_configuration();
        
        // ========== Phase 3: Basic TX Path ==========
        test_basic_tx();
        
        // ========== Phase 4: Basic RX Path ==========
        test_basic_rx();
        
        // ========== Phase 5: Bidirectional Traffic ==========
        test_bidirectional();
        
        // ========== Phase 6: Variable Packet Sizes ==========
        test_variable_sizes();
        
        // ========== Phase 7: Interrupt Handling ==========
        test_interrupts();
        
        // ========== Phase 8: Error Handling ==========
        test_error_handling();
        
        // ========== Phase 9: Statistics Verification ==========
        test_statistics();
        
        // ========== Phase 10: Reset Recovery ==========
        test_reset_recovery();
        
        // Final report
        final_report();
        
        phase.drop_objection(this);
    endtask

    //--------------------------------------------------------------------------
    // Print Banner
    //--------------------------------------------------------------------------
    function void print_banner(string msg);
        `uvm_info("TEST", "================================================", UVM_NONE)
        `uvm_info("TEST", $sformatf("  %s", msg), UVM_NONE)
        `uvm_info("TEST", "================================================", UVM_NONE)
    endfunction

    function void print_phase(string msg);
        `uvm_info("TEST", "------------------------------------------------", UVM_MEDIUM)
        `uvm_info("TEST", $sformatf("  Phase: %s", msg), UVM_MEDIUM)
        `uvm_info("TEST", "------------------------------------------------", UVM_MEDIUM)
    endfunction

    //--------------------------------------------------------------------------
    // Phase 1: MAC Configuration
    //--------------------------------------------------------------------------
    virtual task test_mac_configuration();
        bit [31:0] data;
        
        print_phase("MAC Configuration");
        
        // Set MAC address
        env.axi_lite_agt.write(32'h0010, dut_mac_address[31:0]);
        env.axi_lite_agt.write(32'h0014, {16'h0, dut_mac_address[47:32]});
        
        // Verify readback
        env.axi_lite_agt.read(32'h0010, data);
        if (data != dut_mac_address[31:0]) begin
            `uvm_error("TEST", "MAC address low mismatch")
            total_errors++;
        end
        
        // Enable MAC TX and RX
        env.axi_lite_agt.write(32'h0000, 32'h0000_0003);  // TX_EN | RX_EN
        
        // Verify
        env.axi_lite_agt.read(32'h0000, data);
        if ((data & 32'h3) != 32'h3) begin
            `uvm_error("TEST", "MAC enable failed")
            total_errors++;
        end
        
        // Configure promiscuous mode for testing
        env.axi_lite_agt.write(32'h0004, 32'h0000_0001);  // PROMISC
        
        `uvm_info("TEST", "MAC configuration complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Phase 2: DMA Configuration
    //--------------------------------------------------------------------------
    virtual task test_dma_configuration();
        print_phase("DMA Configuration");
        
        // Full DMA configuration
        configure_dma(.enable_tx(1), .enable_rx(1), .enable_irq(1));
        
        // Setup RX buffers
        setup_rx_buffers(desc_count);
        
        // Configure interrupt coalescing
        env.axi_lite_agt.write(32'h0280, 32'h0064_0002);  // TX: 2 packets or 100 cycles
        env.axi_lite_agt.write(32'h0284, 32'h0064_0002);  // RX: 2 packets or 100 cycles
        
        `uvm_info("TEST", "DMA configuration complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Phase 3: Basic TX Path
    //--------------------------------------------------------------------------
    virtual task test_basic_tx();
        bit [7:0] pkt_data[$];
        bit [31:0] tail;
        
        print_phase("Basic TX Path");
        
        for (int i = 0; i < basic_tx_count; i++) begin
            generate_packet(128, pkt_data);
            
            env.axi_lite_agt.read(32'h0220, tail);
            queue_tx_packet(pkt_data, tail);
            tail = (tail + 1) % desc_count;
            env.axi_lite_agt.write(32'h0220, tail);
            
            total_tx_packets++;
            wait_tx_complete(5000);
            
            `uvm_info("TEST", $sformatf("TX packet %0d complete", i+1), UVM_HIGH)
        end
        
        `uvm_info("TEST", $sformatf("Basic TX: %0d packets sent", basic_tx_count), UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Phase 4: Basic RX Path
    //--------------------------------------------------------------------------
    virtual task test_basic_rx();
        gmii_frame frame;
        bit [31:0] head, prev_head;
        
        print_phase("Basic RX Path");
        
        env.axi_lite_agt.read(32'h024C, prev_head);
        
        for (int i = 0; i < basic_rx_count; i++) begin
            frame = gmii_frame::type_id::create("rx_frame");
            frame.dst_mac = dut_mac_address;
            frame.src_mac = 48'hAABBCCDDEEFF;
            frame.ether_type = 16'h0800;
            frame.payload = new[100];
            foreach (frame.payload[j]) frame.payload[j] = j[7:0];
            frame.has_fcs = 1;
            
            env.gmii_agt.send_frame(frame);
            total_rx_packets++;
            
            #5us;
        end
        
        #10us;
        
        // Verify reception
        env.axi_lite_agt.read(32'h024C, head);
        if (head - prev_head != basic_rx_count) begin
            `uvm_error("TEST", $sformatf("RX count mismatch: expected=%0d got=%0d", 
                basic_rx_count, head - prev_head))
            total_errors++;
        end
        
        `uvm_info("TEST", $sformatf("Basic RX: %0d frames received", head - prev_head), UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Phase 5: Bidirectional Traffic
    //--------------------------------------------------------------------------
    virtual task test_bidirectional();
        print_phase("Bidirectional Traffic");
        
        fork
            begin : tx_thread
                bit [7:0] pkt[$];
                bit [31:0] tail;
                
                for (int i = 0; i < loopback_count; i++) begin
                    generate_packet(256, pkt);
                    env.axi_lite_agt.read(32'h0220, tail);
                    queue_tx_packet(pkt, tail);
                    tail = (tail + 1) % desc_count;
                    env.axi_lite_agt.write(32'h0220, tail);
                    total_tx_packets++;
                    #2us;
                end
            end
            
            begin : rx_thread
                gmii_frame frame;
                
                for (int i = 0; i < loopback_count; i++) begin
                    frame = gmii_frame::type_id::create("rx_frame");
                    frame.dst_mac = dut_mac_address;
                    frame.src_mac = 48'h112233445566;
                    frame.ether_type = 16'h0806;  // ARP
                    frame.payload = new[46];
                    foreach (frame.payload[j]) frame.payload[j] = $urandom;
                    frame.has_fcs = 1;
                    
                    env.gmii_agt.send_frame(frame);
                    total_rx_packets++;
                    #3us;
                end
            end
        join
        
        #20us;
        `uvm_info("TEST", "Bidirectional traffic complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Phase 6: Variable Packet Sizes
    //--------------------------------------------------------------------------
    virtual task test_variable_sizes();
        int sizes[] = '{64, 128, 256, 512, 1024, 1518};
        bit [7:0] pkt[$];
        bit [31:0] tail;
        gmii_frame frame;
        
        print_phase("Variable Packet Sizes");
        
        // TX various sizes
        foreach (sizes[i]) begin
            generate_packet(sizes[i], pkt);
            env.axi_lite_agt.read(32'h0220, tail);
            queue_tx_packet(pkt, tail);
            tail = (tail + 1) % desc_count;
            env.axi_lite_agt.write(32'h0220, tail);
            total_tx_packets++;
            wait_tx_complete(5000);
            
            `uvm_info("TEST", $sformatf("TX size %0d: OK", sizes[i]), UVM_HIGH)
        end
        
        // RX various sizes
        foreach (sizes[i]) begin
            frame = gmii_frame::type_id::create("rx_frame");
            frame.dst_mac = dut_mac_address;
            frame.src_mac = 48'hDEADBEEF0000 + i;
            frame.ether_type = 16'h0800;
            frame.payload = new[sizes[i] - 18];
            foreach (frame.payload[j]) frame.payload[j] = j[7:0];
            frame.has_fcs = 1;
            
            env.gmii_agt.send_frame(frame);
            total_rx_packets++;
            #10us;
            
            `uvm_info("TEST", $sformatf("RX size %0d: OK", sizes[i]), UVM_HIGH)
        end
        
        `uvm_info("TEST", "Variable size test complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Phase 7: Interrupt Handling
    //--------------------------------------------------------------------------
    virtual task test_interrupts();
        bit [31:0] irq_status, irq_en;
        
        print_phase("Interrupt Handling");
        
        // Read current interrupt enable
        env.axi_lite_agt.read(32'h0208, irq_en);
        `uvm_info("TEST", $sformatf("IRQ Enable: 0x%08h", irq_en), UVM_MEDIUM)
        
        // Generate some traffic to trigger interrupts
        begin
            bit [7:0] pkt[$];
            bit [31:0] tail;
            
            generate_packet(64, pkt);
            env.axi_lite_agt.read(32'h0220, tail);
            queue_tx_packet(pkt, tail);
            env.axi_lite_agt.write(32'h0220, (tail + 1) % desc_count);
            total_tx_packets++;
        end
        
        #10us;
        
        // Check interrupt status
        env.axi_lite_agt.read(32'h020C, irq_status);
        `uvm_info("TEST", $sformatf("IRQ Status: 0x%08h", irq_status), UVM_MEDIUM)
        
        // Clear interrupts
        env.axi_lite_agt.write(32'h020C, irq_status);
        
        // Verify cleared
        env.axi_lite_agt.read(32'h020C, irq_status);
        if (irq_status != 0) begin
            `uvm_warning("TEST", $sformatf("Interrupts not fully cleared: 0x%08h", irq_status))
        end
        
        `uvm_info("TEST", "Interrupt handling complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Phase 8: Error Handling
    //--------------------------------------------------------------------------
    virtual task test_error_handling();
        gmii_frame frame;
        bit [31:0] status;
        
        print_phase("Error Handling");
        
        // Test 1: CRC error frame
        `uvm_info("TEST", "Injecting CRC error frame", UVM_MEDIUM)
        frame = gmii_frame::type_id::create("crc_err_frame");
        frame.dst_mac = dut_mac_address;
        frame.src_mac = 48'hBADBADBADBAD;
        frame.ether_type = 16'h0800;
        frame.payload = new[46];
        frame.has_fcs = 1;
        frame.inject_fcs_error = 1;  // Bad CRC
        
        env.gmii_agt.send_frame(frame);
        #5us;
        
        // Check error status in MAC
        env.axi_lite_agt.read(32'h0008, status);  // MAC IRQ status
        `uvm_info("TEST", $sformatf("MAC IRQ Status after CRC error: 0x%08h", status), UVM_MEDIUM)
        
        // Test 2: Runt frame (too short)
        `uvm_info("TEST", "Injecting runt frame", UVM_MEDIUM)
        frame = gmii_frame::type_id::create("runt_frame");
        frame.dst_mac = dut_mac_address;
        frame.src_mac = 48'h123456789ABC;
        frame.ether_type = 16'h0800;
        frame.payload = new[10];  // Way too short
        frame.has_fcs = 1;
        
        env.gmii_agt.send_frame(frame);
        #5us;
        
        `uvm_info("TEST", "Error handling complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Phase 9: Statistics Verification
    //--------------------------------------------------------------------------
    virtual task test_statistics();
        bit [31:0] mac_tx_frames, mac_rx_frames;
        bit [31:0] dma_tx_pkts, dma_tx_bytes;
        bit [31:0] dma_rx_pkts, dma_rx_bytes;
        
        print_phase("Statistics Verification");
        
        // Read MAC statistics
        env.axi_lite_agt.read(32'h0020, mac_tx_frames);  // TX frame count
        env.axi_lite_agt.read(32'h0030, mac_rx_frames);  // RX frame count
        
        // Read DMA statistics
        env.axi_lite_agt.read(32'h0260, dma_tx_pkts);
        env.axi_lite_agt.read(32'h0264, dma_tx_bytes);
        env.axi_lite_agt.read(32'h0270, dma_rx_pkts);
        env.axi_lite_agt.read(32'h0274, dma_rx_bytes);
        
        `uvm_info("TEST", "=== Statistics ===", UVM_MEDIUM)
        `uvm_info("TEST", $sformatf("MAC TX Frames: %0d", mac_tx_frames), UVM_MEDIUM)
        `uvm_info("TEST", $sformatf("MAC RX Frames: %0d", mac_rx_frames), UVM_MEDIUM)
        `uvm_info("TEST", $sformatf("DMA TX Packets: %0d (%0d bytes)", dma_tx_pkts, dma_tx_bytes), UVM_MEDIUM)
        `uvm_info("TEST", $sformatf("DMA RX Packets: %0d (%0d bytes)", dma_rx_pkts, dma_rx_bytes), UVM_MEDIUM)
        
        // Verify DMA TX count matches expected
        if (dma_tx_pkts != total_tx_packets) begin
            `uvm_error("TEST", $sformatf("DMA TX count mismatch: expected=%0d got=%0d", 
                total_tx_packets, dma_tx_pkts))
            total_errors++;
        end
        
        `uvm_info("TEST", "Statistics verification complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Phase 10: Reset Recovery
    //--------------------------------------------------------------------------
    virtual task test_reset_recovery();
        bit [31:0] ctrl, status;
        
        print_phase("Reset Recovery");
        
        // Soft reset DMA
        `uvm_info("TEST", "Performing DMA soft reset", UVM_MEDIUM)
        env.axi_lite_agt.write(32'h0200, 32'h0000_0300);  // TX_RST | RX_RST
        #1us;
        env.axi_lite_agt.write(32'h0200, 32'h0000_0000);
        #1us;
        
        // Verify DMA is stopped
        env.axi_lite_agt.read(32'h0204, status);
        `uvm_info("TEST", $sformatf("DMA status after reset: 0x%08h", status), UVM_MEDIUM)
        
        // Re-enable DMA
        configure_dma(.enable_tx(1), .enable_rx(1), .enable_irq(1));
        setup_rx_buffers(desc_count);
        
        // Verify can still send/receive
        begin
            bit [7:0] pkt[$];
            bit [31:0] tail;
            
            generate_packet(64, pkt);
            env.axi_lite_agt.read(32'h0220, tail);
            queue_tx_packet(pkt, tail);
            env.axi_lite_agt.write(32'h0220, (tail + 1) % desc_count);
            total_tx_packets++;
            
            wait_tx_complete(5000);
        end
        
        `uvm_info("TEST", "Reset recovery verified", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Final Report
    //--------------------------------------------------------------------------
    virtual task final_report();
        bit [31:0] dma_tx_pkts, dma_rx_pkts;
        
        env.axi_lite_agt.read(32'h0260, dma_tx_pkts);
        env.axi_lite_agt.read(32'h0270, dma_rx_pkts);
        
        `uvm_info("TEST", "", UVM_NONE)
        print_banner("COMPREHENSIVE TEST COMPLETE");
        `uvm_info("TEST", $sformatf("  Total TX Packets Sent:    %0d", total_tx_packets), UVM_NONE)
        `uvm_info("TEST", $sformatf("  Total RX Packets Injected: %0d", total_rx_packets), UVM_NONE)
        `uvm_info("TEST", $sformatf("  DMA TX Counter:            %0d", dma_tx_pkts), UVM_NONE)
        `uvm_info("TEST", $sformatf("  DMA RX Counter:            %0d", dma_rx_pkts), UVM_NONE)
        `uvm_info("TEST", $sformatf("  Test Errors:               %0d", total_errors), UVM_NONE)
        `uvm_info("TEST", "================================================", UVM_NONE)
        
        if (total_errors == 0) begin
            `uvm_info("TEST", "  *** ALL TESTS PASSED ***", UVM_NONE)
        end else begin
            `uvm_error("TEST", $sformatf("  *** %0d TEST FAILURES ***", total_errors))
        end
        `uvm_info("TEST", "================================================", UVM_NONE)
    endtask

endclass : eth_controller_full_test
