//==============================================================================
// Class: axi4_mem_txn
// Description: AXI4 transaction for memory operations
//
// Supports both write and read transactions with burst capability
//==============================================================================

class axi4_mem_txn extends uvm_sequence_item;
    `uvm_object_utils(axi4_mem_txn)

    // Transaction type
    typedef enum {AXI4_WRITE, AXI4_READ} axi4_op_t;
    rand axi4_op_t op_type;

    // Address channel
    rand bit [63:0] addr;         // Address (parameterizable in agent)
    rand bit [7:0]  len;          // Burst length (0-255 beats)
    rand bit [2:0]  size;         // Burst size (bytes per beat)
    rand bit [1:0]  burst;        // Burst type (FIXED=0, INCR=1, WRAP=2)
    rand bit [3:0]  id;           // Transaction ID

    // Data
    rand bit [63:0] data[];       // Data array (size depends on len+1)
    rand bit [7:0]  strb[];       // Write strobe array

    // Response
    bit [1:0] resp;               // Response (OKAY=0, EXOKAY=1, SLVERR=2, DECERR=3)

    // Timing
    int aw_delay;                 // Cycles to wait before address
    int w_delay[];                // Cycles to wait before each data beat
    int ar_delay;                 // Cycles to wait before read address

    // Constraints
    constraint c_valid_len {
        len inside {[0:15]};      // Typical burst lengths
    }

    constraint c_valid_size {
        size inside {[0:3]};      // 1,2,4,8 bytes
    }

    constraint c_valid_burst {
        burst inside {1, 2};      // INCR or WRAP
    }

    constraint c_align_addr {
        addr[2:0] == 3'b000;      // 8-byte aligned
    }

    constraint c_data_size {
        data.size() == len + 1;
        strb.size() == len + 1;
    }

    function new(string name = "axi4_mem_txn");
        super.new(name);
    endfunction

    function void do_copy(uvm_object rhs);
        axi4_mem_txn rhs_;
        if(!$cast(rhs_, rhs)) begin
            `uvm_fatal("do_copy", "cast failed")
        end
        super.do_copy(rhs);
        op_type = rhs_.op_type;
        addr    = rhs_.addr;
        len     = rhs_.len;
        size    = rhs_.size;
        burst   = rhs_.burst;
        id      = rhs_.id;
        data    = rhs_.data;
        strb    = rhs_.strb;
        resp    = rhs_.resp;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axi4_mem_txn rhs_;
        if(!$cast(rhs_, rhs)) return 0;
        return super.do_compare(rhs, comparer) &&
               (op_type == rhs_.op_type) &&
               (addr == rhs_.addr) &&
               (len == rhs_.len) &&
               (data == rhs_.data);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("AXI4_%s: addr=0x%0h len=%0d size=%0d burst=%0d",
                      op_type.name(), addr, len, size, burst);
        if (op_type == AXI4_WRITE) begin
            s = {s, $sformatf(" data[0]=0x%0h", data[0])};
        end
        return s;
    endfunction

endclass : axi4_mem_txn
