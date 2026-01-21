//==============================================================================
// DMA RX Test Sequences
//==============================================================================

`ifndef DMA_RX_SEQ_SV
`define DMA_RX_SEQ_SV

//==============================================================================
// RX Descriptor Ring Setup Sequence
//==============================================================================
class dma_rx_setup_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_rx_setup_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int num_descriptors = 16;
    int buffer_size = 2048;
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_rx_setup_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        bit [63:0] buf_addr;
        
        `uvm_info("DMA_RX", $sformatf("Setting up RX ring: %0d descriptors, %0d byte buffers",
            num_descriptors, buffer_size), UVM_MEDIUM)
        
        // Create all RX descriptors with buffers
        for (int i = 0; i < num_descriptors; i++) begin
            buf_addr = rx_buf_base + (i * buffer_size);
            
            create_rx_descriptor(
                .index(i),
                .buf_addr(buf_addr),
                .buf_length(buffer_size),
                .set_own(1)  // DMA owns all buffers initially
            );
        end
        
        // Update tail pointer to indicate all descriptors are available
        write_reg(DMA_RX_TAIL, num_descriptors);
        
        `uvm_info("DMA_RX", "RX descriptor ring initialized", UVM_MEDIUM)
    endtask
    
endclass : dma_rx_setup_seq


//==============================================================================
// RX Wait for Packet Sequence
//==============================================================================
class dma_rx_wait_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_rx_wait_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int num_packets_expected = 1;
    int timeout_us = 10000;
    
    //--------------------------------------------------------------------------
    // Received Packets
    //--------------------------------------------------------------------------
    bit [7:0] received_packets[$][$];
    int received_lengths[$];
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_rx_wait_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        bit [31:0] head;
        bit [31:0] prev_head;
        bit [63:0] desc_addr;
        bit [31:0] status;
        bit [63:0] buf_addr;
        int pkt_len;
        bit [7:0] pkt_data[$];
        int wait_count = 0;
        int packets_received = 0;
        
        `uvm_info("DMA_RX", $sformatf("Waiting for %0d packets", num_packets_expected), UVM_MEDIUM)
        
        // Get initial head pointer
        read_reg(DMA_RX_HEAD, prev_head);
        received_packets.delete();
        received_lengths.delete();
        
        do begin
            read_reg(DMA_RX_HEAD, head);
            
            // Check for new completions
            while (prev_head != head) begin
                desc_addr = rx_desc_base + (prev_head * 16);
                
                // Read descriptor status
                status = read_descriptor_status(desc_addr);
                
                if (status[DESC_DONE_BIT]) begin
                    // Get buffer address from descriptor
                    buf_addr = 0;
                    buf_addr[7:0]   = mem.read_byte(desc_addr + 0);
                    buf_addr[15:8]  = mem.read_byte(desc_addr + 1);
                    buf_addr[23:16] = mem.read_byte(desc_addr + 2);
                    buf_addr[31:24] = mem.read_byte(desc_addr + 3);
                    buf_addr[39:32] = mem.read_byte(desc_addr + 4);
                    buf_addr[47:40] = mem.read_byte(desc_addr + 5);
                    buf_addr[55:48] = mem.read_byte(desc_addr + 6);
                    buf_addr[63:56] = mem.read_byte(desc_addr + 7);
                    
                    // Get received length from descriptor
                    pkt_len = {mem.read_byte(desc_addr + 9), mem.read_byte(desc_addr + 8)};
                    
                    // Read packet data
                    read_packet_buffer(buf_addr, pkt_len, pkt_data);
                    received_packets.push_back(pkt_data);
                    received_lengths.push_back(pkt_len);
                    packets_received++;
                    
                    `uvm_info("DMA_RX", $sformatf("Received packet %0d: length=%0d status=0x%08h",
                        packets_received, pkt_len, status), UVM_MEDIUM)
                    
                    if (status[DESC_ERR_BIT])
                        `uvm_warning("DMA_RX", "Packet received with error flag")
                end
                
                prev_head = (prev_head + 1) % rx_desc_count;
            end
            
            if (packets_received >= num_packets_expected) begin
                `uvm_info("DMA_RX", $sformatf("Received all %0d expected packets", packets_received), UVM_MEDIUM)
                return;
            end
            
            #1us;
            wait_count++;
        end while (wait_count < timeout_us);
        
        `uvm_error("DMA_RX", $sformatf("Timeout: received %0d of %0d expected packets",
            packets_received, num_packets_expected))
    endtask
    
endclass : dma_rx_wait_seq


//==============================================================================
// RX Buffer Replenish Sequence
//==============================================================================
class dma_rx_replenish_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_rx_replenish_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int start_index;
    int num_buffers;
    int buffer_size = 2048;
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_rx_replenish_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        bit [63:0] buf_addr;
        bit [31:0] tail;
        
        `uvm_info("DMA_RX", $sformatf("Replenishing %0d RX buffers starting at index %0d",
            num_buffers, start_index), UVM_MEDIUM)
        
        for (int i = 0; i < num_buffers; i++) begin
            int idx = (start_index + i) % rx_desc_count;
            buf_addr = rx_buf_base + (idx * buffer_size);
            
            // Re-create descriptor with OWN bit set
            create_rx_descriptor(
                .index(idx),
                .buf_addr(buf_addr),
                .buf_length(buffer_size),
                .set_own(1)
            );
        end
        
        // Update tail pointer
        read_reg(DMA_RX_TAIL, tail);
        tail = (tail + num_buffers) % rx_desc_count;
        write_reg(DMA_RX_TAIL, tail);
        
        `uvm_info("DMA_RX", $sformatf("RX tail updated to %0d", tail), UVM_MEDIUM)
    endtask
    
endclass : dma_rx_replenish_seq


//==============================================================================
// RX Interrupt Handling Sequence
//==============================================================================
class dma_rx_irq_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_rx_irq_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int timeout_us = 10000;
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_rx_irq_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body - Wait for RX interrupt and process
    //--------------------------------------------------------------------------
    task body();
        bit [31:0] irq_status;
        int wait_count = 0;
        
        `uvm_info("DMA_RX", "Waiting for RX interrupt", UVM_MEDIUM)
        
        // Poll for interrupt
        do begin
            read_reg(DMA_IRQ_STATUS, irq_status);
            
            if (irq_status & 32'h0000_0002) begin  // RX done
                `uvm_info("DMA_RX", "RX interrupt received", UVM_MEDIUM)
                
                // Clear interrupt
                write_reg(DMA_IRQ_STATUS, 32'h0000_0002);
                
                // Process received packets
                process_rx_completions();
                return;
            end
            
            #1us;
            wait_count++;
        end while (wait_count < timeout_us);
        
        `uvm_error("DMA_RX", "Timeout waiting for RX interrupt")
    endtask
    
    //--------------------------------------------------------------------------
    // Process RX Completions
    //--------------------------------------------------------------------------
    task process_rx_completions();
        bit [31:0] head;
        bit [31:0] tail;
        bit [64:0] desc_addr;
        bit [31:0] status;
        int processed = 0;
        
        read_reg(DMA_RX_HEAD, head);
        read_reg(DMA_RX_TAIL, tail);
        
        // Process all completed descriptors
        while (head != tail) begin
            desc_addr = rx_desc_base + (head * 16);
            status = read_descriptor_status(desc_addr);
            
            if (!status[DESC_OWN_BIT] && status[DESC_DONE_BIT]) begin
                `uvm_info("DMA_RX", $sformatf("Processing RX desc[%0d]", head), UVM_HIGH)
                processed++;
            end else begin
                break;  // Stop at first non-completed descriptor
            end
            
            head = (head + 1) % rx_desc_count;
        end
        
        `uvm_info("DMA_RX", $sformatf("Processed %0d RX completions", processed), UVM_MEDIUM)
    endtask
    
endclass : dma_rx_irq_seq


//==============================================================================
// RX Stress Test Sequence
//==============================================================================
class dma_rx_stress_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_rx_stress_seq)
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    int num_packets = 100;
    int min_packet_len = 64;
    int max_packet_len = 1518;
    int replenish_threshold = 4;  // Replenish when this many buffers consumed
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_rx_stress_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        dma_rx_setup_seq setup_seq;
        dma_rx_replenish_seq replenish_seq;
        bit [31:0] head;
        bit [31:0] prev_head;
        int consumed = 0;
        int total_received = 0;
        
        `uvm_info("DMA_RX", $sformatf("Starting RX stress test: %0d packets", num_packets), UVM_MEDIUM)
        
        // Setup RX ring
        setup_seq = dma_rx_setup_seq::type_id::create("setup_seq");
        setup_seq.mem = mem;
        setup_seq.rx_desc_base = rx_desc_base;
        setup_seq.rx_desc_count = rx_desc_count;
        setup_seq.rx_buf_base = rx_buf_base;
        setup_seq.start(null);
        
        // Get initial head
        read_reg(DMA_RX_HEAD, prev_head);
        
        // Main receive loop
        while (total_received < num_packets) begin
            read_reg(DMA_RX_HEAD, head);
            
            // Count consumed buffers
            while (prev_head != head) begin
                consumed++;
                total_received++;
                prev_head = (prev_head + 1) % rx_desc_count;
                
                `uvm_info("DMA_RX", $sformatf("Received packet %0d", total_received), UVM_HIGH)
            end
            
            // Replenish if threshold reached
            if (consumed >= replenish_threshold) begin
                replenish_seq = dma_rx_replenish_seq::type_id::create("replenish_seq");
                replenish_seq.mem = mem;
                replenish_seq.rx_desc_base = rx_desc_base;
                replenish_seq.rx_desc_count = rx_desc_count;
                replenish_seq.rx_buf_base = rx_buf_base;
                replenish_seq.start_index = (head + rx_desc_count - consumed) % rx_desc_count;
                replenish_seq.num_buffers = consumed;
                replenish_seq.start(null);
                consumed = 0;
            end
            
            #100ns;
        end
        
        `uvm_info("DMA_RX", $sformatf("RX stress test complete: %0d packets received", total_received), UVM_MEDIUM)
    endtask
    
endclass : dma_rx_stress_seq

`endif // DMA_RX_SEQ_SV
