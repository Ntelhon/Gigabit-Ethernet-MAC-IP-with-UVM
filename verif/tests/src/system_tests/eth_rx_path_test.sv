// File: tb/tests/system_tests/eth_rx_path_test.sv
class eth_rx_path_test extends eth_base_test;

  `uvm_component_utils(eth_rx_path_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    eth_rx_path_vseq vseq;
    
    super.run_phase(phase);
    
    phase.raise_objection(this);
    
    vseq = eth_rx_path_vseq::type_id::create("vseq");
    assert(vseq.randomize() with {num_packets == 10;});
    vseq.start(env.virtual_sqr);
    
    phase.drop_objection(this);
  endtask

endclass : eth_rx_path_test
