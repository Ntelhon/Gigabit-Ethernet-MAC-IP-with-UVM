// File: tb/agents/gmii/gmii_driver.sv

//==============================================================================
// Class: gmii_driver
// Description: UVM Driver for GMII RX path (drives data TO the DUT)
//
// Purpose:
//   Acts as a behavioral PHY model, driving Ethernet frames into the MAC's
//   RX interface. Generates preamble, SFD, frame data, and FCS according
//   to GMII timing at 125 MHz.
//
// Driven Signals:
//   - rxd[7:0]  : Receive data to MAC
//   - rx_dv     : Receive data valid
//   - rx_er     : Receive error
//
// Features:
//   - Correct preamble (7 × 0x55) and SFD (0xD5) generation
//   - CRC32 calculation and transmission
//   - Automatic padding to minimum frame size (optional)
//   - Error injection: CRC errors, runt frames, IFG violations, RX_ER
//   - Clock-accurate GMII timing
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_driver extends uvm_driver #(gmii_item);

  `uvm_component_utils(gmii_driver)

  virtual gmii_if vif;
  gmii_config cfg;

  // uvm_analysis_port #(gmii_item) ap;

  bit enable_padding;
  int unsigned min_frame_size;
  int unsigned default_ifg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    // ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(gmii_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")

    enable_padding   = cfg.enable_padding;
    min_frame_size  = cfg.min_frame_size;
    default_ifg     = cfg.default_ifg;
    
    if(!uvm_config_db#(virtual gmii_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not set for gmii_driver")
  endfunction

  task run_phase(uvm_phase phase);
    reset_signals();
    
    forever begin
      wait_for_reset_release();

      seq_item_port.get_next_item(req);

      `uvm_info("GMII_DRIVER", $sformatf("Driving frame with payload length %0d bytes", req.payload.size()), UVM_MEDIUM)
      drive_frame(req);

      // Broadcast frame to analysis port (for scoreboard tracking)
      // ap.write(req);
      
      seq_item_port.item_done(req);
    end
  endtask

  //==========================================================================
  // Reset signals to idle state
  //==========================================================================
  task reset_signals();
    if(cfg.direction == GMII_RX) begin
      @(vif.rx_driver_cb);
      vif.rx_driver_cb.rx_dv <= 1'b0;
      vif.rx_driver_cb.rx_er <= 1'b0;
      vif.rx_driver_cb.rxd   <= 8'h00;
    end else begin
      @(vif.tx_driver_cb);
      vif.tx_driver_cb.tx_en <= 1'b0;
      vif.tx_driver_cb.tx_er <= 1'b0;
      vif.tx_driver_cb.txd   <= 8'h00;
    end
  endtask

  //==========================================================================
  // Wait for reset release
  //==========================================================================
  task wait_for_reset_release();
    // Simple wait - in real implementation, monitor reset signal
    wait (vif.rst_n == 1'b1);
    if(cfg.direction == GMII_TX)
      @(vif.tx_driver_cb);
    else if(cfg.direction == GMII_RX) begin
      @(vif.rx_driver_cb);
    end
  endtask

  //==========================================================================
  // Drive a complete Ethernet frame
  //==========================================================================
  task drive_frame(gmii_item frame);
    bit [7:0] frame_bytes[];
    bit [7:0] padded_frame[];
    bit [31:0] crc;
    int unsigned ifg;
    int total_data_len;

    // Record start time
    frame.start_time = $time;

    // Get frame bytes (header + payload)
    frame.get_frame_bytes(frame_bytes);

    // Handle padding
    if (!frame.send_as_runt && enable_padding) begin
      total_data_len = frame_bytes.size() + 4;  // +4 for FCS
      if (total_data_len < min_frame_size) begin
        int pad_bytes = min_frame_size - 4 - frame_bytes.size();
        padded_frame = new[frame_bytes.size() + pad_bytes];
        foreach (frame_bytes[i]) padded_frame[i] = frame_bytes[i];
        for (int i = frame_bytes.size(); i < padded_frame.size(); i++) begin
            padded_frame[i] = 8'h00;  // Pad with zeros
        end
        frame_bytes = padded_frame;
      end
    end

    // Calculate CRC
    crc = frame.calculate_crc();
    frame.fcs = crc;

    // Inject CRC error if requested
    if (frame.inject_crc_error) begin
        frame.fcs = frame.fcs ^ 32'hDEADBEEF;
    end

    // Inter-frame gap
    ifg = frame.inject_ifg_violation ? frame.ifg_bytes : default_ifg;
    drive_ifg(ifg);

    // Drive preamble
    drive_preamble(frame.preamble_bytes);
    
    // Drive SFD
    drive_byte(SFD_BYTE, 1'b0);
    
    // Drive frame data
    drive_data(frame_bytes, frame.inject_rx_error, frame.rx_error_byte_pos);
    
    // Drive FCS (4 bytes, LSB first)
    drive_byte(frame.fcs[7:0],   1'b0);
    drive_byte(frame.fcs[15:8],  1'b0);
    drive_byte(frame.fcs[23:16], 1'b0);
    drive_byte(frame.fcs[31:24], 1'b0);
    
    // Deassert data valid
    if(cfg.direction == GMII_RX) begin
      @(vif.rx_driver_cb);
      vif.rx_driver_cb.rxd   <= 8'h00;
      vif.rx_driver_cb.rx_dv <= 1'b0;
      vif.rx_driver_cb.rx_er <= 1'b0;
    end else if(cfg.direction == GMII_TX) begin
      @(vif.tx_driver_cb);
      vif.tx_driver_cb.txd   <= 8'h00;
      vif.tx_driver_cb.tx_en <= 1'b0;
      vif.tx_driver_cb.tx_er <= 1'b0;
    end

    // Record end time
    frame.end_time = $time;
  endtask

  //==========================================================================
  // Drive preamble bytes
  //==========================================================================
  task drive_preamble(int unsigned num_bytes);
    for (int i = 0; i < num_bytes; i++) begin
      drive_byte(PREAMBLE_BYTE, 1'b0);
    end
  endtask

  //==========================================================================
  // Drive a single byte on GMII
  //==========================================================================
  task drive_byte(bit [7:0] data, bit rx_error);
    if(cfg.direction == GMII_RX) begin
      @(vif.rx_driver_cb);
      vif.rx_driver_cb.rxd   <= data;
      vif.rx_driver_cb.rx_dv <= 1'b1;
      vif.rx_driver_cb.rx_er <= rx_error;
    end else if(cfg.direction == GMII_TX) begin
      @(vif.tx_driver_cb);
      vif.tx_driver_cb.txd   <= data;
      vif.tx_driver_cb.tx_en <= 1'b1;
      vif.tx_driver_cb.tx_er <= rx_error;
    end
  endtask

  //==========================================================================
  // Drive frame data bytes
  //==========================================================================
  task drive_data(input bit [7:0] data[], bit inject_error, int unsigned error_pos);
    for (int i = 0; i < data.size(); i++) begin
      bit err = inject_error && (i == error_pos);
      drive_byte(data[i], err);
    end
  endtask

  //==========================================================================
  // Drive inter-frame gap (idle)
  //==========================================================================
  task drive_ifg(int unsigned num_bytes);
    for (int i = 0; i < num_bytes; i++) begin
      if(cfg.direction == GMII_RX) begin
        @(vif.rx_driver_cb);
        vif.rx_driver_cb.rxd   <= 8'h00;
        vif.rx_driver_cb.rx_dv <= 1'b0;
        vif.rx_driver_cb.rx_er <= 1'b0;
      end else if(cfg.direction == GMII_TX) begin
        @(vif.tx_driver_cb);
        vif.tx_driver_cb.txd   <= 8'h00;
        vif.tx_driver_cb.tx_en <= 1'b0;
        vif.tx_driver_cb.tx_er <= 1'b0;
      end
    end
  endtask

endclass : gmii_driver
