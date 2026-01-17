//==============================================================================
// Class: axi4_mem_agent
// Description: AXI4 memory agent
//
// Can be configured as active (with driver) or passive (monitor only)
//==============================================================================

class axi4_mem_agent extends uvm_agent;
    `uvm_component_utils(axi4_mem_agent)

    axi4_mem_sequencer sequencer;
    axi4_mem_driver    driver;
    axi4_mem_monitor   monitor;

    uvm_analysis_port #(axi4_mem_txn) ap;

    function new(string name = "axi4_mem_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        monitor = axi4_mem_monitor::type_id::create("monitor", this);
        
        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = axi4_mem_sequencer::type_id::create("sequencer", this);
            driver = axi4_mem_driver::type_id::create("driver", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        ap = monitor.ap;
        
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : axi4_mem_agent
