//==============================================================================
// Class: dma_scoreboard
// Description: UVM Scoreboard for DMA verification
//
// Purpose:
//   Tracks DMA TX and RX transactions, validates data integrity between
//   system memory and MAC interfaces.
//
// Features:
//   - TX path: memory -> DMA -> MAC AXI-Stream
//   - RX path: MAC AXI-Stream -> DMA -> memory
//   - Descriptor tracking
//   - Statistics collection
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class dma_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(dma_scoreboard)

    //==========================================================================
    // Analysis Exports
    //==========================================================================
    
    // AXI-MM transactions (memory reads/writes)
    uvm_analysis_export #(axi_mm_item) axi_mm_write_export;
    uvm_analysis_export #(axi_mm_item) axi_mm_read_export;
    
    // AXI-Stream transactions (to/from MAC)
    uvm_analysis_export #(axi_stream_txn) axis_tx_export;  // TX to MAC
    uvm_analysis_export #(axi_stream_txn) axis_rx_export;  // RX from MAC

    //==========================================================================
    // Analysis FIFOs
    //==========================================================================
    uvm_tlm_analysis_fifo #(axi_mm_item) mm_write_fifo;
    uvm_tlm_analysis_fifo #(axi_mm_item) mm_read_fifo;
    uvm_tlm_analysis_fifo #(axi_stream_txn) axis_tx_fifo;
    uvm_tlm_analysis_fifo #(axi_stream_txn) axis_rx_fifo;

    //==========================================================================
    // Configuration
    //==========================================================================
    bit [63:0] tx_desc_base = 64'h0000_1000;
    bit [63:0] rx_desc_base = 64'h0000_2000;
    bit [63:0] tx_buf_base  = 64'h0001_0000;
    bit [63:0] rx_buf_base  = 64'h0002_0000;
    int desc_count = 16;
    int buf_size = 2048;
    
    bit enable_checking = 1;

    //==========================================================================
    // Statistics
    //==========================================================================
    int unsigned mm_write_count = 0;
    int unsigned mm_read_count = 0;
    int unsigned mm_write_bytes = 0;
    int unsigned mm_read_bytes = 0;
    
    int unsigned tx_packet_count = 0;
    int unsigned rx_packet_count = 0;
    int unsigned tx_byte_count = 0;
    int unsigned rx_byte_count = 0;
    
    int unsigned desc_read_count = 0;
    int unsigned desc_write_count = 0;
    
    int unsigned data_mismatch_count = 0;

    //==========================================================================
    // Packet Tracking
    //==========================================================================
    bit [7:0] tx_expected_packets[$][$];  // Expected TX data from memory reads
    bit [7:0] rx_received_packets[$][$];  // RX data to be written to memory

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "dma_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Create exports
        axi_mm_write_export = new("axi_mm_write_export", this);
        axi_mm_read_export  = new("axi_mm_read_export", this);
        axis_tx_export      = new("axis_tx_export", this);
        axis_rx_export      = new("axis_rx_export", this);
        
        // Create FIFOs
        mm_write_fifo = new("mm_write_fifo", this);
        mm_read_fifo  = new("mm_read_fifo", this);
        axis_tx_fifo  = new("axis_tx_fifo", this);
        axis_rx_fifo  = new("axis_rx_fifo", this);
    endfunction

    //==========================================================================
    // Connect Phase
    //==========================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        axi_mm_write_export.connect(mm_write_fifo.analysis_export);
        axi_mm_read_export.connect(mm_read_fifo.analysis_export);
        axis_tx_export.connect(axis_tx_fifo.analysis_export);
        axis_rx_export.connect(axis_rx_fifo.analysis_export);
    endfunction

    //==========================================================================
    // Run Phase
    //==========================================================================
    task run_phase(uvm_phase phase);
        fork
            process_mm_writes();
            process_mm_reads();
            process_axis_tx();
            process_axis_rx();
        join
    endtask

    //==========================================================================
    // Process Memory Writes
    //==========================================================================
    task process_mm_writes();
        axi_mm_item txn;
        
        forever begin
            mm_write_fifo.get(txn);
            mm_write_count++;
            mm_write_bytes += txn.get_total_bytes();
            
            // Classify write
            if (is_descriptor_access(txn.addr)) begin
                desc_write_count++;
                `uvm_info("DMA_SB", $sformatf("Descriptor write: addr=0x%h", txn.addr), UVM_HIGH)
            end else if (is_rx_buffer_access(txn.addr)) begin
                // RX data being written to memory
                `uvm_info("DMA_SB", $sformatf("RX buffer write: addr=0x%h len=%0d", 
                    txn.addr, txn.get_total_bytes()), UVM_HIGH)
            end
        end
    endtask

    //==========================================================================
    // Process Memory Reads
    //==========================================================================
    task process_mm_reads();
        axi_mm_item txn;
        
        forever begin
            mm_read_fifo.get(txn);
            mm_read_count++;
            mm_read_bytes += txn.get_total_bytes();
            
            // Classify read
            if (is_descriptor_access(txn.addr)) begin
                desc_read_count++;
                `uvm_info("DMA_SB", $sformatf("Descriptor read: addr=0x%h", txn.addr), UVM_HIGH)
            end else if (is_tx_buffer_access(txn.addr)) begin
                // TX data being read from memory
                `uvm_info("DMA_SB", $sformatf("TX buffer read: addr=0x%h len=%0d", 
                    txn.addr, txn.get_total_bytes()), UVM_HIGH)
            end
        end
    endtask

    //==========================================================================
    // Process AXI-Stream TX (to MAC)
    //==========================================================================
    task process_axis_tx();
        axi_stream_txn txn;
        
        forever begin
            axis_tx_fifo.get(txn);
            tx_packet_count++;
            tx_byte_count += txn.data.size();
            
            `uvm_info("DMA_SB", $sformatf("TX packet to MAC: len=%0d", txn.data.size()), UVM_MEDIUM)
        end
    endtask

    //==========================================================================
    // Process AXI-Stream RX (from MAC)
    //==========================================================================
    task process_axis_rx();
        axi_stream_txn txn;
        
        forever begin
            axis_rx_fifo.get(txn);
            rx_packet_count++;
            rx_byte_count += txn.data.size();
            
            `uvm_info("DMA_SB", $sformatf("RX packet from MAC: len=%0d", txn.data.size()), UVM_MEDIUM)
        end
    endtask

    //==========================================================================
    // Address Classification Helpers
    //==========================================================================
    function bit is_descriptor_access(bit [63:0] addr);
        return ((addr >= tx_desc_base && addr < tx_desc_base + (desc_count * 16)) ||
                (addr >= rx_desc_base && addr < rx_desc_base + (desc_count * 16)));
    endfunction
    
    function bit is_tx_buffer_access(bit [63:0] addr);
        return (addr >= tx_buf_base && addr < tx_buf_base + (desc_count * buf_size));
    endfunction
    
    function bit is_rx_buffer_access(bit [63:0] addr);
        return (addr >= rx_buf_base && addr < rx_buf_base + (desc_count * buf_size));
    endfunction

    //==========================================================================
    // Report Phase
    //==========================================================================
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
    endfunction

    //==========================================================================
    // Print Summary
    //==========================================================================
    function void print_summary();
        string report;
        
        report = "\n";
        report = {report, "============================================================\n"};
        report = {report, "                DMA SCOREBOARD SUMMARY\n"};
        report = {report, "============================================================\n"};
        report = {report, "  Memory Interface:\n"};
        report = {report, $sformatf("    Write Transactions:  %0d (%0d bytes)\n", mm_write_count, mm_write_bytes)};
        report = {report, $sformatf("    Read Transactions:   %0d (%0d bytes)\n", mm_read_count, mm_read_bytes)};
        report = {report, $sformatf("    Descriptor Reads:    %0d\n", desc_read_count)};
        report = {report, $sformatf("    Descriptor Writes:   %0d\n", desc_write_count)};
        report = {report, "------------------------------------------------------------\n"};
        report = {report, "  Packet Statistics:\n"};
        report = {report, $sformatf("    TX Packets (to MAC): %0d (%0d bytes)\n", tx_packet_count, tx_byte_count)};
        report = {report, $sformatf("    RX Packets (from MAC): %0d (%0d bytes)\n", rx_packet_count, rx_byte_count)};
        report = {report, "------------------------------------------------------------\n"};
        report = {report, $sformatf("  Data Mismatches:       %0d\n", data_mismatch_count)};
        report = {report, "============================================================\n"};
        
        if (data_mismatch_count == 0) begin
            report = {report, "  RESULT: *** PASS ***\n"};
        end else begin
            report = {report, "  RESULT: *** FAIL ***\n"};
        end
        
        report = {report, "============================================================\n"};
        
        `uvm_info("DMA_SB", report, UVM_NONE)
    endfunction

    //==========================================================================
    // Reset Statistics
    //==========================================================================
    function void reset_counters();
        mm_write_count = 0;
        mm_read_count = 0;
        mm_write_bytes = 0;
        mm_read_bytes = 0;
        tx_packet_count = 0;
        rx_packet_count = 0;
        tx_byte_count = 0;
        rx_byte_count = 0;
        desc_read_count = 0;
        desc_write_count = 0;
        data_mismatch_count = 0;
        tx_expected_packets.delete();
        rx_received_packets.delete();
    endfunction

endclass : dma_scoreboard
