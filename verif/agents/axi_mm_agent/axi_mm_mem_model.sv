//==============================================================================
// AXI4 Memory Model - Associative Array Based
//==============================================================================

`ifndef AXI_MM_MEM_MODEL_SV
`define AXI_MM_MEM_MODEL_SV

class axi_mm_mem_model extends uvm_object;
    
    //--------------------------------------------------------------------------
    // Memory Storage (byte-addressable)
    //--------------------------------------------------------------------------
    bit [7:0] mem[bit [AXI_ADDR_WIDTH-1:0]];
    
    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------
    bit         initialized;
    bit [7:0]   default_value;
    
    // Error injection
    bit         inject_error;
    bit [AXI_ADDR_WIDTH-1:0] error_addr_start;
    bit [AXI_ADDR_WIDTH-1:0] error_addr_end;
    
    `uvm_object_utils_begin(axi_mm_mem_model)
        `uvm_field_int(default_value, UVM_ALL_ON)
        `uvm_field_int(inject_error, UVM_ALL_ON)
        `uvm_field_int(error_addr_start, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(error_addr_end, UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "axi_mm_mem_model");
        super.new(name);
        default_value = 8'hXX;
        inject_error = 0;
    endfunction
    
    //--------------------------------------------------------------------------
    // Clear Memory
    //--------------------------------------------------------------------------
    function void clear();
        mem.delete();
        `uvm_info("MEM_MODEL", "Memory cleared", UVM_MEDIUM)
    endfunction
    
    //--------------------------------------------------------------------------
    // Write Single Byte
    //--------------------------------------------------------------------------
    function void write_byte(bit [AXI_ADDR_WIDTH-1:0] addr, bit [7:0] data);
        mem[addr] = data;
    endfunction
    
    //--------------------------------------------------------------------------
    // Read Single Byte
    //--------------------------------------------------------------------------
    function bit [7:0] read_byte(bit [AXI_ADDR_WIDTH-1:0] addr);
        if (mem.exists(addr))
            return mem[addr];
        else
            return default_value;
    endfunction
    
    //--------------------------------------------------------------------------
    // Write Data Beat (with strobes)
    //--------------------------------------------------------------------------
    function void write_beat(
        bit [AXI_ADDR_WIDTH-1:0] addr,
        bit [AXI_DATA_WIDTH-1:0] data,
        bit [AXI_STRB_WIDTH-1:0] strb
    );
        for (int i = 0; i < AXI_STRB_WIDTH; i++) begin
            if (strb[i]) begin
                mem[addr + i] = data[i*8 +: 8];
            end
        end
    endfunction
    
    //--------------------------------------------------------------------------
    // Read Data Beat
    //--------------------------------------------------------------------------
    function bit [AXI_DATA_WIDTH-1:0] read_beat(bit [AXI_ADDR_WIDTH-1:0] addr);
        bit [AXI_DATA_WIDTH-1:0] data;
        for (int i = 0; i < AXI_STRB_WIDTH; i++) begin
            data[i*8 +: 8] = read_byte(addr + i);
        end
        return data;
    endfunction
    
    //--------------------------------------------------------------------------
    // Process AXI Write Transaction
    //--------------------------------------------------------------------------
    function bit [1:0] process_write(axi_mm_item txn);
        bit [AXI_ADDR_WIDTH-1:0] beat_addr;
        
        // Check for error injection
        if (inject_error && 
            txn.addr >= error_addr_start && 
            txn.addr <= error_addr_end) begin
            return 2'b10;  // SLVERR
        end
        
        for (int beat = 0; beat <= txn.len; beat++) begin
            beat_addr = txn.get_beat_addr(beat);
            // Align address to size
            beat_addr = beat_addr & ~((1 << txn.size) - 1);
            
            if (beat < txn.data.size() && beat < txn.strb.size()) begin
                write_beat(beat_addr, txn.data[beat], txn.strb[beat]);
                `uvm_info("MEM_MODEL", $sformatf("Write[%0d]: addr=0x%h data=0x%h strb=0x%h", 
                    beat, beat_addr, txn.data[beat], txn.strb[beat]), UVM_HIGH)
            end
        end
        
        return 2'b00;  // OKAY
    endfunction
    
    //--------------------------------------------------------------------------
    // Process AXI Read Transaction
    //--------------------------------------------------------------------------
    function bit [1:0] process_read(ref axi_mm_item txn);
        bit [AXI_ADDR_WIDTH-1:0] beat_addr;
        
        // Check for error injection
        if (inject_error && 
            txn.addr >= error_addr_start && 
            txn.addr <= error_addr_end) begin
            return 2'b10;  // SLVERR
        end
        
        txn.data.delete();
        
        for (int beat = 0; beat <= txn.len; beat++) begin
            beat_addr = txn.get_beat_addr(beat);
            // Align address to size
            beat_addr = beat_addr & ~((1 << txn.size) - 1);
            
            txn.data.push_back(read_beat(beat_addr));
            `uvm_info("MEM_MODEL", $sformatf("Read[%0d]: addr=0x%h data=0x%h", 
                beat, beat_addr, txn.data[beat]), UVM_HIGH)
        end
        
        return 2'b00;  // OKAY
    endfunction
    
    //--------------------------------------------------------------------------
    // Load Memory from File
    //--------------------------------------------------------------------------
    function void load_from_file(string filename, bit [AXI_ADDR_WIDTH-1:0] base_addr = 0);
        int fd;
        bit [7:0] byte_val;
        bit [AXI_ADDR_WIDTH-1:0] addr = base_addr;
        
        fd = $fopen(filename, "rb");
        if (fd == 0) begin
            `uvm_error("MEM_MODEL", $sformatf("Cannot open file: %s", filename))
            return;
        end
        
        while (!$feof(fd)) begin
            if ($fread(byte_val, fd) == 1) begin
                mem[addr] = byte_val;
                addr++;
            end
        end
        
        $fclose(fd);
        `uvm_info("MEM_MODEL", $sformatf("Loaded %0d bytes from %s to addr 0x%h", 
            addr - base_addr, filename, base_addr), UVM_MEDIUM)
    endfunction
    
    //--------------------------------------------------------------------------
    // Dump Memory to File
    //--------------------------------------------------------------------------
    function void dump_to_file(
        string filename, 
        bit [AXI_ADDR_WIDTH-1:0] start_addr,
        int size
    );
        int fd;
        
        fd = $fopen(filename, "wb");
        if (fd == 0) begin
            `uvm_error("MEM_MODEL", $sformatf("Cannot create file: %s", filename))
            return;
        end
        
        for (int i = 0; i < size; i++) begin
            $fwrite(fd, "%c", read_byte(start_addr + i));
        end
        
        $fclose(fd);
        `uvm_info("MEM_MODEL", $sformatf("Dumped %0d bytes from addr 0x%h to %s", 
            size, start_addr, filename), UVM_MEDIUM)
    endfunction
    
    //--------------------------------------------------------------------------
    // Set Error Injection Region
    //--------------------------------------------------------------------------
    function void set_error_region(
        bit [AXI_ADDR_WIDTH-1:0] start_addr,
        bit [AXI_ADDR_WIDTH-1:0] end_addr
    );
        error_addr_start = start_addr;
        error_addr_end = end_addr;
        inject_error = 1;
        `uvm_info("MEM_MODEL", $sformatf("Error injection enabled: 0x%h - 0x%h", 
            start_addr, end_addr), UVM_MEDIUM)
    endfunction
    
    //--------------------------------------------------------------------------
    // Clear Error Injection
    //--------------------------------------------------------------------------
    function void clear_error_region();
        inject_error = 0;
        `uvm_info("MEM_MODEL", "Error injection disabled", UVM_MEDIUM)
    endfunction
    
    //--------------------------------------------------------------------------
    // Print Memory Contents (for debug)
    //--------------------------------------------------------------------------
    function void print_region(
        bit [AXI_ADDR_WIDTH-1:0] start_addr, 
        int size
    );
        string s;
        s = $sformatf("\n===== Memory Region [0x%h - 0x%h] =====\n", 
            start_addr, start_addr + size - 1);
        
        for (int i = 0; i < size; i += 16) begin
            s = {s, $sformatf("0x%08h: ", start_addr + i)};
            for (int j = 0; j < 16 && (i+j) < size; j++) begin
                s = {s, $sformatf("%02h ", read_byte(start_addr + i + j))};
            end
            s = {s, "\n"};
        end
        
        `uvm_info("MEM_MODEL", s, UVM_MEDIUM)
    endfunction
    
    //--------------------------------------------------------------------------
    // Compare Memory Region with Expected
    //--------------------------------------------------------------------------
    function bit compare_region(
        bit [AXI_ADDR_WIDTH-1:0] addr,
        bit [7:0] expected[$],
        output int first_mismatch
    );
        for (int i = 0; i < expected.size(); i++) begin
            if (read_byte(addr + i) !== expected[i]) begin
                first_mismatch = i;
                `uvm_error("MEM_MODEL", $sformatf(
                    "Memory mismatch at addr 0x%h: expected=0x%h, actual=0x%h",
                    addr + i, expected[i], read_byte(addr + i)))
                return 0;
            end
        end
        return 1;
    endfunction
    
endclass : axi_mm_mem_model

`endif // AXI_MM_MEM_MODEL_SV
