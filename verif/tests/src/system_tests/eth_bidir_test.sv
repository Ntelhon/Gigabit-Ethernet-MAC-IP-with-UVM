// File: tb/tests/system_tests/eth_bidir_test.sv
class eth_bidir_test extends eth_base_test;

  `uvm_component_utils(eth_bidir_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    eth_bidir_vseq vseq;
    
    super.run_phase(phase);
    
    phase.raise_objection(this);
    
    vseq = eth_bidir_vseq::type_id::create("vseq");
    assert(vseq.randomize());
    vseq.start(env.virtual_sqr);
    
    phase.drop_objection(this);
  endtask

endclass : eth_bidir_test
