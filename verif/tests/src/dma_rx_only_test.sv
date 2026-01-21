//==============================================================================
// File: dma_rx_only_test.sv
// Description: DMA RX-only path verification test
//==============================================================================

class dma_rx_only_test extends dma_base_test;

    `uvm_component_utils(dma_rx_only_test)

    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int num_packets = 5;
    int packet_sizes[] = '{64, 128, 256, 512, 1518};

    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_rx_only_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // Run Phase
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        gmii_frame frame;
        bit [31:0] rx_head, prev_head;
        
        phase.raise_objection(this);
        super.run_phase(phase);
        
        `uvm_info("TEST", "========================================", UVM_NONE)
        `uvm_info("TEST", "    DMA RX-Only Test Starting", UVM_NONE)
        `uvm_info("TEST", "========================================", UVM_NONE)
        
        // Initialize MAC
        #100ns;
        
        // Configure DMA (RX only)
        configure_dma(.enable_tx(0), .enable_rx(1), .enable_irq(1));
        
        // Setup RX buffers
        setup_rx_buffers(desc_count);
        
        // Get initial head
        read_reg(32'h024C, prev_head);
        
        // Inject frames via GMII
        for (int i = 0; i < num_packets; i++) begin
            int pkt_len = packet_sizes[i % packet_sizes.size()];
            
            // Create frame
            frame = gmii_frame::type_id::create("rx_frame");
            frame.dst_mac = 48'h001122334455;
            frame.src_mac = 48'hAABBCCDDEEFF;
            frame.ether_type = 16'h0800 + i;
            frame.payload = new[pkt_len - 18];  // Subtract header and FCS
            for (int j = 0; j < frame.payload.size(); j++) begin
                frame.payload[j] = j[7:0];
            end
            frame.has_fcs = 1;
            
            // Send frame
            send_frame(frame);
            `uvm_info("TEST", $sformatf("Injected RX frame %0d: length=%0d", i+1, pkt_len), UVM_MEDIUM)
            
            #5us;
        end
        
        // Wait for RX completions
        #10us;
        wait_rx_complete(10000);
        
        // Verify received packets
        verify_rx_packets();
        
        // Verify RX statistics
        verify_rx_stats();
        
        #10us;
        phase.drop_objection(this);
    endtask

    //--------------------------------------------------------------------------
    // Verify Received Packets
    //--------------------------------------------------------------------------
    virtual task verify_rx_packets();
        bit [31:0] head;
        int packets_received = 0;
        
        read_reg(32'h024C, head);
        
        `uvm_info("TEST", $sformatf("RX head pointer: %0d", head), UVM_MEDIUM)
        
        for (int i = 0; i < head; i++) begin
            bit [63:0] desc_addr = rx_desc_base + (i * 16);
            bit [31:0] status;
            int pkt_len;
            
            // Read status
            status = 0;
            status[7:0]   = mm_agent.mem.read_byte(desc_addr + 12);
            status[15:8]  = mm_agent.mem.read_byte(desc_addr + 13);
            status[23:16] = mm_agent.mem.read_byte(desc_addr + 14);
            status[31:24] = mm_agent.mem.read_byte(desc_addr + 15);
            
            // Read length
            pkt_len = {mm_agent.mem.read_byte(desc_addr + 9), mm_agent.mem.read_byte(desc_addr + 8)};
            
            if (status[30]) begin  // DONE bit
                packets_received++;
                `uvm_info("TEST", $sformatf("RX Desc[%0d]: length=%0d status=0x%08h", i, pkt_len, status), UVM_HIGH)
                
                if (status[29]) begin  // ERR bit
                    `uvm_error("TEST", $sformatf("RX Desc[%0d]: Error flag set", i))
                end
            end
        end
        
        if (packets_received != num_packets) begin
            `uvm_error("TEST", $sformatf("Received packet count mismatch: expected=%0d got=%0d", 
                num_packets, packets_received))
        end else begin
            `uvm_info("TEST", $sformatf("All %0d packets received successfully", packets_received), UVM_MEDIUM)
        end
    endtask

    //--------------------------------------------------------------------------
    // Verify RX Statistics
    //--------------------------------------------------------------------------
    virtual task verify_rx_stats();
        bit [31:0] pkt_cnt, byte_cnt;
        
        read_reg(32'h0270, pkt_cnt);   // RX_PKT_CNT
        read_reg(32'h0274, byte_cnt);  // RX_BYTE_CNT
        
        `uvm_info("TEST", $sformatf("RX Statistics: packets=%0d bytes=%0d", pkt_cnt, byte_cnt), UVM_MEDIUM)
        
        if (pkt_cnt != num_packets) begin
            `uvm_error("TEST", $sformatf("RX packet count mismatch: expected=%0d got=%0d", num_packets, pkt_cnt))
        end
    endtask

endclass : dma_rx_only_test
