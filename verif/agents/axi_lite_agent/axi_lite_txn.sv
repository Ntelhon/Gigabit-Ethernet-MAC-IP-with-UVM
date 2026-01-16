//==============================================================================
// Class: axi_lite_txn
// Description: AXI4-Lite transaction for register read/write operations
//
// Purpose:
//   Encapsulates all fields needed for an AXI4-Lite register access.
//   Supports both read and write operations with response handling.
//
// Fields:
//   - Operation type (read/write)
//   - Address
//   - Write data and strobes
//   - Read data (response)
//   - Response status
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class axi_lite_txn extends uvm_sequence_item;

    //==========================================================================
    // Transaction Type
    //==========================================================================
    typedef enum bit {
        AXI_READ  = 1'b0,
        AXI_WRITE = 1'b1
    } axi_op_e;

    //==========================================================================
    // AXI Response Codes
    //==========================================================================
    typedef enum bit [1:0] {
        RESP_OKAY   = 2'b00,    // Normal access success
        RESP_EXOKAY = 2'b01,    // Exclusive access success
        RESP_SLVERR = 2'b10,    // Slave error
        RESP_DECERR = 2'b11     // Decode error
    } axi_resp_e;

    //==========================================================================
    // Transaction Fields
    //==========================================================================
    
    // Operation type
    rand axi_op_e op;
    
    // Address (32-bit)
    rand bit [31:0] addr;
    
    // Write data (32-bit)
    rand bit [31:0] wdata;
    
    // Write strobes (byte enables)
    rand bit [3:0] wstrb;
    
    // Protection type (usually tied to 0)
    rand bit [2:0] prot;
    
    // Read data (returned by slave)
    bit [31:0] rdata;
    
    // Response (from slave)
    axi_resp_e resp;
    
    //==========================================================================
    // Timing Information
    //==========================================================================
    
    // Transaction start time
    time start_time;
    
    // Transaction end time
    time end_time;
    
    //==========================================================================
    // Status Flags
    //==========================================================================
    
    // Transaction completed successfully
    bit completed;
    
    // Error occurred
    bit error;

    //==========================================================================
    // UVM Field Macros
    //==========================================================================
    `uvm_object_utils_begin(axi_lite_txn)
        `uvm_field_enum(axi_op_e, op, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON)
        `uvm_field_int(wdata, UVM_ALL_ON)
        `uvm_field_int(wstrb, UVM_ALL_ON)
        `uvm_field_int(prot, UVM_ALL_ON)
        `uvm_field_int(rdata, UVM_ALL_ON)
        `uvm_field_enum(axi_resp_e, resp, UVM_ALL_ON)
        `uvm_field_int(start_time, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(end_time, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(completed, UVM_ALL_ON)
        `uvm_field_int(error, UVM_ALL_ON)
    `uvm_object_utils_end

    //==========================================================================
    // Constraints
    //==========================================================================
    
    // Default write strobes to all bytes enabled
    constraint c_default_wstrb {
        soft wstrb == 4'hF;
    }
    
    // Default protection to unprivileged, secure, data access
    constraint c_default_prot {
        soft prot == 3'b000;
    }
    
    // Word-aligned addresses
    constraint c_addr_aligned {
        addr[1:0] == 2'b00;
    }

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_lite_txn");
        super.new(name);
        completed = 0;
        error = 0;
        resp = RESP_OKAY;
    endfunction

    //==========================================================================
    // Helper: Create write transaction
    //==========================================================================
    static function axi_lite_txn create_write(
        bit [31:0] address,
        bit [31:0] data,
        bit [3:0]  strb = 4'hF
    );
        axi_lite_txn txn = new("write_txn");
        txn.op    = AXI_WRITE;
        txn.addr  = address;
        txn.wdata = data;
        txn.wstrb = strb;
        return txn;
    endfunction

    //==========================================================================
    // Helper: Create read transaction
    //==========================================================================
    static function axi_lite_txn create_read(bit [31:0] address);
        axi_lite_txn txn = new("read_txn");
        txn.op   = AXI_READ;
        txn.addr = address;
        return txn;
    endfunction

    //==========================================================================
    // Convert to string
    //==========================================================================
    function string convert2string();
        string s;
        if (op == AXI_WRITE) begin
            s = $sformatf("AXI-Lite WRITE: addr=0x%08h wdata=0x%08h wstrb=0x%01h resp=%s",
                          addr, wdata, wstrb, resp.name());
        end else begin
            s = $sformatf("AXI-Lite READ:  addr=0x%08h rdata=0x%08h resp=%s",
                          addr, rdata, resp.name());
        end
        return s;
    endfunction

    //==========================================================================
    // Check if response is OK
    //==========================================================================
    function bit is_ok();
        return (resp == RESP_OKAY) || (resp == RESP_EXOKAY);
    endfunction

endclass : axi_lite_txn
