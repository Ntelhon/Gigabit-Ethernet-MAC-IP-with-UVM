// File: tb/env/eth_controller/axi_lite_agent/axi_lite_driver.sv
class axi_lite_driver #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 32
) extends uvm_driver #(axi_lite_item#(ADDR_WIDTH, DATA_WIDTH));

  `uvm_component_param_utils(axi_lite_driver#(ADDR_WIDTH, DATA_WIDTH))

  typedef axi_lite_item#(ADDR_WIDTH, DATA_WIDTH) item_t;
  virtual axi_lite_if#(ADDR_WIDTH, DATA_WIDTH) vif;
  axi_lite_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(axi_lite_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")

    if(!uvm_config_db#(virtual axi_lite_if#(ADDR_WIDTH, DATA_WIDTH))::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not set for axi_lite_driver")
  endfunction

  task run_phase(uvm_phase phase);
    reset_signals();
    
    forever begin
      seq_item_port.get_next_item(req);
      
      if(req.trans_type == AXI_LITE_WRITE)
        drive_write(req);
      else
        drive_read(req);

      seq_item_port.item_done(req);
    end
  endtask

  task reset_signals();
    @(vif.master_driver_cb);
    vif.master_driver_cb.awvalid <= 1'b0;
    vif.master_driver_cb.awaddr  <= '0;
    vif.master_driver_cb.awprot  <= '0;
    vif.master_driver_cb.wvalid  <= 1'b0;
    vif.master_driver_cb.wdata   <= '0;
    vif.master_driver_cb.wstrb   <= '0;
    vif.master_driver_cb.bready  <= 1'b0;
    vif.master_driver_cb.arvalid <= 1'b0;
    vif.master_driver_cb.araddr  <= '0;
    vif.master_driver_cb.arprot  <= '0;
    vif.master_driver_cb.rready  <= 1'b0;
  endtask

  task drive_write(item_t item);
    fork
      // Write address channel
      begin
        repeat(item.addr_delay) @(vif.master_driver_cb);
        vif.master_driver_cb.awvalid <= 1'b1;
        vif.master_driver_cb.awaddr  <= item.addr;
        vif.master_driver_cb.awprot  <= item.prot;
        
        do @(vif.master_driver_cb);
        while(vif.master_driver_cb.awready !== 1'b1);
        
        vif.master_driver_cb.awvalid <= 1'b0;
      end
      
      // Write data channel
      begin
        repeat(item.data_delay) @(vif.master_driver_cb);
        vif.master_driver_cb.wvalid <= 1'b1;
        vif.master_driver_cb.wdata  <= item.data;
        vif.master_driver_cb.wstrb  <= item.strb;
        
        do @(vif.master_driver_cb);
        while(vif.master_driver_cb.wready !== 1'b1);
        
        vif.master_driver_cb.wvalid <= 1'b0;
      end
    join
    
    // Write response channel
    vif.master_driver_cb.bready <= 1'b1;
    do @(vif.master_driver_cb);
    while(vif.master_driver_cb.bvalid !== 1'b1);
    
    item.resp = vif.master_driver_cb.bresp;
    vif.master_driver_cb.bready <= 1'b0;
  endtask

  task drive_read(item_t item);
    `uvm_info("DRIVE_READ", "Starting read transaction", UVM_LOW)
    // Read address channel
    repeat(item.addr_delay) @(vif.master_driver_cb);
    `uvm_info("DRIVE_READ", $sformatf("Address: 0x%0h, Prot: %0d", item.addr, item.prot), UVM_LOW)
    vif.arvalid <= 1'b1;
    vif.araddr  <= item.addr;
    vif.arprot  <= item.prot;
    
    do @(vif.master_driver_cb);
    while(vif.master_driver_cb.arready !== 1'b1);
    `uvm_info("DRIVE_READ", "Read address accepted by DUT", UVM_LOW)
    
    vif.arvalid <= 1'b0;
    
    // Read data channel
    vif.rready <= 1'b1;
    do @(vif.master_driver_cb);
    while(vif.master_driver_cb.rvalid !== 1'b1);
    `uvm_info("DRIVE_READ", $sformatf("Data: 0x%0h, Resp: %0d", vif.master_driver_cb.rdata, vif.master_driver_cb.rresp), UVM_LOW)
    
    item.read_data = vif.master_driver_cb.rdata;
    item.resp      = vif.master_driver_cb.rresp;
    vif.rready <= 1'b0;
  endtask

endclass : axi_lite_driver
