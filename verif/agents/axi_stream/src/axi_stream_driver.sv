// File: tb/agents/axi_stream/axi_stream_driver.sv
class axi_stream_driver #(
  int DATA_WIDTH = 32,
  int USER_WIDTH = 1,
  int DEST_WIDTH = 1,
  int ID_WIDTH   = 1
) extends uvm_driver #(axi_stream_item#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH));

  `uvm_component_param_utils(axi_stream_driver#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH))

  typedef axi_stream_item#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH) item_t;
  virtual axi_stream_if#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH) vif;
  axi_stream_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(axi_stream_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")

    if(!uvm_config_db#(virtual axi_stream_if#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH))::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not set for axi_stream_driver")
  endfunction

  task run_phase(uvm_phase phase);
    reset_signals();
    
    forever begin
      seq_item_port.get_next_item(req);
      drive_transfer(req);
      seq_item_port.item_done();
    end
  endtask

  task reset_signals();
    @(vif.driver_cb);
    vif.driver_cb.tvalid <= 1'b0;
    vif.driver_cb.tdata  <= '0;
    vif.driver_cb.tstrb  <= '0;
    vif.driver_cb.tkeep  <= '0;
    vif.driver_cb.tlast  <= 1'b0;
    vif.driver_cb.tuser  <= '0;
    vif.driver_cb.tdest  <= '0;
    vif.driver_cb.tid    <= '0;
  endtask

  task drive_transfer(item_t item);
    // Idle cycles before transfer
    repeat(item.idle_cycles_before) @(vif.driver_cb);
    
    // Drive each beat
    foreach(item.data_queue[i]) begin
      vif.driver_cb.tvalid <= 1'b1;
      vif.driver_cb.tdata  <= item.data_queue[i];
      vif.driver_cb.tstrb  <= item.strb_queue[i];
      vif.driver_cb.tkeep  <= item.keep_queue[i];
      vif.driver_cb.tlast  <= (i == item.data_queue.size() - 1) ? 1'b1 : 1'b0;
      vif.driver_cb.tuser  <= item.user;
      vif.driver_cb.tdest  <= item.dest;
      vif.driver_cb.tid    <= item.id;
      
      // Wait for ready
      do begin
        @(vif.driver_cb);
      end while(vif.driver_cb.tready !== 1'b1);
    end
    
    // Deassert valid
    vif.driver_cb.tvalid <= 1'b0;
    vif.driver_cb.tlast  <= 1'b0;
  endtask

endclass : axi_stream_driver
