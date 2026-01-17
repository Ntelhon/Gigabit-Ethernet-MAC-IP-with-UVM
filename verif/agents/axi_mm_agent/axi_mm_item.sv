//==============================================================================
// AXI4 Memory Transaction Item
//==============================================================================

`ifndef AXI_MM_ITEM_SV
`define AXI_MM_ITEM_SV

class axi_mm_item extends uvm_sequence_item;
    
    //--------------------------------------------------------------------------
    // Transaction Type
    //--------------------------------------------------------------------------
    typedef enum {AXI_READ, AXI_WRITE} axi_op_e;
    
    rand axi_op_e               op;
    
    //--------------------------------------------------------------------------
    // Address Channel Fields
    //--------------------------------------------------------------------------
    rand bit [AXI_ADDR_WIDTH-1:0]   addr;
    rand bit [7:0]                  len;        // Burst length - 1
    rand bit [2:0]                  size;       // 2^size bytes per beat
    rand bit [1:0]                  burst;      // 0=FIXED, 1=INCR, 2=WRAP
    rand bit [AXI_ID_WIDTH-1:0]     id;
    
    //--------------------------------------------------------------------------
    // Data
    //--------------------------------------------------------------------------
    rand bit [AXI_DATA_WIDTH-1:0]   data[$];    // Queue of data beats
    rand bit [AXI_STRB_WIDTH-1:0]   strb[$];    // Queue of strobes (write only)
    
    //--------------------------------------------------------------------------
    // Response
    //--------------------------------------------------------------------------
    bit [1:0]                       resp;       // Response code
    
    //--------------------------------------------------------------------------
    // Timing (optional)
    //--------------------------------------------------------------------------
    int                             addr_delay;
    int                             data_delay;
    int                             resp_delay;
    
    //--------------------------------------------------------------------------
    // UVM Macros
    //--------------------------------------------------------------------------
    `uvm_object_utils_begin(axi_mm_item)
        `uvm_field_enum(axi_op_e, op, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(len, UVM_ALL_ON)
        `uvm_field_int(size, UVM_ALL_ON)
        `uvm_field_int(burst, UVM_ALL_ON)
        `uvm_field_int(id, UVM_ALL_ON)
        `uvm_field_queue_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_queue_int(strb, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(resp, UVM_ALL_ON)
    `uvm_object_utils_end
    
    //--------------------------------------------------------------------------
    // Constraints
    //--------------------------------------------------------------------------
    
    // Burst type constraint
    constraint burst_type_c {
        burst inside {2'b00, 2'b01, 2'b10};  // FIXED, INCR, WRAP
    }
    
    // Size constraint (up to bus width)
    constraint size_c {
        size <= $clog2(AXI_DATA_WIDTH/8);
    }
    
    // Burst length constraint
    constraint len_c {
        len <= 255;
        // For WRAP, len must be 1, 3, 7, or 15
        if (burst == 2'b10) {
            len inside {1, 3, 7, 15};
        }
    }
    
    // 4KB boundary constraint for INCR
    constraint boundary_c {
        if (burst == 2'b01) {  // INCR
            // Start address + total bytes should not cross 4KB
            ((addr & 12'hFFF) + ((len + 1) * (1 << size))) <= 4096;
        }
    }
    
    // Data queue size constraint
    constraint data_size_c {
        data.size() == len + 1;
        if (op == AXI_WRITE) {
            strb.size() == len + 1;
        }
    }
    
    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "axi_mm_item");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Helper Functions
    //--------------------------------------------------------------------------
    
    // Get total transfer size in bytes
    function int get_total_bytes();
        return (len + 1) * (1 << size);
    endfunction
    
    // Calculate address for beat N (INCR burst)
    function bit [AXI_ADDR_WIDTH-1:0] get_beat_addr(int beat_num);
        case (burst)
            2'b00: return addr;  // FIXED
            2'b01: return addr + (beat_num * (1 << size));  // INCR
            2'b10: begin  // WRAP
                int wrap_boundary = ((len + 1) * (1 << size));
                bit [AXI_ADDR_WIDTH-1:0] lower_addr = addr & ~(wrap_boundary - 1);
                bit [AXI_ADDR_WIDTH-1:0] upper_addr = lower_addr + wrap_boundary;
                bit [AXI_ADDR_WIDTH-1:0] result = addr + (beat_num * (1 << size));
                if (result >= upper_addr)
                    result = lower_addr + (result - upper_addr);
                return result;
            end
            default: return addr;
        endcase
    endfunction
    
    // Convert to string for debug
    function string convert2string();
        string s;
        s = $sformatf("\n===== AXI_MM_ITEM =====\n");
        s = {s, $sformatf("  OP:    %s\n", op.name())};
        s = {s, $sformatf("  ADDR:  0x%016h\n", addr)};
        s = {s, $sformatf("  LEN:   %0d (beats: %0d)\n", len, len+1)};
        s = {s, $sformatf("  SIZE:  %0d (bytes: %0d)\n", size, 1<<size)};
        s = {s, $sformatf("  BURST: %0d\n", burst)};
        s = {s, $sformatf("  ID:    %0d\n", id)};
        s = {s, $sformatf("  RESP:  %0d\n", resp)};
        if (data.size() > 0) begin
            s = {s, "  DATA:  "};
            foreach (data[i]) begin
                s = {s, $sformatf("[%0d]=0x%016h ", i, data[i])};
                if ((i+1) % 4 == 0 && i < data.size()-1) s = {s, "\n         "};
            end
            s = {s, "\n"};
        end
        return s;
    endfunction
    
endclass : axi_mm_item

`endif // AXI_MM_ITEM_SV
