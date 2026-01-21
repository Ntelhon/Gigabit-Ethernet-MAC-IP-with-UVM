//==============================================================================
// File: eth_base_seq.sv
// Description: Base sequence for Ethernet Controller operations
//
// Purpose:
//   Provides common register access methods for both MAC and DMA configuration.
//   This sequence runs on the shared AXI-Lite sequencer.
//
// Key Methods:
//   - write_reg():  Write to any register (MAC or DMA)
//   - read_reg():   Read from any register (MAC or DMA)
//   - poll_reg():   Poll register until condition met
//   - rmw_reg():    Read-Modify-Write operation
//
// Usage:
//   class my_sequence extends eth_base_seq;
//     virtual task body();
//       write_reg(32'h0008, 32'h0000_0003);  // Enable MAC TX+RX
//     endtask
//   endclass
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

`ifndef ETH_BASE_SEQ_SV
`define ETH_BASE_SEQ_SV

class eth_base_seq extends uvm_sequence #(axi_lite_txn);

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_object_utils(eth_base_seq)

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "eth_base_seq");
        super.new(name);
    endfunction

    //==========================================================================
    // Read-Modify-Write: Read register, modify bits, write back
    task rmw_reg(bit [31:0] addr, bit [31:0] mask, bit [31:0] value);
        bit [31:0] data;
        read_reg(addr, data);
        data = (data & ~mask) | (value & mask);
        write_reg(addr, data);
        `uvm_info("ETH_SEQ", $sformatf("RMW: addr=0x%08h mask=0x%08h value=0x%08h -> 0x%08h", addr, mask, value, data), UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Utility Functions
    //==========================================================================
    
    function bit [31:0] swap_bytes(bit [31:0] data);
        return {data[7:0], data[15:8], data[23:16], data[31:24]};
    endfunction

endclass

`endif // ETH_BASE_SEQ_SV
