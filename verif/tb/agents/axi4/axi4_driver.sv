// File: tb/agents/axi4/axi4_driver.sv
class axi4_driver #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 64,
  int ID_WIDTH   = 4,
  int USER_WIDTH = 1
) extends uvm_driver #(axi4_item#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH));

  `uvm_component_param_utils(axi4_driver#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH))

  typedef axi4_item#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH) item_t;
  virtual axi4_if#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH) vif;
  axi4_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(axi4_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")
  endfunction

  task run_phase(uvm_phase phase);
    reset_signals();
    
    forever begin
      seq_item_port.get_next_item(req);
      
      if(req.trans_type == AXI4_WRITE)
        drive_write(req);
      else
        drive_read(req);
      
      seq_item_port.item_done();
    end
  endtask

  task reset_signals();
    @(vif.master_driver_cb);
    vif.master_driver_cb.awvalid <= 1'b0;
    vif.master_driver_cb.wvalid  <= 1'b0;
    vif.master_driver_cb.bready  <= 1'b1;  // Always ready for response
    vif.master_driver_cb.arvalid <= 1'b0;
    vif.master_driver_cb.rready  <= 1'b1;  // Always ready for data
  endtask

  task drive_write(item_t item);
    fork
      // Write address channel
      begin
        repeat(item.addr_delay) @(vif.master_driver_cb);
        
        vif.master_driver_cb.awid     <= item.id;
        vif.master_driver_cb.awaddr   <= item.addr;
        vif.master_driver_cb.awlen    <= item.len;
        vif.master_driver_cb.awsize   <= item.size;
        vif.master_driver_cb.awburst  <= item.burst;
        vif.master_driver_cb.awlock   <= item.lock;
        vif.master_driver_cb.awcache  <= item.cache;
        vif.master_driver_cb.awprot   <= item.prot;
        vif.master_driver_cb.awqos    <= item.qos;
        vif.master_driver_cb.awregion <= item.region;
        vif.master_driver_cb.awuser   <= item.user;
        vif.master_driver_cb.awvalid  <= 1'b1;
        
        do @(vif.master_driver_cb);
        while(vif.master_driver_cb.awready !== 1'b1);
        
        vif.master_driver_cb.awvalid <= 1'b0;
      end
      
      // Write data channel
      begin
        for(int i = 0; i <= item.len; i++) begin
          repeat(item.data_delay[i]) @(vif.master_driver_cb);
          
          vif.master_driver_cb.wdata  <= item.data[i];
          vif.master_driver_cb.wstrb  <= item.strb[i];
          vif.master_driver_cb.wlast  <= (i == item.len) ? 1'b1 : 1'b0;
          vif.master_driver_cb.wvalid <= 1'b1;
          
          do @(vif.master_driver_cb);
          while(vif.master_driver_cb.wready !== 1'b1);
        end
        
        vif.master_driver_cb.wvalid <= 1'b0;
      end
    join
    
    // Wait for write response
    do @(vif.master_driver_cb);
    while(!(vif.master_driver_cb.bvalid && vif.master_driver_cb.bready));
    
    item.resp = new[1];
    item.resp[0] = vif.master_driver_cb.bresp;
  endtask

  task drive_read(item_t item);
    // Read address channel
    repeat(item.addr_delay) @(vif.master_driver_cb);
    
    vif.master_driver_cb.arid     <= item.id;
    vif.master_driver_cb.araddr   <= item.addr;
    vif.master_driver_cb.arlen    <= item.len;
    vif.master_driver_cb.arsize   <= item.size;
    vif.master_driver_cb.arburst  <= item.burst;
    vif.master_driver_cb.arlock   <= item.lock;
    vif.master_driver_cb.arcache  <= item.cache;
    vif.master_driver_cb.arprot   <= item.prot;
    vif.master_driver_cb.arqos    <= item.qos;
    vif.master_driver_cb.arregion <= item.region;
    vif.master_driver_cb.aruser   <= item.user;
    vif.master_driver_cb.arvalid  <= 1'b1;
    
    do @(vif.master_driver_cb);
    while(vif.master_driver_cb.arready !== 1'b1);
    
    vif.master_driver_cb.arvalid <= 1'b0;
    
    // Read data channel - collect all beats
    item.data = new[item.len + 1];
    item.resp = new[item.len + 1];
    
    for(int i = 0; i <= item.len; i++) begin
      do @(vif.master_driver_cb);
      while(!(vif.master_driver_cb.rvalid && vif.master_driver_cb.rready));
      
      item.data[i] = vif.master_driver_cb.rdata;
      item.resp[i] = vif.master_driver_cb.rresp;
    end
  endtask

endclass : axi4_driver
