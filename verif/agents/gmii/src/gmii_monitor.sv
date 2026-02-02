// File: tb/agents/gmii/gmii_monitor.sv

//==============================================================================
// Class: gmii_monitor
// Description: UVM Monitor for GMII TX path (monitors data FROM the DUT)
//
// Purpose:
//   Observes Ethernet frames transmitted by the MAC on the GMII TX interface.
//   Reconstructs complete frames from byte stream and sends them to the
//   scoreboard via analysis port.
//
// Monitored Signals:
//   - txd[7:0]  : Transmit data from MAC
//   - tx_en     : Transmit enable
//   - tx_er     : Transmit error
//
// Features:
//   - Preamble and SFD detection
//   - Frame boundary detection via TX_EN
//   - Byte stream reconstruction
//   - CRC32 verification
//   - Error detection (TX_ER, CRC errors, runt frames)
//   - Analysis port for scoreboard integration
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_monitor extends uvm_monitor;

  `uvm_component_utils(gmii_monitor)

  virtual gmii_if vif;
  gmii_config cfg;
  
  uvm_analysis_port #(gmii_item) rx_ap;
  uvm_analysis_port #(gmii_item) tx_ap;

  //==========================================================================
  // Internal State
  //==========================================================================
  typedef enum {
      MON_IDLE,
      MON_PREAMBLE,
      MON_DATA
  } monitor_state_e;

  monitor_state_e state_rx;
  monitor_state_e state_tx;
  bit [7:0] frame_buffer_rx[$];
  bit [7:0] frame_buffer_tx[$];
  int unsigned preamble_count_rx;
  int unsigned preamble_count_tx;
  bit tx_error_seen;
  bit rx_error_seen;

  // Configurable parameters
  bit min_frame_size;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_ap = new("rx_ap", this);
    tx_ap = new("tx_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(gmii_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Config object not found")

    min_frame_size = cfg.min_frame_size;

    if(!uvm_config_db#(virtual gmii_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not set for gmii_monitor")
  endfunction

  task run_phase(uvm_phase phase);
  fork
    begin
      // Initialize state
      state_rx = MON_IDLE;
      frame_buffer_rx.delete();
      preamble_count_rx = 0;
      rx_error_seen = 0;

      forever begin
          @(vif.rx_monitor_cb);
          monitor_rx_cycle();
      end
    end

    begin
      // Initialize state
      state_tx = MON_IDLE;
      frame_buffer_tx.delete();
      preamble_count_tx = 0;
      tx_error_seen = 0;

      forever begin
          @(vif.tx_monitor_cb);
          monitor_tx_cycle();
      end
    end
  join_any
  endtask

  task monitor_tx_cycle();
    gmii_item item;
    bit [7:0] data;
    bit       tx_en;
    bit       tx_er;
    
    // Sample signals
    data  = vif.tx_monitor_cb.txd;
    tx_en = vif.tx_monitor_cb.tx_en;
    tx_er = vif.tx_monitor_cb.tx_er;

    case (state_tx)
      //------------------------------------------------------------------
      // IDLE: Waiting for TX_EN assertion
      //------------------------------------------------------------------
      MON_IDLE: begin
        if (tx_en) begin
          if (data == PREAMBLE_BYTE) begin
            state_tx = MON_PREAMBLE;
            preamble_count_tx = 1;
            frame_buffer_tx.delete();
            tx_error_seen = 0;
            `uvm_info("GMII_TX_MON", "Preamble detected, frame starting", UVM_HIGH)
          end else if (data == SFD_BYTE) begin
            // Short preamble or immediate SFD
            state_tx = MON_DATA;
            frame_buffer_tx.delete();
            tx_error_seen = 0;
            `uvm_info("GMII_TX_MON", "SFD detected (short preamble)", UVM_HIGH)
          end
        end
      end
        
      //------------------------------------------------------------------
      // PREAMBLE: Receiving preamble bytes, waiting for SFD
      //------------------------------------------------------------------
      MON_PREAMBLE: begin
        if (!tx_en) begin
          // Premature end
          `uvm_warning("GMII_TX_MON", "TX_EN deasserted during preamble")
          state_tx = MON_IDLE;
        end else if (data == PREAMBLE_BYTE) begin
          preamble_count_tx++;
        end else if (data == SFD_BYTE) begin
          state_tx = MON_DATA;
          `uvm_info("GMII_TX_MON", $sformatf("SFD detected after %0d preamble bytes", 
                    preamble_count_tx), UVM_HIGH)
        end else begin
          `uvm_warning("GMII_TX_MON", $sformatf("Invalid preamble byte: 0x%02h", data))
          state_tx = MON_IDLE;
        end
        
        if (tx_er) begin
          tx_error_seen = 1;
        end
      end
        
      //------------------------------------------------------------------
      // DATA: Receiving frame data until TX_EN deasserts
      //------------------------------------------------------------------
      MON_DATA: begin
        if (!tx_en) begin
          // End of frame
          item = process_frame(frame_buffer_tx, tx_error_seen);
          if(item != null)
            tx_ap.write(item);
          state_tx = MON_IDLE;
        end else begin
          // Capture data byte
          frame_buffer_tx.push_back(data);
          `uvm_info("GMII_TX_MON", $sformatf("DATA[%0d] = %02h", frame_buffer_tx.size()-1, data), UVM_DEBUG)
          
          if (tx_er) begin
            tx_error_seen = 1;
            `uvm_info("GMII_TX_MON", $sformatf("TX_ER asserted at byte %0d", 
                      frame_buffer_tx.size()), UVM_MEDIUM)
          end
        end
      end
        
      default: begin
        state_tx = MON_IDLE;
      end
    endcase
  endtask

    task monitor_rx_cycle();
    gmii_item item;
    bit [7:0] data;
    bit       rx_dv;
    bit       rx_er;
    
    // Sample signals
    data  = vif.rx_monitor_cb.rxd;
    rx_dv = vif.rx_monitor_cb.rx_dv;
    rx_er = vif.rx_monitor_cb.rx_er;

    case (state_rx)
      //------------------------------------------------------------------
      // IDLE: Waiting for RX_DV assertion
      //------------------------------------------------------------------
      MON_IDLE: begin
        if (rx_dv) begin
          if (data == PREAMBLE_BYTE) begin
            state_rx = MON_PREAMBLE;
            preamble_count_rx = 1;
            frame_buffer_rx.delete();
            rx_error_seen = 0;
            `uvm_info("GMII_RX_MON", "Preamble detected, frame starting", UVM_HIGH)
          end else if (data == SFD_BYTE) begin
            // Short preamble or immediate SFD
            state_rx = MON_DATA;
            frame_buffer_rx.delete();
            rx_error_seen = 0;
            `uvm_info("GMII_RX_MON", "SFD detected (short preamble)", UVM_HIGH)
          end
        end
      end
        
      //------------------------------------------------------------------
      // PREAMBLE: Receiving preamble bytes, waiting for SFD
      //------------------------------------------------------------------
      MON_PREAMBLE: begin
        if (!rx_dv) begin
          // Premature end
          `uvm_warning("GMII_RX_MON", "RX_DV deasserted during preamble")
          state_rx = MON_IDLE;
        end else if (data == PREAMBLE_BYTE) begin
          preamble_count_rx++;
        end else if (data == SFD_BYTE) begin
          state_rx = MON_DATA;
          `uvm_info("GMII_RX_MON", $sformatf("SFD detected after %0d preamble bytes", 
                    preamble_count_rx), UVM_HIGH)
        end else begin
          `uvm_warning("GMII_RX_MON", $sformatf("Invalid preamble byte: 0x%02h", data))
          state_rx = MON_IDLE;
        end

        if (rx_er) begin
          rx_error_seen = 1;
        end
      end
        
      //------------------------------------------------------------------
      // DATA: Receiving frame data until RX_DV deasserts
      //------------------------------------------------------------------
      MON_DATA: begin
        if (!rx_dv) begin
          // End of frame
          item = process_frame(frame_buffer_rx, rx_error_seen);
          if(item != null)
            rx_ap.write(item);
          state_rx = MON_IDLE;
        end else begin
          // Capture data byte
          frame_buffer_rx.push_back(data);
          `uvm_info("GMII_RX_MON", $sformatf("DATA[%0d] = %02h", frame_buffer_rx.size()-1, data), UVM_DEBUG)

          if (rx_er) begin
            rx_error_seen = 1;
            `uvm_info("GMII_RX_MON", $sformatf("RX_ER asserted at byte %0d", 
                      frame_buffer_rx.size()), UVM_MEDIUM)
          end
        end
      end
        
      default: begin
        state_rx = MON_IDLE;
      end
    endcase
  endtask

  function gmii_item process_frame(byte unsigned frame_buffer[$], bit error_seen);
    gmii_item frame;
    bit [7:0] frame_bytes[];
    bit [31:0] calc_crc;
    bit [31:0] recv_crc;
    int idx = 0;

    if (frame_buffer.size() < 4) begin
      `uvm_warning("GMII_MON", $sformatf("Frame too short: %0d bytes", frame_buffer.size()))
      return frame;
    end
    
    // Create frame object
    frame = gmii_item::type_id::create("monitored_frame");
    
    // Record timing
    frame.end_time = $time;
    
    // Copy buffer to array
    frame_bytes = new[frame_buffer.size()];
    foreach (frame_buffer[i]) begin
        frame_bytes[i] = frame_buffer[i];
    end
    
    // Set frame from bytes
    frame.set_from_bytes(frame_bytes);
    
    // Check frame length
    frame.frame_length = frame_buffer.size();
    if (frame.frame_length < min_frame_size) begin
        frame.runt_detected = 1;
        `uvm_info("GMII_MON", $sformatf("Runt frame detected: %0d bytes", 
                  frame.frame_length), UVM_MEDIUM)
    end

    // Verify CRC
    if (frame_buffer.size() >= 18) begin
      // Calculate CRC on data (excluding received FCS)
      calc_crc = frame.calculate_crc();
      
      // Get received CRC (last 4 bytes)
      // Ethernet FCS is transmitted LSB first, so:
      // frame_bytes[size-4] = CRC[7:0]   (first transmitted)
      // frame_bytes[size-3] = CRC[15:8]
      // frame_bytes[size-2] = CRC[23:16]
      // frame_bytes[size-1] = CRC[31:24] (last transmitted)
      recv_crc = {frame_bytes[frame_buffer.size()-1],
                  frame_bytes[frame_buffer.size()-2],
                  frame_bytes[frame_buffer.size()-3],
                  frame_bytes[frame_buffer.size()-4]};
      
      if (calc_crc != recv_crc) begin
        frame.crc_error_detected = 1;
        frame.frame_valid = 0;
        `uvm_info("GMII_MON", $sformatf("CRC error: calc=0x%08h recv=0x%08h", 
                  calc_crc, recv_crc), UVM_MEDIUM)
      end else begin
        frame.frame_valid = !error_seen && !frame.runt_detected;
      end
    end
    
    // Log frame info
    `uvm_info("GMII_MON", $sformatf("Frame captured: %0d bytes, valid=%0b, crc_err=%0b, runt=%0b",
              frame.frame_length, frame.frame_valid, 
              frame.crc_error_detected, frame.runt_detected), UVM_MEDIUM)

    return frame;
  endfunction

endclass : gmii_monitor
