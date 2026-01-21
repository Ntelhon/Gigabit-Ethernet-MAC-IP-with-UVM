//==============================================================================
// File: dma_tx_only_test.sv
// Description: DMA TX-only path verification test
//==============================================================================

class dma_tx_only_test extends dma_base_test;

    `uvm_component_utils(dma_tx_only_test)

    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int num_packets = 5;
    int packet_sizes[] = '{64, 128, 256, 512, 1518};

    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_tx_only_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // Run Phase
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        bit [7:0] pkt_data[$];
        bit [31:0] tail;
        
        phase.raise_objection(this);
        super.run_phase(phase);
        
        `uvm_info("TEST", "========================================", UVM_NONE)
        `uvm_info("TEST", "    DMA TX-Only Test Starting", UVM_NONE)
        `uvm_info("TEST", "========================================", UVM_NONE)
        
        // Initialize MAC
        #100ns;
        
        // Configure DMA (TX only)
        configure_dma(.enable_tx(1), .enable_rx(0), .enable_irq(1));
        
        // Transmit packets of various sizes
        for (int i = 0; i < num_packets; i++) begin
            int pkt_len = packet_sizes[i % packet_sizes.size()];
            
            // Generate packet
            generate_packet(pkt_len, pkt_data);
            
            // Get current tail
            read_reg(32'h0220, tail);
            
            // Queue packet
            queue_tx_packet(pkt_data, tail);
            
            // Update tail
            tail = (tail + 1) % desc_count;
            write_reg(32'h0220, tail);
            
            `uvm_info("TEST", $sformatf("Transmitted packet %0d: length=%0d", i+1, pkt_len), UVM_MEDIUM)
            
            // Wait for completion
            wait_tx_complete(5000);
            
            #1us;
        end
        
        // Verify TX statistics
        verify_tx_stats();
        
        #10us;
        phase.drop_objection(this);
    endtask

    //--------------------------------------------------------------------------
    // Verify TX Statistics
    //--------------------------------------------------------------------------
    virtual task verify_tx_stats();
        bit [31:0] pkt_cnt, byte_cnt;
        
        read_reg(32'h0260, pkt_cnt);   // TX_PKT_CNT
        read_reg(32'h0264, byte_cnt);  // TX_BYTE_CNT
        
        `uvm_info("TEST", $sformatf("TX Statistics: packets=%0d bytes=%0d", pkt_cnt, byte_cnt), UVM_MEDIUM)
        
        if (pkt_cnt != num_packets) begin
            `uvm_error("TEST", $sformatf("TX packet count mismatch: expected=%0d got=%0d", num_packets, pkt_cnt))
        end
    endtask

endclass : dma_tx_only_test
