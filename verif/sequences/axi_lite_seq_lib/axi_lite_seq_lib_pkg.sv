//==============================================================================
// Package: axi_lite_seq_lib_pkg
// Description: AXI-Lite sequence library
//
// Contains sequences that only drive the AXI-Lite interface
//==============================================================================

package axi_lite_seq_lib_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import axi_lite_agent_pkg::*;
    
    // AXI-Lite sequences (only drive AXI-Lite interface)
    `include "axi_lite_write_seq.sv"
    `include "axi_lite_read_seq.sv"
    `include "axi_lite_mac_init_seq.sv"
    `include "axi_lite_read_cnt_seq.sv"
    `include "axi_lite_pool_seq.sv"

endpackage : axi_lite_seq_lib_pkg
