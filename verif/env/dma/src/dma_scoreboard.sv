// File: tb/env/dma/dma_scoreboard.sv
class dma_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(dma_scoreboard)
  `uvm_analysis_imp_decl(_dma_axi4)

  // Analysis ports for DMA Scoreboard
  uvm_analysis_imp_dma_axi4#(axi4_item#(32,64,4,1), dma_scoreboard)     dma_axi4_imp;

  // Reference to memory model
  memory_model mem;

  // Statistics
  int axi4_writes = 0;
  int axi4_reads = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dma_axi4_imp = new("dma_axi4_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Memory model passed via config or created here
    if(!uvm_config_db#(memory_model)::get(this, "", "mem", mem)) begin
      `uvm_info("DMA_SB", "Creating local memory model", UVM_MEDIUM)
      mem = memory_model::type_id::create("mem", this);
    end
  endfunction

  function void write_dma_axi4(axi4_item#(32,64,4,1) item);
    byte unsigned byte_data[];
    int byte_idx = 0;
    
    if(item.trans_type == AXI4_WRITE) begin
      // Convert AXI4 data to byte array
      byte_data = new[item.data.size() * 8];  // 64-bit data width = 8 bytes
      foreach(item.data[i]) begin
        for(int j = 0; j < 8; j++) begin
          if(item.strb[i][j])
            byte_data[byte_idx++] = item.data[i][j*8 +: 8];
        end
      end
      byte_data = new[byte_idx](byte_data);  // Trim
      
      mem.write_mem(item.addr, byte_data, byte_data.size());
      axi4_writes++;
      `uvm_info("DMA_SB", $sformatf("AXI4 Write tracked: addr=0x%0h, size=%0d", item.addr, byte_data.size()), UVM_MEDIUM)
    end
    else begin
      axi4_reads++;
      `uvm_info("DMA_SB", $sformatf("AXI4 Read tracked: addr=0x%0h", item.addr), UVM_MEDIUM)
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("DMA_SB", $sformatf("=== DMA Scoreboard Statistics ==="), UVM_NONE)
    `uvm_info("DMA_SB", $sformatf("AXI4 Writes: %0d, Reads: %0d", axi4_writes, axi4_reads), UVM_NONE)
  endfunction

endclass : dma_scoreboard
