// File: tb/env/eth_controller/axi_lite_agent/axi_lite_monitor.sv
class axi_lite_monitor #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 32
) extends uvm_monitor;

  `uvm_component_param_utils(axi_lite_monitor#(ADDR_WIDTH, DATA_WIDTH))

  typedef axi_lite_item#(ADDR_WIDTH, DATA_WIDTH) item_t;
  virtual axi_lite_if#(ADDR_WIDTH, DATA_WIDTH) vif;
  axi_lite_config cfg;
  
  uvm_analysis_port #(item_t) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(axi_lite_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_write();
      monitor_read();
    join_none
  endtask

  task monitor_write();
    item_t item;
    bit [ADDR_WIDTH-1:0] addr;
    bit [DATA_WIDTH-1:0] data;
    bit [(DATA_WIDTH/8)-1:0] strb;
    
    forever begin
      // Wait for write address valid
      do @(vif.monitor_cb);
      while(!(vif.monitor_cb.awvalid && vif.monitor_cb.awready));
      
      addr = vif.monitor_cb.awaddr;
      
      // Wait for write data
      do @(vif.monitor_cb);
      while(!(vif.monitor_cb.wvalid && vif.monitor_cb.wready));
      
      data = vif.monitor_cb.wdata;
      strb = vif.monitor_cb.wstrb;
      
      // Wait for response
      do @(vif.monitor_cb);
      while(!(vif.monitor_cb.bvalid && vif.monitor_cb.bready));
      
      item = item_t::type_id::create("item");
      item.trans_type = AXI_LITE_WRITE;
      item.addr = addr;
      item.data = data;
      item.strb = strb;
      item.resp = vif.monitor_cb.bresp;
      
      ap.write(item);
    end
  endtask

  task monitor_read();
    item_t item;
    bit [ADDR_WIDTH-1:0] addr;
    
    forever begin
      // Wait for read address
      do @(vif.monitor_cb);
      while(!(vif.monitor_cb.arvalid && vif.monitor_cb.arready));
      
      addr = vif.monitor_cb.araddr;
      
      // Wait for read data
      do @(vif.monitor_cb);
      while(!(vif.monitor_cb.rvalid && vif.monitor_cb.rready));
      
      item = item_t::type_id::create("item");
      item.trans_type = AXI_LITE_READ;
      item.addr = addr;
      item.read_data = vif.monitor_cb.rdata;
      item.resp = vif.monitor_cb.rresp;
      
      ap.write(item);
    end
  endtask

endclass : axi_lite_monitor
