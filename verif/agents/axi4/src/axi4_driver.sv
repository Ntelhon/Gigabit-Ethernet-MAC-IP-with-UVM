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
  memory_model mem;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(axi4_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")

    if(!uvm_config_db#(virtual axi4_if#(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH))::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not set for axi4_driver")

    if(!uvm_config_db#(memory_model)::get(this, "", "mem", mem))
      `uvm_fatal("NOMEM", "Memory model not found")
  endfunction

  task run_phase(uvm_phase phase);
    reset_signals();
    
    if(cfg.agent_type == AXI4_MASTER) begin
      forever begin
        seq_item_port.get_next_item(req);
        
        if(req.trans_type == AXI4_WRITE)
          drive_master_write(req);
        else
          drive_master_read(req);

        seq_item_port.item_done();
      end
    end
    else if(cfg.agent_type == AXI4_SLAVE) begin
      fork
        drive_slave_write();
        drive_slave_read();
      join_none
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

  task drive_master_write(item_t item);
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
    while(!vif.master_driver_cb.bvalid);
    
    item.resp = new[1];
    item.resp[0] = vif.master_driver_cb.bresp;
  endtask

  task drive_master_read(item_t item);
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
      while(!vif.master_driver_cb.rvalid);
      
      item.data[i] = vif.master_driver_cb.rdata;
      item.resp[i] = vif.master_driver_cb.rresp;
    end
  endtask

  task drive_slave_write();
    item_t item;
    item_t rsp;
    
    forever begin
      // Wait for write address
      vif.slave_driver_cb.awready <= 1'b1;
      do @(vif.slave_driver_cb);
      while(vif.slave_driver_cb.awvalid !== 1'b1);
      vif.slave_driver_cb.awready <= 1'b0;

      item = item_t::type_id::create("item");
      item.trans_type = AXI4_WRITE;
      item.id     = vif.slave_driver_cb.awid;
      item.addr   = vif.slave_driver_cb.awaddr;
      item.len    = vif.slave_driver_cb.awlen;
      item.size   = vif.slave_driver_cb.awsize;
      item.burst  = vif.slave_driver_cb.awburst;
      item.lock   = vif.slave_driver_cb.awlock;
      item.cache  = vif.slave_driver_cb.awcache;
      item.prot   = vif.slave_driver_cb.awprot;
      item.qos    = vif.slave_driver_cb.awqos;
      item.region = vif.slave_driver_cb.awregion;
      item.user   = vif.slave_driver_cb.awuser;

      // Wait for write data
      vif.slave_driver_cb.wready <= 1'b1;

      // Collect write data
      item.data = new[item.len + 1];
      item.strb = new[item.len + 1];

      for (int i = 0; i <= item.len; i++) begin
        do @(vif.slave_driver_cb);
        while(vif.slave_driver_cb.wvalid !== 1'b1);
        item.data[i] = vif.slave_driver_cb.wdata;
        item.strb[i] = vif.slave_driver_cb.wstrb;
      end

      vif.slave_driver_cb.wready <= 1'b0;

      // Handle the write transaction
      rsp = item_t::type_id::create("rsp");
      handle_write(item, rsp);

      // Provide write response
      vif.slave_driver_cb.bresp  <= rsp.resp[0];
      vif.slave_driver_cb.bvalid <= 1'b1;
      vif.slave_driver_cb.bid    <= rsp.id;
      do @(vif.slave_driver_cb);
      while(vif.slave_driver_cb.bready !== 1'b1);
      vif.slave_driver_cb.bvalid <= 1'b0;
      vif.slave_driver_cb.bid    <= '0;  // Clear ID after response

    end
  endtask

  task drive_slave_read();
    item_t item;
    item_t rsp;
    
    forever begin
      // Wait for read address
      vif.slave_driver_cb.arready <= 1'b1;
      do @(vif.slave_driver_cb);
      while(vif.slave_driver_cb.arvalid !== 1'b1);
      vif.slave_driver_cb.arready <= 1'b0;

      item = item_t::type_id::create("item");
      item.trans_type = AXI4_READ;
      item.id     = vif.slave_driver_cb.arid;
      item.addr   = vif.slave_driver_cb.araddr;
      item.len    = vif.slave_driver_cb.arlen;
      item.size   = vif.slave_driver_cb.arsize;
      item.burst  = vif.slave_driver_cb.arburst;
      item.lock   = vif.slave_driver_cb.arlock;
      item.cache  = vif.slave_driver_cb.arcache;
      item.prot   = vif.slave_driver_cb.arprot;
      item.qos    = vif.slave_driver_cb.arqos;
      item.region = vif.slave_driver_cb.arregion;
      item.user   = vif.slave_driver_cb.aruser;

      // Handle the read transaction
      rsp = item_t::type_id::create("rsp");
      handle_read(item, rsp);

      // Provide read data
      for (int i = 0; i <= item.len; i++) begin
        vif.slave_driver_cb.rdata  <= rsp.data[i];
        vif.slave_driver_cb.rresp  <= rsp.resp[i];
        vif.slave_driver_cb.rlast  <= (i == item.len) ? 1'b1 : 1'b0;
        vif.slave_driver_cb.rid    <= rsp.id;
        vif.slave_driver_cb.rvalid <= 1'b1;
        do @(vif.slave_driver_cb);
        while(vif.slave_driver_cb.rready !== 1'b1);
      end
      vif.slave_driver_cb.rvalid <= 1'b0;
    end
  endtask

  virtual task handle_write(item_t req, item_t rsp);
    bit[63:0] addr;
    int burst_len;
    int data_width_bytes;
    
    addr = req.addr;
    burst_len = req.len + 1;
    data_width_bytes = 2 ** req.size;
    
    rsp.trans_type = AXI4_WRITE;
    rsp.addr = req.addr;
    rsp.len = req.len;
    rsp.id = req.id;
    rsp.resp = new[1];
    rsp.resp[0] = 2'b00;  // OKAY
    
    // Write data for each beat
    for (int beat = 0; beat < burst_len; beat++) begin
      // Write bytes based on strobe
      for (int byte_idx = 0; byte_idx < data_width_bytes; byte_idx++) begin
        if (req.strb[beat][byte_idx]) begin
          byte unsigned tmp_data[];
          bit[63:0] byte_addr = addr + byte_idx;
          tmp_data[0] = req.data[beat][byte_idx*8 +: 8];
          mem.write_mem(byte_addr, tmp_data, 1);
        end
      end
      
      // Next address
      if (req.burst == 2'b01) begin  // INCR
        addr += data_width_bytes;
      end else if (req.burst == 2'b10) begin  // WRAP
        bit[63:0] burst_size = burst_len * data_width_bytes;
        addr += data_width_bytes;
        if (addr >= (req.addr + burst_size))
          addr = req.addr;  // Wrap around
      end else begin
        // FIXED - do not change address
      end
    end
    
    `uvm_info(get_type_name(), $sformatf("WRITE: addr=0x%0h, len=%0d, size=%0d", req.addr, burst_len, data_width_bytes), UVM_MEDIUM)
  endtask

  virtual task handle_read(item_t req, item_t rsp);
    bit[63:0] addr;
    int burst_len;
    int data_width_bytes;
    
    addr = req.addr;
    burst_len = req.len + 1;
    data_width_bytes = 2 ** req.size;

    rsp.trans_type = AXI4_READ;
    rsp.addr = req.addr;
    rsp.len = req.len;
    rsp.id = req.id;
    rsp.data = new[burst_len];
    rsp.resp = new[burst_len];
    for (int i = 0; i < burst_len; i++) begin
      byte unsigned tmp_data[];
      mem.read_mem(addr, tmp_data, data_width_bytes);
      // Pack bytes into rsp.data[i]
      for (int b = 0; b < data_width_bytes; b++) begin
          rsp.data[i][8*b +: 8] = tmp_data[b];
      end
      rsp.resp[i] = 2'b00;  // OKAY
      addr += data_width_bytes;
    end

    `uvm_info(get_type_name(), $sformatf("READ: addr=0x%0h, len=%0d, size=%0d", req.addr, burst_len, data_width_bytes), UVM_MEDIUM)
  endtask

endclass : axi4_driver
