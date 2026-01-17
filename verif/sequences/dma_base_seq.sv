//==============================================================================
// DMA Base Sequence - Common utilities for DMA sequences
//==============================================================================

`ifndef DMA_BASE_SEQ_SV
`define DMA_BASE_SEQ_SV

class dma_base_seq extends uvm_sequence;
    
    `uvm_object_utils(dma_base_seq)
    `uvm_declare_p_sequencer(uvm_sequencer)
    
    //--------------------------------------------------------------------------
    // Sequencer Handles
    //--------------------------------------------------------------------------
    uvm_sequencer #(axi_lite_item) reg_sqr;
    
    //--------------------------------------------------------------------------
    // Memory Model Handle
    //--------------------------------------------------------------------------
    axi_mm_mem_model mem;
    
    //--------------------------------------------------------------------------
    // Descriptor Ring Configuration
    //--------------------------------------------------------------------------
    bit [63:0] tx_desc_base;
    bit [63:0] rx_desc_base;
    int        tx_desc_count;
    int        rx_desc_count;
    
    // Packet buffers (separate from descriptors)
    bit [63:0] tx_buf_base;
    bit [63:0] rx_buf_base;
    int        buf_size;
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_base_seq");
        super.new(name);
        
        // Default memory layout
        tx_desc_base  = 64'h0000_1000;  // TX descriptors at 4KB
        rx_desc_base  = 64'h0000_2000;  // RX descriptors at 8KB
        tx_desc_count = 16;
        rx_desc_count = 16;
        tx_buf_base   = 64'h0001_0000;  // TX buffers at 64KB
        rx_buf_base   = 64'h0002_0000;  // RX buffers at 128KB
        buf_size      = 2048;           // Per-packet buffer size
    endfunction
    
    //--------------------------------------------------------------------------
    // AXI-Lite Register Access
    //--------------------------------------------------------------------------
    
    task write_reg(bit [31:0] addr, bit [31:0] data);
        axi_lite_item txn;
        txn = axi_lite_item::type_id::create("reg_wr");
        txn.op = axi_lite_item::AXI_WRITE;
        txn.addr = addr;
        txn.data = data;
        txn.strb = 4'hF;
        start_item(txn);
        finish_item(txn);
        `uvm_info("DMA_SEQ", $sformatf("REG WRITE: addr=0x%08h data=0x%08h", addr, data), UVM_HIGH)
    endtask
    
    task read_reg(bit [31:0] addr, output bit [31:0] data);
        axi_lite_item txn;
        txn = axi_lite_item::type_id::create("reg_rd");
        txn.op = axi_lite_item::AXI_READ;
        txn.addr = addr;
        start_item(txn);
        finish_item(txn);
        data = txn.data;
        `uvm_info("DMA_SEQ", $sformatf("REG READ: addr=0x%08h data=0x%08h", addr, data), UVM_HIGH)
    endtask
    
    task poll_reg(bit [31:0] addr, bit [31:0] mask, bit [31:0] expected, int timeout_cycles = 1000);
        bit [31:0] data;
        int count = 0;
        
        do begin
            read_reg(addr, data);
            if ((data & mask) == expected) return;
            #100ns;
            count++;
        end while (count < timeout_cycles);
        
        `uvm_error("DMA_SEQ", $sformatf("Poll timeout: addr=0x%08h mask=0x%08h expected=0x%08h got=0x%08h",
            addr, mask, expected, data & mask))
    endtask
    
    //--------------------------------------------------------------------------
    // Descriptor Management
    //--------------------------------------------------------------------------
    
    // Create a TX descriptor in memory
    function void create_tx_descriptor(
        int index,
        bit [63:0] buf_addr,
        bit [15:0] length,
        bit is_first,
        bit is_last,
        bit set_own
    );
        bit [63:0] desc_addr = tx_desc_base + (index * 16);
        bit [31:0] status;
        
        // Word 0: addr_lo
        mem.write_byte(desc_addr + 0, buf_addr[7:0]);
        mem.write_byte(desc_addr + 1, buf_addr[15:8]);
        mem.write_byte(desc_addr + 2, buf_addr[23:16]);
        mem.write_byte(desc_addr + 3, buf_addr[31:24]);
        
        // Word 1: addr_hi
        mem.write_byte(desc_addr + 4, buf_addr[39:32]);
        mem.write_byte(desc_addr + 5, buf_addr[47:40]);
        mem.write_byte(desc_addr + 6, buf_addr[55:48]);
        mem.write_byte(desc_addr + 7, buf_addr[63:56]);
        
        // Word 2: length
        mem.write_byte(desc_addr + 8, length[7:0]);
        mem.write_byte(desc_addr + 9, length[15:8]);
        mem.write_byte(desc_addr + 10, 8'h00);
        mem.write_byte(desc_addr + 11, 8'h00);
        
        // Word 3: status
        status = 0;
        if (set_own)  status[DESC_OWN_BIT]   = 1;
        if (is_first) status[DESC_FIRST_BIT] = 1;
        if (is_last)  status[DESC_LAST_BIT]  = 1;
        
        mem.write_byte(desc_addr + 12, status[7:0]);
        mem.write_byte(desc_addr + 13, status[15:8]);
        mem.write_byte(desc_addr + 14, status[23:16]);
        mem.write_byte(desc_addr + 15, status[31:24]);
        
        `uvm_info("DMA_SEQ", $sformatf("TX Desc[%0d]: buf=0x%h len=%0d first=%0d last=%0d own=%0d",
            index, buf_addr, length, is_first, is_last, set_own), UVM_MEDIUM)
    endfunction
    
    // Create an RX descriptor in memory
    function void create_rx_descriptor(
        int index,
        bit [63:0] buf_addr,
        bit [15:0] buf_length,
        bit set_own
    );
        bit [63:0] desc_addr = rx_desc_base + (index * 16);
        bit [31:0] status;
        
        // Word 0: addr_lo
        mem.write_byte(desc_addr + 0, buf_addr[7:0]);
        mem.write_byte(desc_addr + 1, buf_addr[15:8]);
        mem.write_byte(desc_addr + 2, buf_addr[23:16]);
        mem.write_byte(desc_addr + 3, buf_addr[31:24]);
        
        // Word 1: addr_hi
        mem.write_byte(desc_addr + 4, buf_addr[39:32]);
        mem.write_byte(desc_addr + 5, buf_addr[47:40]);
        mem.write_byte(desc_addr + 6, buf_addr[55:48]);
        mem.write_byte(desc_addr + 7, buf_addr[63:56]);
        
        // Word 2: buffer length
        mem.write_byte(desc_addr + 8, buf_length[7:0]);
        mem.write_byte(desc_addr + 9, buf_length[15:8]);
        mem.write_byte(desc_addr + 10, 8'h00);
        mem.write_byte(desc_addr + 11, 8'h00);
        
        // Word 3: status (OWN bit set for RX)
        status = 0;
        if (set_own) status[DESC_OWN_BIT] = 1;
        
        mem.write_byte(desc_addr + 12, status[7:0]);
        mem.write_byte(desc_addr + 13, status[15:8]);
        mem.write_byte(desc_addr + 14, status[23:16]);
        mem.write_byte(desc_addr + 15, status[31:24]);
        
        `uvm_info("DMA_SEQ", $sformatf("RX Desc[%0d]: buf=0x%h len=%0d own=%0d",
            index, buf_addr, buf_length, set_own), UVM_MEDIUM)
    endfunction
    
    // Read descriptor status
    function bit [31:0] read_descriptor_status(bit [63:0] desc_addr);
        bit [31:0] status;
        status[7:0]   = mem.read_byte(desc_addr + 12);
        status[15:8]  = mem.read_byte(desc_addr + 13);
        status[23:16] = mem.read_byte(desc_addr + 14);
        status[31:24] = mem.read_byte(desc_addr + 15);
        return status;
    endfunction
    
    // Check if descriptor is done (OWN=0 and DONE=1)
    function bit is_descriptor_done(bit [63:0] desc_addr);
        bit [31:0] status = read_descriptor_status(desc_addr);
        return (!status[DESC_OWN_BIT] && status[DESC_DONE_BIT]);
    endfunction
    
    //--------------------------------------------------------------------------
    // Packet Buffer Management
    //--------------------------------------------------------------------------
    
    // Write packet data to TX buffer
    function void write_packet_buffer(bit [63:0] buf_addr, bit [7:0] data[$]);
        foreach (data[i]) begin
            mem.write_byte(buf_addr + i, data[i]);
        end
    endfunction
    
    // Read packet data from RX buffer
    function void read_packet_buffer(bit [63:0] buf_addr, int length, ref bit [7:0] data[$]);
        data.delete();
        for (int i = 0; i < length; i++) begin
            data.push_back(mem.read_byte(buf_addr + i));
        end
    endfunction
    
    // Generate random packet
    function void generate_random_packet(int length, ref bit [7:0] data[$]);
        data.delete();
        for (int i = 0; i < length; i++) begin
            data.push_back($urandom);
        end
    endfunction
    
    // Generate Ethernet frame (with proper header)
    function void generate_ethernet_frame(
        bit [47:0] dst_mac,
        bit [47:0] src_mac,
        bit [15:0] ethertype,
        int payload_length,
        ref bit [7:0] frame[$]
    );
        frame.delete();
        
        // Destination MAC
        frame.push_back(dst_mac[47:40]);
        frame.push_back(dst_mac[39:32]);
        frame.push_back(dst_mac[31:24]);
        frame.push_back(dst_mac[23:16]);
        frame.push_back(dst_mac[15:8]);
        frame.push_back(dst_mac[7:0]);
        
        // Source MAC
        frame.push_back(src_mac[47:40]);
        frame.push_back(src_mac[39:32]);
        frame.push_back(src_mac[31:24]);
        frame.push_back(src_mac[23:16]);
        frame.push_back(src_mac[15:8]);
        frame.push_back(src_mac[7:0]);
        
        // EtherType
        frame.push_back(ethertype[15:8]);
        frame.push_back(ethertype[7:0]);
        
        // Payload
        for (int i = 0; i < payload_length; i++) begin
            frame.push_back($urandom);
        end
    endfunction
    
endclass : dma_base_seq

`endif // DMA_BASE_SEQ_SV
