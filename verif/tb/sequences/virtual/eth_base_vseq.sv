// File: tb/sequences/virtual/eth_base_vseq.sv
class eth_base_vseq extends uvm_sequence;

  `uvm_object_utils(eth_base_vseq)

  // Virtual sequencer handle
  `uvm_declare_p_sequencer(eth_virtual_sequencer)
  
  // Configuration access
  eth_controller_config cfg;
  
  function new(string name = "eth_base_vseq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    cfg = p_sequencer.cfg;
  endtask

  // Helper: Write MAC register
  task write_mac_reg(bit [31:0] offset, bit [31:0] data);
    axi_lite_write_seq wr_seq;
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = cfg.mac_reg_base + offset;
    wr_seq.data = data;
    wr_seq.start(p_sequencer.axi_lite_sqr);
  endtask

  // Helper: Read MAC register
  task read_mac_reg(bit [31:0] offset, output bit [31:0] data);
    axi_lite_read_seq rd_seq;
    rd_seq = axi_lite_read_seq::type_id::create("rd_seq");
    rd_seq.addr = cfg.mac_reg_base + offset;
    rd_seq.start(p_sequencer.axi_lite_sqr);
    data = rd_seq.read_data;
  endtask

  // Helper: Write DMA register
  task write_dma_reg(bit [31:0] offset, bit [31:0] data);
    axi_lite_write_seq wr_seq;
    wr_seq = axi_lite_write_seq::type_id::create("wr_seq");
    wr_seq.addr = cfg.dma_reg_base + offset;
    wr_seq.data = data;
    wr_seq.start(p_sequencer.axi_lite_sqr);
  endtask

  // Helper: Read DMA register
  task read_dma_reg(bit [31:0] offset, output bit [31:0] data);
    axi_lite_read_seq rd_seq;
    rd_seq = axi_lite_read_seq::type_id::create("rd_seq");
    rd_seq.addr = cfg.dma_reg_base + offset;
    rd_seq.start(p_sequencer.axi_lite_sqr);
    data = rd_seq.read_data;
  endtask

endclass : eth_base_vseq
