//==============================================================================
// DMA UVM Sequences
// Description: Sequences for testing DMA functionality
//
// This file contains sequences for:
// - TX packet setup and transmission via DMA
// - RX packet reception via DMA
// - Error injection scenarios
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

//==============================================================================
// Base DMA Sequence
//==============================================================================
class dma_base_seq extends uvm_sequence;
    `uvm_object_utils(dma_base_seq)

    // Descriptor format (128 bits)
    typedef struct packed {
        bit [15:0] status;        // [127:112] Status (written by DMA)
        bit [15:0] control;       // [111:96]  Control bits
        bit [15:0] reserved;      // [95:80]   Reserved
        bit [15:0] buffer_len;    // [79:64]   Buffer length
        bit [63:0] buffer_addr;   // [63:0]    Buffer address
    } eth_descriptor_t;

    // Control bits
    localparam DESC_OWN     = 16'h0001;  // Bit 0: DMA owns descriptor
    localparam DESC_LAST    = 16'h0002;  // Bit 1: Last descriptor
    localparam DESC_WRAP    = 16'h0002;  // Bit 1: Wrap (RX)
    localparam DESC_INT_EN  = 16'h0004;  // Bit 2: Interrupt enable

    function new(string name = "dma_base_seq");
        super.new(name);
    endfunction

    // Helper to create descriptor
    function eth_descriptor_t create_tx_desc(bit [63:0] addr, int len, bit last=1);
        eth_descriptor_t desc;
        desc.buffer_addr = addr;
        desc.buffer_len = len;
        desc.reserved = 0;
        desc.control = DESC_OWN | DESC_INT_EN;
        if (last) desc.control |= DESC_LAST;
        desc.status = 0;
        return desc;
    endfunction

    function eth_descriptor_t create_rx_desc(bit [63:0] addr, int len, bit wrap=0);
        eth_descriptor_t desc;
        desc.buffer_addr = addr;
        desc.buffer_len = len;
        desc.reserved = 0;
        desc.control = DESC_OWN | DESC_INT_EN;
        if (wrap) desc.control |= DESC_WRAP;
        desc.status = 0;
        return desc;
    endfunction

endclass : dma_base_seq

//==============================================================================
// DMA TX Packet Sequence
// Sets up descriptors and packet data in memory for TX DMA to read
//==============================================================================
class dma_tx_packet_seq extends dma_base_seq;
    `uvm_object_utils(dma_tx_packet_seq)

    rand bit [63:0] desc_base_addr;
    rand bit [63:0] buffer_addr;
    rand int packet_size;
    rand bit [7:0] packet_data[];

    constraint c_valid_size {
        packet_size inside {[64:1518]};
        packet_data.size() == packet_size;
    }

    constraint c_aligned_addr {
        desc_base_addr[3:0] == 4'h0;  // 16-byte aligned
        buffer_addr[2:0] == 3'h0;     // 8-byte aligned
    }

    function new(string name = "dma_tx_packet_seq");
        super.new(name);
    endfunction

    task body();
        axi4_mem_driver mem_driver;
        eth_descriptor_t desc;
        bit [7:0] data_queue[$];

        `uvm_info("DMA_TX_SEQ", $sformatf("Setting up TX packet: size=%0d addr=0x%0h", 
                  packet_size, buffer_addr), UVM_MEDIUM)

        // Get handle to memory driver
        if (!uvm_config_db#(axi4_mem_driver)::get(null, "", "mem_driver", mem_driver)) begin
            `uvm_fatal("NO_DRV", "Cannot get memory driver")
        end

        // Create descriptor
        desc = create_tx_desc(buffer_addr, packet_size, 1);

        // Write descriptor to memory (2 x 64-bit writes)
        data_queue = {};
        for (int i = 0; i < 8; i++) data_queue.push_back(desc[i*8 +: 8]);
        mem_driver.load_mem(desc_base_addr, data_queue);
        
        data_queue = {};
        for (int i = 0; i < 8; i++) data_queue.push_back(desc[64 + i*8 +: 8]);
        mem_driver.load_mem(desc_base_addr + 8, data_queue);

        // Write packet data to memory
        data_queue = {};
        foreach (packet_data[i]) data_queue.push_back(packet_data[i]);
        mem_driver.load_mem(buffer_addr, data_queue);

        `uvm_info("DMA_TX_SEQ", "TX packet setup complete", UVM_MEDIUM)
    endtask

endclass : dma_tx_packet_seq

//==============================================================================
// DMA RX Packet Sequence
// Sets up RX descriptors in memory for DMA to write received packets
//==============================================================================
class dma_rx_setup_seq extends dma_base_seq;
    `uvm_object_utils(dma_rx_setup_seq)

    rand bit [63:0] desc_base_addr;
    rand bit [63:0] buffer_addr[];
    rand int num_descriptors;
    int buffer_size = 2048;  // Standard RX buffer size

    constraint c_valid_count {
        num_descriptors inside {[1:16]};
        buffer_addr.size() == num_descriptors;
    }

    constraint c_aligned_addr {
        desc_base_addr[3:0] == 4'h0;
        foreach (buffer_addr[i]) {
            buffer_addr[i][2:0] == 3'h0;
        }
    }

    function new(string name = "dma_rx_setup_seq");
        super.new(name);
    endfunction

    task body();
        axi4_mem_driver mem_driver;
        eth_descriptor_t desc;
        bit [7:0] data_queue[$];

        `uvm_info("DMA_RX_SEQ", $sformatf("Setting up %0d RX descriptors", 
                  num_descriptors), UVM_MEDIUM)

        if (!uvm_config_db#(axi4_mem_driver)::get(null, "", "mem_driver", mem_driver)) begin
            `uvm_fatal("NO_DRV", "Cannot get memory driver")
        end

        // Create and write descriptors
        for (int i = 0; i < num_descriptors; i++) begin
            bit wrap = (i == num_descriptors - 1);
            desc = create_rx_desc(buffer_addr[i], buffer_size, wrap);

            // Write descriptor (2 x 64-bit writes)
            data_queue = {};
            for (int j = 0; j < 8; j++) data_queue.push_back(desc[j*8 +: 8]);
            mem_driver.load_mem(desc_base_addr + i*16, data_queue);
            
            data_queue = {};
            for (int j = 0; j < 8; j++) data_queue.push_back(desc[64 + j*8 +: 8]);
            mem_driver.load_mem(desc_base_addr + i*16 + 8, data_queue);
        end

        `uvm_info("DMA_RX_SEQ", "RX descriptors setup complete", UVM_MEDIUM)
    endtask

endclass : dma_rx_setup_seq

//==============================================================================
// DMA Error Injection Sequence
// Tests error scenarios (invalid descriptors, memory errors, etc.)
//==============================================================================
class dma_error_inject_seq extends dma_base_seq;
    `uvm_object_utils(dma_error_inject_seq)

    typedef enum {
        ERR_INVALID_ADDR,      // Descriptor with invalid address
        ERR_ZERO_LENGTH,       // Descriptor with zero length
        ERR_UNALIGNED_ADDR,    // Unaligned buffer address
        ERR_OWN_BIT_CLEAR      // Descriptor with OWN bit already clear
    } error_type_t;

    rand error_type_t error_type;
    rand bit [63:0] desc_base_addr;

    function new(string name = "dma_error_inject_seq");
        super.new(name);
    endfunction

    task body();
        axi4_mem_driver mem_driver;
        eth_descriptor_t desc;
        bit [7:0] data_queue[$];

        `uvm_info("DMA_ERR_SEQ", $sformatf("Injecting error type: %s", 
                  error_type.name()), UVM_MEDIUM)

        if (!uvm_config_db#(axi4_mem_driver)::get(null, "", "mem_driver", mem_driver)) begin
            `uvm_fatal("NO_DRV", "Cannot get memory driver")
        end

        // Create descriptor with error
        case (error_type)
            ERR_INVALID_ADDR: begin
                desc = create_tx_desc(64'hFFFF_FFFF_FFFF_0000, 64, 1);
            end
            ERR_ZERO_LENGTH: begin
                desc = create_tx_desc(64'h0000_1000, 0, 1);
            end
            ERR_UNALIGNED_ADDR: begin
                desc = create_tx_desc(64'h0000_1003, 64, 1);  // Unaligned
            end
            ERR_OWN_BIT_CLEAR: begin
                desc = create_tx_desc(64'h0000_1000, 64, 1);
                desc.control = desc.control & ~DESC_OWN;  // Clear OWN bit
            end
        endcase

        // Write descriptor to memory
        data_queue = {};
        for (int i = 0; i < 8; i++) data_queue.push_back(desc[i*8 +: 8]);
        mem_driver.load_mem(desc_base_addr, data_queue);
        
        data_queue = {};
        for (int i = 0; i < 8; i++) data_queue.push_back(desc[64 + i*8 +: 8]);
        mem_driver.load_mem(desc_base_addr + 8, data_queue);

        `uvm_info("DMA_ERR_SEQ", "Error injection complete", UVM_MEDIUM)
    endtask

endclass : dma_error_inject_seq

//==============================================================================
// DMA Configuration Sequence
// Programs DMA registers for operation
//==============================================================================
class dma_config_seq extends uvm_sequence #(axi_lite_txn);
    `uvm_object_utils(dma_config_seq)

    rand bit [63:0] tx_desc_base;
    rand bit [63:0] rx_desc_base;
    rand bit [7:0]  tx_ring_size;
    rand bit [7:0]  rx_ring_size;
    bit [31:0] base_addr = 32'h200;  // DMA registers at 0x200

    constraint c_ring_size {
        tx_ring_size inside {[6:10]};  // 64 to 1024 descriptors
        rx_ring_size inside {[6:10]};
    }

    function new(string name = "dma_config_seq");
        super.new(name);
    endfunction

    task body();
        axi_lite_txn txn;

        `uvm_info("DMA_CFG", "Configuring DMA registers", UVM_MEDIUM)

        // Write TX descriptor base (low)
        txn = axi_lite_txn::type_id::create("txn");
        txn.addr = base_addr + 32'h08;
        txn.data = tx_desc_base[31:0];
        txn.write = 1;
        start_item(txn);
        finish_item(txn);

        // Write TX descriptor base (high)
        txn = axi_lite_txn::type_id::create("txn");
        txn.addr = base_addr + 32'h0C;
        txn.data = tx_desc_base[63:32];
        txn.write = 1;
        start_item(txn);
        finish_item(txn);

        // Write TX ring size
        txn = axi_lite_txn::type_id::create("txn");
        txn.addr = base_addr + 32'h10;
        txn.data = {24'h0, tx_ring_size};
        txn.write = 1;
        start_item(txn);
        finish_item(txn);

        // Write RX descriptor base (low)
        txn = axi_lite_txn::type_id::create("txn");
        txn.addr = base_addr + 32'h14;
        txn.data = rx_desc_base[31:0];
        txn.write = 1;
        start_item(txn);
        finish_item(txn);

        // Write RX descriptor base (high)
        txn = axi_lite_txn::type_id::create("txn");
        txn.addr = base_addr + 32'h18;
        txn.data = rx_desc_base[63:32];
        txn.write = 1;
        start_item(txn);
        finish_item(txn);

        // Write RX ring size
        txn = axi_lite_txn::type_id::create("txn");
        txn.addr = base_addr + 32'h1C;
        txn.data = {24'h0, rx_ring_size};
        txn.write = 1;
        start_item(txn);
        finish_item(txn);

        // Enable DMA (TX_EN | RX_EN)
        txn = axi_lite_txn::type_id::create("txn");
        txn.addr = base_addr + 32'h00;
        txn.data = 32'h0000_0003;
        txn.write = 1;
        start_item(txn);
        finish_item(txn);

        `uvm_info("DMA_CFG", "DMA configuration complete", UVM_MEDIUM)
    endtask

endclass : dma_config_seq
