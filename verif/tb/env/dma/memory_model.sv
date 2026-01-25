// File: tb/env/dma/memory_model.sv
class memory_model extends uvm_component;

  `uvm_component_utils(memory_model)

  // Simple associative array for memory
  byte unsigned mem[bit[31:0]];
  
  // Statistics
  int writes = 0;
  int reads = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Write data to memory
  function void write_mem(bit [31:0] addr, byte unsigned data[], int size_bytes);
    for(int i = 0; i < size_bytes && i < data.size(); i++) begin
      mem[addr + i] = data[i];
    end
    writes++;
    `uvm_info("MEM_MODEL", $sformatf("Write: addr=0x%0h, size=%0d", addr, size_bytes), UVM_HIGH)
  endfunction

  // Read data from memory
  function void read_mem(bit [31:0] addr, ref byte unsigned data[], int size_bytes);
    data = new[size_bytes];
    for(int i = 0; i < size_bytes; i++) begin
      if(mem.exists(addr + i))
        data[i] = mem[addr + i];
      else
        data[i] = 8'h00;  // Uninitialized memory returns 0
    end
    reads++;
    `uvm_info("MEM_MODEL", $sformatf("Read: addr=0x%0h, size=%0d", addr, size_bytes), UVM_HIGH)
  endfunction

  // Initialize memory region
  function void init_mem(bit [31:0] start_addr, byte unsigned data[]);
    foreach(data[i])
      mem[start_addr + i] = data[i];
    `uvm_info("MEM_MODEL", $sformatf("Initialized: addr=0x%0h, size=%0d", start_addr, data.size()), UVM_MEDIUM)
  endfunction

  // Clear memory
  function void clear_mem();
    mem.delete();
    `uvm_info("MEM_MODEL", "Memory cleared", UVM_MEDIUM)
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("MEM_MODEL", $sformatf("Total writes: %0d, reads: %0d, size: %0d bytes", 
                                      writes, reads, mem.size()), UVM_NONE)
  endfunction

endclass : memory_model
