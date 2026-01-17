//==============================================================================
// DMA Loopback Test Sequences
//==============================================================================

`ifndef DMA_LOOPBACK_SEQ_SV
`define DMA_LOOPBACK_SEQ_SV

//==============================================================================
// Basic Loopback Sequence - TX followed by RX verification
//==============================================================================
class dma_loopback_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_loopback_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    rand int packet_length;
    int timeout_us = 10000;
    
    constraint packet_length_c {
        packet_length >= 64;
        packet_length <= 1518;
    }
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_loopback_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        bit [7:0] tx_packet[$];
        bit [7:0] rx_packet[$];
        dma_rx_setup_seq rx_setup;
        bit [31:0] rx_head;
        bit [31:0] prev_rx_head;
        bit [63:0] rx_desc_addr;
        bit [31:0] status;
        bit [63:0] buf_addr;
        int rx_len;
        int wait_count;
        
        `uvm_info("DMA_LB", $sformatf("Starting loopback test: length=%0d", packet_length), UVM_MEDIUM)
        
        // ========== Step 1: Setup RX ring ==========
        rx_setup = dma_rx_setup_seq::type_id::create("rx_setup");
        rx_setup.mem = mem;
        rx_setup.rx_desc_base = rx_desc_base;
        rx_setup.rx_desc_count = rx_desc_count;
        rx_setup.rx_buf_base = rx_buf_base;
        rx_setup.start(null);
        
        // Get initial RX head
        read_reg(DMA_RX_HEAD, prev_rx_head);
        
        // ========== Step 2: Generate and transmit packet ==========
        generate_ethernet_frame(
            .dst_mac(48'hFF_FF_FF_FF_FF_FF),  // Broadcast
            .src_mac(48'h00_11_22_33_44_55),
            .ethertype(16'h0800),             // IPv4
            .payload_length(packet_length - 14),
            .frame(tx_packet)
        );
        
        transmit_packet(tx_packet);
        
        // ========== Step 3: Wait for RX ==========
        `uvm_info("DMA_LB", "Waiting for loopback packet", UVM_MEDIUM)
        wait_count = 0;
        
        do begin
            read_reg(DMA_RX_HEAD, rx_head);
            
            if (rx_head != prev_rx_head) begin
                // Packet received
                rx_desc_addr = rx_desc_base + (prev_rx_head * 16);
                status = read_descriptor_status(rx_desc_addr);
                
                if (status[DESC_DONE_BIT]) begin
                    // Get buffer address
                    buf_addr = 0;
                    buf_addr[7:0]   = mem.read_byte(rx_desc_addr + 0);
                    buf_addr[15:8]  = mem.read_byte(rx_desc_addr + 1);
                    buf_addr[23:16] = mem.read_byte(rx_desc_addr + 2);
                    buf_addr[31:24] = mem.read_byte(rx_desc_addr + 3);
                    buf_addr[39:32] = mem.read_byte(rx_desc_addr + 4);
                    buf_addr[47:40] = mem.read_byte(rx_desc_addr + 5);
                    buf_addr[55:48] = mem.read_byte(rx_desc_addr + 6);
                    buf_addr[63:56] = mem.read_byte(rx_desc_addr + 7);
                    
                    // Get length
                    rx_len = {mem.read_byte(rx_desc_addr + 9), mem.read_byte(rx_desc_addr + 8)};
                    
                    // Read RX data
                    read_packet_buffer(buf_addr, rx_len, rx_packet);
                    
                    `uvm_info("DMA_LB", $sformatf("Received packet: length=%0d", rx_len), UVM_MEDIUM)
                    
                    // ========== Step 4: Verify ==========
                    verify_loopback(tx_packet, rx_packet);
                    return;
                end
            end
            
            #1us;
            wait_count++;
        end while (wait_count < timeout_us);
        
        `uvm_error("DMA_LB", "Timeout waiting for loopback packet")
    endtask
    
    //--------------------------------------------------------------------------
    // Transmit Packet Helper
    //--------------------------------------------------------------------------
    task transmit_packet(bit [7:0] data[$]);
        bit [63:0] buf_addr;
        bit [31:0] tail;
        
        // Write to TX buffer
        buf_addr = tx_buf_base;
        write_packet_buffer(buf_addr, data);
        
        // Get tail
        read_reg(DMA_TX_TAIL, tail);
        
        // Create descriptor
        create_tx_descriptor(
            .index(tail),
            .buf_addr(buf_addr),
            .length(data.size()),
            .is_first(1),
            .is_last(1),
            .set_own(1)
        );
        
        // Update tail
        tail = (tail + 1) % tx_desc_count;
        write_reg(DMA_TX_TAIL, tail);
        
        `uvm_info("DMA_LB", $sformatf("Transmitted packet: length=%0d", data.size()), UVM_HIGH)
    endtask
    
    //--------------------------------------------------------------------------
    // Verify Loopback Data
    //--------------------------------------------------------------------------
    function void verify_loopback(bit [7:0] tx_data[$], bit [7:0] rx_data[$]);
        int errors = 0;
        int compare_len;
        
        // Compare lengths (RX may include padding, FCS)
        if (rx_data.size() < tx_data.size()) begin
            `uvm_error("DMA_LB", $sformatf("RX packet too short: TX=%0d RX=%0d", 
                tx_data.size(), rx_data.size()))
            return;
        end
        
        compare_len = tx_data.size();
        
        // Compare data
        for (int i = 0; i < compare_len; i++) begin
            if (tx_data[i] !== rx_data[i]) begin
                `uvm_error("DMA_LB", $sformatf("Data mismatch at byte %0d: TX=0x%02h RX=0x%02h",
                    i, tx_data[i], rx_data[i]))
                errors++;
                if (errors > 10) begin
                    `uvm_error("DMA_LB", "Too many errors, stopping comparison")
                    return;
                end
            end
        end
        
        if (errors == 0)
            `uvm_info("DMA_LB", "Loopback verification PASSED", UVM_MEDIUM)
    endfunction
    
endclass : dma_loopback_seq


//==============================================================================
// Multi-Packet Loopback Sequence
//==============================================================================
class dma_loopback_multi_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_loopback_multi_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    rand int num_packets;
    rand int min_length;
    rand int max_length;
    int timeout_us = 50000;
    
    constraint config_c {
        num_packets >= 1;
        num_packets <= 64;
        min_length >= 64;
        max_length <= 1518;
        min_length <= max_length;
    }
    
    //--------------------------------------------------------------------------
    // Packet Storage
    //--------------------------------------------------------------------------
    bit [7:0] tx_packets[$][$];
    bit [7:0] rx_packets[$][$];
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_loopback_multi_seq");
        super.new(name);
        min_length = 64;
        max_length = 1518;
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        dma_rx_setup_seq rx_setup;
        bit [63:0] buf_addr;
        bit [31:0] tx_tail, rx_head, prev_rx_head;
        int pkt_len;
        bit [7:0] pkt_data[$];
        int tx_count = 0;
        int rx_count = 0;
        int wait_count = 0;
        
        `uvm_info("DMA_LB", $sformatf("Starting multi-packet loopback: %0d packets, %0d-%0d bytes",
            num_packets, min_length, max_length), UVM_MEDIUM)
        
        // ========== Step 1: Setup RX ring ==========
        rx_setup = dma_rx_setup_seq::type_id::create("rx_setup");
        rx_setup.mem = mem;
        rx_setup.rx_desc_base = rx_desc_base;
        rx_setup.rx_desc_count = rx_desc_count;
        rx_setup.rx_buf_base = rx_buf_base;
        rx_setup.start(null);
        
        read_reg(DMA_RX_HEAD, prev_rx_head);
        read_reg(DMA_TX_TAIL, tx_tail);
        
        // ========== Step 2: Generate and queue all TX packets ==========
        tx_packets.delete();
        
        for (int i = 0; i < num_packets; i++) begin
            pkt_len = $urandom_range(min_length, max_length);
            
            generate_ethernet_frame(
                .dst_mac(48'hFF_FF_FF_FF_FF_FF),
                .src_mac(48'h00_11_22_33_44_55),
                .ethertype(16'h0800 + i),  // Unique ethertype for identification
                .payload_length(pkt_len - 14),
                .frame(pkt_data)
            );
            
            tx_packets.push_back(pkt_data);
            
            // Write to buffer
            buf_addr = tx_buf_base + (i * buf_size);
            write_packet_buffer(buf_addr, pkt_data);
            
            // Create descriptor
            create_tx_descriptor(
                .index((tx_tail + i) % tx_desc_count),
                .buf_addr(buf_addr),
                .length(pkt_data.size()),
                .is_first(1),
                .is_last(1),
                .set_own(1)
            );
        end
        
        // Update tail to start all transmissions
        tx_tail = (tx_tail + num_packets) % tx_desc_count;
        write_reg(DMA_TX_TAIL, tx_tail);
        
        `uvm_info("DMA_LB", $sformatf("Queued %0d TX packets", num_packets), UVM_MEDIUM)
        
        // ========== Step 3: Receive all packets ==========
        rx_packets.delete();
        
        do begin
            read_reg(DMA_RX_HEAD, rx_head);
            
            while (prev_rx_head != rx_head && rx_count < num_packets) begin
                bit [63:0] rx_desc_addr = rx_desc_base + (prev_rx_head * 16);
                bit [31:0] status = read_descriptor_status(rx_desc_addr);
                
                if (status[DESC_DONE_BIT]) begin
                    buf_addr = 0;
                    for (int b = 0; b < 8; b++)
                        buf_addr[b*8 +: 8] = mem.read_byte(rx_desc_addr + b);
                    
                    pkt_len = {mem.read_byte(rx_desc_addr + 9), mem.read_byte(rx_desc_addr + 8)};
                    
                    read_packet_buffer(buf_addr, pkt_len, pkt_data);
                    rx_packets.push_back(pkt_data);
                    rx_count++;
                    
                    `uvm_info("DMA_LB", $sformatf("Received packet %0d: length=%0d", rx_count, pkt_len), UVM_HIGH)
                end
                
                prev_rx_head = (prev_rx_head + 1) % rx_desc_count;
            end
            
            if (rx_count >= num_packets) break;
            
            #1us;
            wait_count++;
        end while (wait_count < timeout_us);
        
        // ========== Step 4: Verify all packets ==========
        if (rx_count != num_packets) begin
            `uvm_error("DMA_LB", $sformatf("Packet count mismatch: TX=%0d RX=%0d", num_packets, rx_count))
        end else begin
            verify_all_packets();
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Verify All Packets
    //--------------------------------------------------------------------------
    function void verify_all_packets();
        int errors = 0;
        
        for (int i = 0; i < tx_packets.size() && i < rx_packets.size(); i++) begin
            int compare_len = tx_packets[i].size();
            
            if (rx_packets[i].size() < compare_len) begin
                `uvm_error("DMA_LB", $sformatf("Packet %0d: RX too short (%0d < %0d)",
                    i, rx_packets[i].size(), compare_len))
                errors++;
                continue;
            end
            
            for (int j = 0; j < compare_len; j++) begin
                if (tx_packets[i][j] !== rx_packets[i][j]) begin
                    `uvm_error("DMA_LB", $sformatf("Packet %0d byte %0d: TX=0x%02h RX=0x%02h",
                        i, j, tx_packets[i][j], rx_packets[i][j]))
                    errors++;
                    break;  // Only report first mismatch per packet
                end
            end
        end
        
        if (errors == 0)
            `uvm_info("DMA_LB", $sformatf("All %0d packets verified successfully", tx_packets.size()), UVM_MEDIUM)
        else
            `uvm_error("DMA_LB", $sformatf("%0d packet verification errors", errors))
    endfunction
    
endclass : dma_loopback_multi_seq


//==============================================================================
// Bidirectional Traffic Sequence
//==============================================================================
class dma_bidirectional_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_bidirectional_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int num_packets = 32;
    int packet_length = 256;
    int duration_us = 100000;
    
    //--------------------------------------------------------------------------
    // Statistics
    //--------------------------------------------------------------------------
    int tx_sent = 0;
    int rx_received = 0;
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_bidirectional_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        dma_rx_setup_seq rx_setup;
        
        `uvm_info("DMA_LB", $sformatf("Starting bidirectional traffic: %0d packets, %0d us",
            num_packets, duration_us), UVM_MEDIUM)
        
        // Setup RX
        rx_setup = dma_rx_setup_seq::type_id::create("rx_setup");
        rx_setup.mem = mem;
        rx_setup.rx_desc_base = rx_desc_base;
        rx_setup.rx_desc_count = rx_desc_count;
        rx_setup.rx_buf_base = rx_buf_base;
        rx_setup.start(null);
        
        // Run TX and RX in parallel
        fork
            tx_traffic();
            rx_traffic();
        join_any
        
        // Report statistics
        `uvm_info("DMA_LB", $sformatf("Bidirectional test complete: TX=%0d RX=%0d",
            tx_sent, rx_received), UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // TX Traffic Generator
    //--------------------------------------------------------------------------
    task tx_traffic();
        bit [63:0] buf_addr;
        bit [31:0] tail;
        bit [7:0] pkt_data[$];
        
        for (int i = 0; i < num_packets; i++) begin
            // Generate packet
            generate_random_packet(packet_length, pkt_data);
            
            // Get tail
            read_reg(DMA_TX_TAIL, tail);
            
            // Write to buffer
            buf_addr = tx_buf_base + ((tail % tx_desc_count) * buf_size);
            write_packet_buffer(buf_addr, pkt_data);
            
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
            tx_sent++;
            
            // Inter-packet gap
            #($urandom_range(100, 1000) * 1ns);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // RX Traffic Handler
    //--------------------------------------------------------------------------
    task rx_traffic();
        bit [31:0] rx_head, prev_rx_head;
        int timeout = duration_us;
        
        read_reg(DMA_RX_HEAD, prev_rx_head);
        
        while (timeout > 0 && rx_received < num_packets) begin
            read_reg(DMA_RX_HEAD, rx_head);
            
            while (prev_rx_head != rx_head) begin
                rx_received++;
                prev_rx_head = (prev_rx_head + 1) % rx_desc_count;
                
                // Replenish buffer
                create_rx_descriptor(
                    .index((prev_rx_head + rx_desc_count - 1) % rx_desc_count),
                    .buf_addr(rx_buf_base + (((prev_rx_head + rx_desc_count - 1) % rx_desc_count) * buf_size)),
                    .buf_length(buf_size),
                    .set_own(1)
                );
            end
            
            #1us;
            timeout--;
        end
    endtask
    
endclass : dma_bidirectional_seq

`endif // DMA_LOOPBACK_SEQ_SV
