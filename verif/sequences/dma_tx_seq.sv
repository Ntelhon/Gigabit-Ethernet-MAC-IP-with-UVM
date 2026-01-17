//==============================================================================
// DMA TX Test Sequences
//==============================================================================

`ifndef DMA_TX_SEQ_SV
`define DMA_TX_SEQ_SV

//==============================================================================
// Single Packet TX Sequence
//==============================================================================
class dma_tx_single_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_tx_single_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    rand int packet_length;
    bit [7:0] packet_data[$];
    bit wait_for_done = 1;
    int timeout_us = 1000;
    
    constraint packet_length_c {
        packet_length >= 64;
        packet_length <= 1518;
    }
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_tx_single_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        bit [63:0] buf_addr;
        bit [63:0] desc_addr;
        bit [31:0] tail;
        int wait_count;
        
        `uvm_info("DMA_TX", $sformatf("Starting TX sequence: packet_length=%0d", packet_length), UVM_MEDIUM)
        
        // ========== Step 1: Prepare packet data ==========
        if (packet_data.size() == 0) begin
            generate_random_packet(packet_length, packet_data);
        end else begin
            packet_length = packet_data.size();
        end
        
        // ========== Step 2: Write packet to buffer ==========
        buf_addr = tx_buf_base;
        write_packet_buffer(buf_addr, packet_data);
        `uvm_info("DMA_TX", $sformatf("Wrote %0d bytes to buffer at 0x%h", packet_length, buf_addr), UVM_HIGH)
        
        // ========== Step 3: Get current tail pointer ==========
        read_reg(DMA_TX_TAIL, tail);
        
        // ========== Step 4: Create descriptor ==========
        create_tx_descriptor(
            .index(tail),
            .buf_addr(buf_addr),
            .length(packet_length),
            .is_first(1),
            .is_last(1),
            .set_own(1)
        );
        
        // ========== Step 5: Update tail pointer ==========
        tail = (tail + 1) % tx_desc_count;
        write_reg(DMA_TX_TAIL, tail);
        `uvm_info("DMA_TX", $sformatf("Updated TX tail to %0d", tail), UVM_HIGH)
        
        // ========== Step 6: Wait for completion ==========
        if (wait_for_done) begin
            desc_addr = tx_desc_base;  // Descriptor 0
            wait_count = 0;
            
            do begin
                if (is_descriptor_done(desc_addr)) begin
                    `uvm_info("DMA_TX", "TX descriptor completed", UVM_MEDIUM)
                    return;
                end
                #1us;
                wait_count++;
            end while (wait_count < timeout_us);
            
            `uvm_error("DMA_TX", "Timeout waiting for TX completion")
        end
    endtask
    
endclass : dma_tx_single_seq


//==============================================================================
// Multiple Packet TX Sequence
//==============================================================================
class dma_tx_multi_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_tx_multi_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    rand int num_packets;
    rand int min_packet_length;
    rand int max_packet_length;
    bit wait_for_all_done = 1;
    int timeout_us = 10000;
    
    constraint num_packets_c {
        num_packets >= 1;
        num_packets <= 16;
    }
    
    constraint packet_length_c {
        min_packet_length >= 64;
        max_packet_length <= 1518;
        min_packet_length <= max_packet_length;
    }
    
    //--------------------------------------------------------------------------
    // Packet Data Storage
    //--------------------------------------------------------------------------
    bit [7:0] packets[$][$];  // Queue of packet data
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_tx_multi_seq");
        super.new(name);
        min_packet_length = 64;
        max_packet_length = 1518;
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        bit [63:0] buf_addr;
        bit [63:0] desc_addr;
        bit [31:0] tail;
        int pkt_len;
        bit [7:0] pkt_data[$];
        int completed_count;
        int wait_count;
        
        `uvm_info("DMA_TX", $sformatf("Starting multi-TX sequence: num_packets=%0d", num_packets), UVM_MEDIUM)
        
        // ========== Step 1: Get current tail pointer ==========
        read_reg(DMA_TX_TAIL, tail);
        
        // ========== Step 2: Prepare all packets ==========
        packets.delete();
        for (int i = 0; i < num_packets; i++) begin
            pkt_len = $urandom_range(min_packet_length, max_packet_length);
            generate_random_packet(pkt_len, pkt_data);
            packets.push_back(pkt_data);
        end
        
        // ========== Step 3: Setup all descriptors ==========
        for (int i = 0; i < num_packets; i++) begin
            int desc_idx = (tail + i) % tx_desc_count;
            buf_addr = tx_buf_base + (i * buf_size);
            
            // Write packet to buffer
            write_packet_buffer(buf_addr, packets[i]);
            
            // Create descriptor
            create_tx_descriptor(
                .index(desc_idx),
                .buf_addr(buf_addr),
                .length(packets[i].size()),
                .is_first(1),
                .is_last(1),
                .set_own(1)
            );
        end
        
        // ========== Step 4: Update tail pointer (triggers DMA) ==========
        tail = (tail + num_packets) % tx_desc_count;
        write_reg(DMA_TX_TAIL, tail);
        `uvm_info("DMA_TX", $sformatf("Queued %0d packets, new tail=%0d", num_packets, tail), UVM_MEDIUM)
        
        // ========== Step 5: Wait for all completions ==========
        if (wait_for_all_done) begin
            wait_count = 0;
            
            do begin
                completed_count = 0;
                
                for (int i = 0; i < num_packets; i++) begin
                    desc_addr = tx_desc_base + (i * 16);
                    if (is_descriptor_done(desc_addr))
                        completed_count++;
                end
                
                if (completed_count == num_packets) begin
                    `uvm_info("DMA_TX", $sformatf("All %0d TX packets completed", num_packets), UVM_MEDIUM)
                    return;
                end
                
                #1us;
                wait_count++;
            end while (wait_count < timeout_us);
            
            `uvm_error("DMA_TX", $sformatf("Timeout: only %0d of %0d packets completed", 
                completed_count, num_packets))
        end
    endtask
    
endclass : dma_tx_multi_seq


//==============================================================================
// Jumbo Frame TX Sequence
//==============================================================================
class dma_tx_jumbo_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_tx_jumbo_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    rand int packet_length;
    bit [7:0] packet_data[$];
    
    constraint packet_length_c {
        packet_length >= 1519;
        packet_length <= 9000;
    }
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_tx_jumbo_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        bit [63:0] buf_addr;
        bit [32:0] tail;
        
        `uvm_info("DMA_TX", $sformatf("Starting Jumbo TX: length=%0d", packet_length), UVM_MEDIUM)
        
        // Generate jumbo frame data
        if (packet_data.size() == 0) begin
            generate_random_packet(packet_length, packet_data);
        end else begin
            packet_length = packet_data.size();
        end
        
        // Write to buffer
        buf_addr = tx_buf_base;
        write_packet_buffer(buf_addr, packet_data);
        
        // Get tail
        read_reg(DMA_TX_TAIL, tail);
        
        // Create descriptor
        create_tx_descriptor(
            .index(tail),
            .buf_addr(buf_addr),
            .length(packet_length),
            .is_first(1),
            .is_last(1),
            .set_own(1)
        );
        
        // Update tail
        tail = (tail + 1) % tx_desc_count;
        write_reg(DMA_TX_TAIL, tail);
        
        `uvm_info("DMA_TX", "Jumbo frame queued for transmission", UVM_MEDIUM)
    endtask
    
endclass : dma_tx_jumbo_seq


//==============================================================================
// Scatter-Gather TX Sequence (multi-descriptor packet)
//==============================================================================
class dma_tx_scatter_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_tx_scatter_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    rand int total_length;
    rand int num_fragments;
    bit wait_for_done = 1;
    
    constraint fragment_c {
        total_length >= 64;
        total_length <= 9000;
        num_fragments >= 2;
        num_fragments <= 8;
    }
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_tx_scatter_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        bit [63:0] buf_addr;
        bit [31:0] tail;
        int frag_lengths[$];
        int remaining;
        int frag_len;
        bit [7:0] frag_data[$];
        
        `uvm_info("DMA_TX", $sformatf("Starting Scatter TX: total=%0d fragments=%0d", 
            total_length, num_fragments), UVM_MEDIUM)
        
        // Calculate fragment lengths
        remaining = total_length;
        for (int i = 0; i < num_fragments - 1; i++) begin
            frag_len = remaining / (num_fragments - i);
            frag_lengths.push_back(frag_len);
            remaining -= frag_len;
        end
        frag_lengths.push_back(remaining);
        
        // Get tail
        read_reg(DMA_TX_TAIL, tail);
        
        // Create descriptors for each fragment
        for (int i = 0; i < num_fragments; i++) begin
            int desc_idx = (tail + i) % tx_desc_count;
            buf_addr = tx_buf_base + (i * buf_size);
            
            // Generate fragment data
            generate_random_packet(frag_lengths[i], frag_data);
            write_packet_buffer(buf_addr, frag_data);
            
            // Create descriptor
            create_tx_descriptor(
                .index(desc_idx),
                .buf_addr(buf_addr),
                .length(frag_lengths[i]),
                .is_first(i == 0),
                .is_last(i == num_fragments - 1),
                .set_own(1)
            );
            
            `uvm_info("DMA_TX", $sformatf("Fragment[%0d]: len=%0d first=%0d last=%0d",
                i, frag_lengths[i], (i == 0), (i == num_fragments - 1)), UVM_HIGH)
        end
        
        // Update tail
        tail = (tail + num_fragments) % tx_desc_count;
        write_reg(DMA_TX_TAIL, tail);
        
        `uvm_info("DMA_TX", $sformatf("Scatter-gather packet queued (%0d descriptors)", num_fragments), UVM_MEDIUM)
    endtask
    
endclass : dma_tx_scatter_seq

`endif // DMA_TX_SEQ_SV
