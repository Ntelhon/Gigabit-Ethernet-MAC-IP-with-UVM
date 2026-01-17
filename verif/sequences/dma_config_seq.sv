//==============================================================================
// DMA Configuration Sequence
//==============================================================================

`ifndef DMA_CONFIG_SEQ_SV
`define DMA_CONFIG_SEQ_SV

class dma_config_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_config_seq)
    
    //--------------------------------------------------------------------------
    // Configuration Options
    //--------------------------------------------------------------------------
    bit enable_tx = 1;
    bit enable_rx = 1;
    bit enable_tx_irq = 1;
    bit enable_rx_irq = 1;
    
    // Interrupt coalescing
    int tx_coal_count = 1;      // Packets before TX interrupt
    int tx_coal_timeout = 100;  // Cycles before TX interrupt timeout
    int rx_coal_count = 1;      // Packets before RX interrupt
    int rx_coal_timeout = 100;  // Cycles before RX interrupt timeout
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "dma_config_seq");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Body
    //--------------------------------------------------------------------------
    task body();
        bit [31:0] ctrl;
        bit [31:0] irq_en;
        bit [31:0] coal_val;
        
        `uvm_info("DMA_CFG", "Starting DMA configuration sequence", UVM_MEDIUM)
        
        // ========== Step 1: Reset DMA ==========
        `uvm_info("DMA_CFG", "Resetting DMA engine", UVM_MEDIUM)
        write_reg(DMA_CTRL, DMA_CTRL_TX_RST | DMA_CTRL_RX_RST);
        #1us;
        write_reg(DMA_CTRL, 32'h0);
        #1us;
        
        // ========== Step 2: Configure TX Descriptor Ring ==========
        if (enable_tx) begin
            `uvm_info("DMA_CFG", $sformatf("Configuring TX ring: base=0x%h count=%0d", 
                tx_desc_base, tx_desc_count), UVM_MEDIUM)
            
            write_reg(DMA_TX_DESC_LO, tx_desc_base[31:0]);
            write_reg(DMA_TX_DESC_HI, tx_desc_base[63:32]);
            write_reg(DMA_TX_DESC_SIZE, tx_desc_count);
            write_reg(DMA_TX_HEAD, 0);
            write_reg(DMA_TX_TAIL, 0);
        end
        
        // ========== Step 3: Configure RX Descriptor Ring ==========
        if (enable_rx) begin
            `uvm_info("DMA_CFG", $sformatf("Configuring RX ring: base=0x%h count=%0d", 
                rx_desc_base, rx_desc_count), UVM_MEDIUM)
            
            write_reg(DMA_RX_DESC_LO, rx_desc_base[31:0]);
            write_reg(DMA_RX_DESC_HI, rx_desc_base[63:32]);
            write_reg(DMA_RX_DESC_SIZE, rx_desc_count);
            write_reg(DMA_RX_HEAD, 0);
            write_reg(DMA_RX_TAIL, 0);
        end
        
        // ========== Step 4: Configure Interrupt Coalescing ==========
        `uvm_info("DMA_CFG", "Configuring interrupt coalescing", UVM_MEDIUM)
        
        coal_val = (tx_coal_timeout << 16) | tx_coal_count;
        write_reg(DMA_INT_COAL_TX, coal_val);
        
        coal_val = (rx_coal_timeout << 16) | rx_coal_count;
        write_reg(DMA_INT_COAL_RX, coal_val);
        
        // ========== Step 5: Enable Interrupts ==========
        irq_en = 0;
        if (enable_tx_irq) irq_en |= 32'h0000_0001;  // TX done IRQ
        if (enable_rx_irq) irq_en |= 32'h0000_0002;  // RX done IRQ
        irq_en |= 32'h0000_0100;  // TX error IRQ
        irq_en |= 32'h0000_0200;  // RX error IRQ
        
        `uvm_info("DMA_CFG", $sformatf("Enabling interrupts: mask=0x%08h", irq_en), UVM_MEDIUM)
        write_reg(DMA_IRQ_EN, irq_en);
        
        // ========== Step 6: Enable DMA Engines ==========
        ctrl = 0;
        if (enable_tx) ctrl |= DMA_CTRL_TX_EN;
        if (enable_rx) ctrl |= DMA_CTRL_RX_EN;
        
        `uvm_info("DMA_CFG", $sformatf("Enabling DMA: ctrl=0x%08h", ctrl), UVM_MEDIUM)
        write_reg(DMA_CTRL, ctrl);
        
        // ========== Step 7: Verify Configuration ==========
        verify_configuration();
        
        `uvm_info("DMA_CFG", "DMA configuration complete", UVM_MEDIUM)
    endtask
    
    //--------------------------------------------------------------------------
    // Verify Configuration
    //--------------------------------------------------------------------------
    task verify_configuration();
        bit [31:0] data;
        
        if (enable_tx) begin
            read_reg(DMA_TX_DESC_LO, data);
            if (data != tx_desc_base[31:0])
                `uvm_error("DMA_CFG", $sformatf("TX DESC_LO mismatch: exp=0x%h got=0x%h", 
                    tx_desc_base[31:0], data))
        end
        
        if (enable_rx) begin
            read_reg(DMA_RX_DESC_LO, data);
            if (data != rx_desc_base[31:0])
                `uvm_error("DMA_CFG", $sformatf("RX DESC_LO mismatch: exp=0x%h got=0x%h", 
                    rx_desc_base[31:0], data))
        end
        
        read_reg(DMA_CTRL, data);
        if (enable_tx && !(data & DMA_CTRL_TX_EN))
            `uvm_error("DMA_CFG", "TX engine not enabled")
        if (enable_rx && !(data & DMA_CTRL_RX_EN))
            `uvm_error("DMA_CFG", "RX engine not enabled")
    endtask
    
endclass : dma_config_seq


//==============================================================================
// DMA Reset Sequence
//==============================================================================
class dma_reset_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_reset_seq)
    
    function new(string name = "dma_reset_seq");
        super.new(name);
    endfunction
    
    task body();
        `uvm_info("DMA_RST", "Performing DMA reset", UVM_MEDIUM)
        
        // Disable DMA
        write_reg(DMA_CTRL, 32'h0);
        
        // Assert reset
        write_reg(DMA_CTRL, DMA_CTRL_TX_RST | DMA_CTRL_RX_RST);
        #1us;
        
        // Release reset
        write_reg(DMA_CTRL, 32'h0);
        #1us;
        
        // Clear any pending interrupts
        write_reg(DMA_IRQ_STATUS, 32'hFFFF_FFFF);
        
        `uvm_info("DMA_RST", "DMA reset complete", UVM_MEDIUM)
    endtask
    
endclass : dma_reset_seq


//==============================================================================
// DMA Disable Sequence
//==============================================================================
class dma_disable_seq extends dma_base_seq;
    
    `uvm_object_utils(dma_disable_seq)
    
    bit wait_for_idle = 1;
    int timeout_us = 100;
    
    function new(string name = "dma_disable_seq");
        super.new(name);
    endfunction
    
    task body();
        bit [31:0] status;
        int wait_count = 0;
        
        `uvm_info("DMA_DIS", "Disabling DMA", UVM_MEDIUM)
        
        // Disable DMA engines (graceful stop)
        write_reg(DMA_CTRL, 32'h0);
        
        // Wait for idle if requested
        if (wait_for_idle) begin
            do begin
                read_reg(DMA_STATUS, status);
                if ((status & 32'h0000_0003) == 0) begin  // TX_BUSY and RX_BUSY clear
                    `uvm_info("DMA_DIS", "DMA is now idle", UVM_MEDIUM)
                    return;
                end
                #1us;
                wait_count++;
            end while (wait_count < timeout_us);
            
            `uvm_warning("DMA_DIS", "Timeout waiting for DMA idle")
        end
    endtask
    
endclass : dma_disable_seq

`endif // DMA_CONFIG_SEQ_SV
