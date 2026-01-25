// File: tb/tests/system_tests/eth_sanity_test.sv
class eth_sanity_test extends eth_base_test;

  `uvm_component_utils(eth_sanity_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    eth_sanity_vseq vseq;
    
    super.run_phase(phase);
    
    phase.raise_objection(this);
    
    vseq = eth_sanity_vseq::type_id::create("vseq");
    vseq.start(env.virtual_sqr);
    
    phase.drop_objection(this);
  endtask

endclass : eth_sanity_test
