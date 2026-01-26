// File: tb/agents/axi_stream/axi_stream_monitor.sv
class axi_stream_monitor #(
  int DATA_WIDTH = 32,
  int USER_WIDTH = 1,
  int DEST_WIDTH = 1,
  int ID_WIDTH   = 1
) extends uvm_monitor;

  `uvm_component_param_utils(axi_stream_monitor#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH))

  typedef axi_stream_item#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH) item_t;
  virtual axi_stream_if#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH) vif;
  axi_stream_config cfg;
  
  uvm_analysis_port #(item_t) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(axi_stream_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")

    if(!uvm_config_db#(virtual axi_stream_if#(DATA_WIDTH, USER_WIDTH, DEST_WIDTH, ID_WIDTH))::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not set for axi_stream_monitor")
  endfunction

  task run_phase(uvm_phase phase);
    item_t item;
    
    forever begin
      item = item_t::type_id::create("item");
      collect_transfer(item);
      ap.write(item);
    end
  endtask

  task collect_transfer(item_t item);
    // Wait for valid
    do begin
      @(vif.monitor_cb);
    end while(vif.monitor_cb.tvalid !== 1'b1);
    
    // Collect beats until tlast
    do begin
      if(vif.monitor_cb.tvalid && vif.monitor_cb.tready) begin
        item.data_queue.push_back(vif.monitor_cb.tdata);
        item.strb_queue.push_back(vif.monitor_cb.tstrb);
        item.keep_queue.push_back(vif.monitor_cb.tkeep);
        item.user = vif.monitor_cb.tuser;
        item.dest = vif.monitor_cb.tdest;
        item.id   = vif.monitor_cb.tid;
        
        if(vif.monitor_cb.tlast) break;
      end
      @(vif.monitor_cb);
    end while(1);
  endtask

endclass : axi_stream_monitor
