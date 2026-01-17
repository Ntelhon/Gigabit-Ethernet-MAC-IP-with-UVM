//==============================================================================
// File: dma_base_test.sv
// Description: Base test class for DMA verification tests
//==============================================================================

class dma_base_test extends mac_base_test;

    `uvm_component_utils(dma_base_test)

    //--------------------------------------------------------------------------
    // AXI-MM Agent Handle
    //--------------------------------------------------------------------------
    axi_mm_agent mm_agent;
    
    //--------------------------------------------------------------------------
    // Test Configuration
    //--------------------------------------------------------------------------
    bit [63:0] tx_desc_base  = 64'h0000_1000;
    bit [63:0] rx_desc_base  = 64'h0000_2000;
    bit [63:0] tx_buf_base   = 64'h0001_0000;
    bit [63:0] rx_buf_base   = 64'h0002_0000;
    int        desc_count    = 16;
    int        buf_size      = 2048;

    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_base_test", uvm_component parent = null);
        super.new(name, parent);
        test_timeout = 500000;  // Longer timeout for DMA tests
    endfunction

    //--------------------------------------------------------------------------
    // Build Phase
    //--------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("DMA_TEST", "Building DMA base test", UVM_MEDIUM)
    endfunction

    //--------------------------------------------------------------------------
    // Configure DMA
    //--------------------------------------------------------------------------
    virtual task configure_dma(
        bit enable_tx = 1,
        bit enable_rx = 1,
        bit enable_irq = 1
    );
        `uvm_info("DMA_TEST", "Configuring DMA engine", UVM_MEDIUM)
        
        // Reset DMA
        env.axi_lite_agt.write(32'h0200, 32'h0000_0300);  // TX_RST | RX_RST
        #1us;
        env.axi_lite_agt.write(32'h0200, 32'h0000_0000);
        #1us;
        
        // Configure TX ring
        if (enable_tx) begin
            env.axi_lite_agt.write(32'h0210, tx_desc_base[31:0]);   // TX_DESC_LO
            env.axi_lite_agt.write(32'h0214, tx_desc_base[63:32]);  // TX_DESC_HI
            env.axi_lite_agt.write(32'h0218, desc_count);           // TX_DESC_SIZE
            env.axi_lite_agt.write(32'h021C, 0);                    // TX_HEAD
            env.axi_lite_agt.write(32'h0220, 0);                    // TX_TAIL
        end
        
        // Configure RX ring
        if (enable_rx) begin
            env.axi_lite_agt.write(32'h0240, rx_desc_base[31:0]);   // RX_DESC_LO
            env.axi_lite_agt.write(32'h0244, rx_desc_base[63:32]);  // RX_DESC_HI
            env.axi_lite_agt.write(32'h0248, desc_count);           // RX_DESC_SIZE
            env.axi_lite_agt.write(32'h024C, 0);                    // RX_HEAD
            env.axi_lite_agt.write(32'h0250, 0);                    // RX_TAIL
        end
        
        // Enable interrupts
        if (enable_irq) begin
            env.axi_lite_agt.write(32'h0208, 32'h0000_0303);  // TX/RX done + error
        end
        
        // Enable DMA
        begin
            bit [31:0] ctrl = 0;
            if (enable_tx) ctrl |= 32'h0000_0001;
            if (enable_rx) ctrl |= 32'h0000_0002;
            env.axi_lite_agt.write(32'h0200, ctrl);
        end
        
        `uvm_info("DMA_TEST", "DMA configuration complete", UVM_MEDIUM)
    endtask

    //--------------------------------------------------------------------------
    // Setup RX Buffers
    //--------------------------------------------------------------------------
    virtual task setup_rx_buffers(int num_buffers = -1);
        bit [63:0] desc_addr, buf_addr;
        bit [31:0] status;
        
        if (num_buffers < 0) num_buffers = desc_count;
        
        `uvm_info("DMA_TEST", $sformatf("Setting up %0d RX buffers", num_buffers), UVM_MEDIUM)
        
        for (int i = 0; i < num_buffers; i++) begin
            desc_addr = rx_desc_base + (i * 16);
            buf_addr = rx_buf_base + (i * buf_size);
            
            // Write descriptor to memory
            mm_agent.mem.write_byte(desc_addr + 0, buf_addr[7:0]);
            mm_agent.mem.write_byte(desc_addr + 1, buf_addr[15:8]);
            mm_agent.mem.write_byte(desc_addr + 2, buf_addr[23:16]);
            mm_agent.mem.write_byte(desc_addr + 3, buf_addr[31:24]);
            mm_agent.mem.write_byte(desc_addr + 4, buf_addr[39:32]);
            mm_agent.mem.write_byte(desc_addr + 5, buf_addr[47:40]);
            mm_agent.mem.write_byte(desc_addr + 6, buf_addr[55:48]);
            mm_agent.mem.write_byte(desc_addr + 7, buf_addr[63:56]);
            mm_agent.mem.write_byte(desc_addr + 8, buf_size[7:0]);
            mm_agent.mem.write_byte(desc_addr + 9, buf_size[15:8]);
            mm_agent.mem.write_byte(desc_addr + 10, 0);
            mm_agent.mem.write_byte(desc_addr + 11, 0);
            
            // Set OWN bit
            status = 32'h8000_0000;
            mm_agent.mem.write_byte(desc_addr + 12, status[7:0]);
            mm_agent.mem.write_byte(desc_addr + 13, status[15:8]);
            mm_agent.mem.write_byte(desc_addr + 14, status[23:16]);
            mm_agent.mem.write_byte(desc_addr + 15, status[31:24]);
        end
        
        // Update tail pointer
        env.axi_lite_agt.write(32'h0250, num_buffers);
    endtask

    //--------------------------------------------------------------------------
    // Queue TX Packet
    //--------------------------------------------------------------------------
    virtual task queue_tx_packet(bit [7:0] data[$], int desc_idx);
        bit [63:0] desc_addr, buf_addr;
        bit [31:0] status;
        
        desc_addr = tx_desc_base + (desc_idx * 16);
        buf_addr = tx_buf_base + (desc_idx * buf_size);
        
        // Write packet data
        foreach (data[i]) begin
            mm_agent.mem.write_byte(buf_addr + i, data[i]);
        end
        
        // Write descriptor
        mm_agent.mem.write_byte(desc_addr + 0, buf_addr[7:0]);
        mm_agent.mem.write_byte(desc_addr + 1, buf_addr[15:8]);
        mm_agent.mem.write_byte(desc_addr + 2, buf_addr[23:16]);
        mm_agent.mem.write_byte(desc_addr + 3, buf_addr[31:24]);
        mm_agent.mem.write_byte(desc_addr + 4, buf_addr[39:32]);
        mm_agent.mem.write_byte(desc_addr + 5, buf_addr[47:40]);
        mm_agent.mem.write_byte(desc_addr + 6, buf_addr[55:48]);
        mm_agent.mem.write_byte(desc_addr + 7, buf_addr[63:56]);
        mm_agent.mem.write_byte(desc_addr + 8, data.size()[7:0]);
        mm_agent.mem.write_byte(desc_addr + 9, data.size()[15:8]);
        mm_agent.mem.write_byte(desc_addr + 10, 0);
        mm_agent.mem.write_byte(desc_addr + 11, 0);
        
        // Set OWN | FIRST | LAST
        status = 32'h9800_0000;
        mm_agent.mem.write_byte(desc_addr + 12, status[7:0]);
        mm_agent.mem.write_byte(desc_addr + 13, status[15:8]);
        mm_agent.mem.write_byte(desc_addr + 14, status[23:16]);
        mm_agent.mem.write_byte(desc_addr + 15, status[31:24]);
        
        `uvm_info("DMA_TEST", $sformatf("Queued TX packet: desc=%0d len=%0d", desc_idx, data.size()), UVM_HIGH)
    endtask

    //--------------------------------------------------------------------------
    // Generate Test Packet
    //--------------------------------------------------------------------------
    function void generate_packet(int length, ref bit [7:0] data[$]);
        data.delete();
        // Ethernet header
        for (int i = 0; i < 6; i++) data.push_back(8'hFF);  // Dst MAC (broadcast)
        for (int i = 0; i < 6; i++) data.push_back(8'h00 + i);  // Src MAC
        data.push_back(8'h08); data.push_back(8'h00);  // EtherType
        // Payload
        for (int i = 14; i < length; i++) data.push_back(i[7:0]);
    endfunction

    //--------------------------------------------------------------------------
    // Wait for TX Complete
    //--------------------------------------------------------------------------
    virtual task wait_tx_complete(int timeout_us = 1000);
        bit [31:0] status;
        int count = 0;
        
        do begin
            env.axi_lite_agt.read(32'h020C, status);  // IRQ_STATUS
            if (status & 32'h0000_0001) begin
                env.axi_lite_agt.write(32'h020C, 32'h0000_0001);  // Clear
                `uvm_info("DMA_TEST", "TX complete interrupt received", UVM_MEDIUM)
                return;
            end
            #1us;
            count++;
        end while (count < timeout_us);
        
        `uvm_warning("DMA_TEST", "Timeout waiting for TX complete")
    endtask

    //--------------------------------------------------------------------------
    // Wait for RX Complete
    //--------------------------------------------------------------------------
    virtual task wait_rx_complete(int timeout_us = 1000);
        bit [31:0] status;
        int count = 0;
        
        do begin
            env.axi_lite_agt.read(32'h020C, status);  // IRQ_STATUS
            if (status & 32'h0000_0002) begin
                env.axi_lite_agt.write(32'h020C, 32'h0000_0002);  // Clear
                `uvm_info("DMA_TEST", "RX complete interrupt received", UVM_MEDIUM)
                return;
            end
            #1us;
            count++;
        end while (count < timeout_us);
        
        `uvm_warning("DMA_TEST", "Timeout waiting for RX complete")
    endtask

endclass : dma_base_test
