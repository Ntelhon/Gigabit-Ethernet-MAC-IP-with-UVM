// File: tb/agents/axi_stream/axi_stream_item.sv
class axi_stream_item #(
  int DATA_WIDTH = 32,
  int USER_WIDTH = 1,
  int DEST_WIDTH = 1,
  int ID_WIDTH   = 1
) extends uvm_sequence_item;

  // Payload
  rand bit [DATA_WIDTH-1:0]     data_queue[$];
  rand bit [(DATA_WIDTH/8)-1:0] strb_queue[$];
  rand bit [(DATA_WIDTH/8)-1:0] keep_queue[$];
  rand bit [USER_WIDTH-1:0]     user;
  rand bit [DEST_WIDTH-1:0]     dest;
  rand bit [ID_WIDTH-1:0]       id;
  
  // Timing
  rand int unsigned             idle_cycles_before;  // Idle before transfer
  rand int unsigned             ready_delay[];       // Per-beat backpressure
  
  // Constraints
  constraint c_idle_cycles {
    idle_cycles_before inside {[0:10]};
  }
  
  constraint c_ready_delay {
    ready_delay.size() == data_queue.size();
    foreach(ready_delay[i]) {
      ready_delay[i] inside {[0:5]};
    }
  }
  
  constraint c_strb_keep {
    strb_queue.size() == data_queue.size();
    keep_queue.size() == data_queue.size();
  }

  `uvm_object_param_utils_begin(axi_stream_item#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH))
    `uvm_field_queue_int(data_queue, UVM_DEFAULT)
    `uvm_field_queue_int(strb_queue, UVM_DEFAULT)
    `uvm_field_queue_int(keep_queue, UVM_DEFAULT)
    `uvm_field_int(user, UVM_DEFAULT)
    `uvm_field_int(dest, UVM_DEFAULT)
    `uvm_field_int(id, UVM_DEFAULT)
    `uvm_field_int(idle_cycles_before, UVM_DEFAULT | UVM_DEC)
    `uvm_field_array_int(ready_delay, UVM_DEFAULT | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "axi_stream_item");
    super.new(name);
  endfunction

  // Helper: Create packet from byte array
  function void create_from_bytes(byte unsigned byte_data[]);
    int num_beats = (byte_data.size() + (DATA_WIDTH/8) - 1) / (DATA_WIDTH/8);
    int byte_idx = 0;
    
    data_queue.delete();
    strb_queue.delete();
    keep_queue.delete();
    
    for(int beat = 0; beat < num_beats; beat++) begin
      bit [DATA_WIDTH-1:0] beat_data = '0;
      bit [(DATA_WIDTH/8)-1:0] beat_strb = '0;
      bit [(DATA_WIDTH/8)-1:0] beat_keep = '0;
      
      for(int byte_in_beat = 0; byte_in_beat < (DATA_WIDTH/8); byte_in_beat++) begin
        if(byte_idx < byte_data.size()) begin
          beat_data[byte_in_beat*8 +: 8] = byte_data[byte_idx];
          beat_strb[byte_in_beat] = 1'b1;
          beat_keep[byte_in_beat] = 1'b1;
          byte_idx++;
        end
      end
      
      data_queue.push_back(beat_data);
      strb_queue.push_back(beat_strb);
      keep_queue.push_back(beat_keep);
    end
  endfunction

  // Helper: Extract byte array
  function void get_bytes(ref byte unsigned byte_data[]);
    byte_data = new[data_queue.size() * (DATA_WIDTH/8)];
    int byte_idx = 0;
    
    foreach(data_queue[i]) begin
      for(int j = 0; j < (DATA_WIDTH/8); j++) begin
        if(keep_queue[i][j]) begin
          byte_data[byte_idx++] = data_queue[i][j*8 +: 8];
        end
      end
    end
    byte_data = new[byte_idx](byte_data);  // Trim to actual size
  endfunction

endclass : axi_stream_item
