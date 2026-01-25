// File: tb/env/mac/mac_scoreboard.sv
class mac_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(mac_scoreboard)

  // Analysis ports (input)
  uvm_analysis_imp_gmii_rx#(gmii_item, mac_scoreboard)          gmii_rx_imp;
  uvm_analysis_imp_axis_tx#(axi_stream_item#(32,1,1,1), mac_scoreboard) axis_tx_imp;
  
  uvm_analysis_imp_gmii_tx#(gmii_item, mac_scoreboard)          gmii_tx_imp;
  uvm_analysis_imp_axis_rx#(axi_stream_item#(32,1,1,1), mac_scoreboard) axis_rx_imp;

  // Queues for checking
  gmii_item               rx_gmii_queue[$];
  axi_stream_item#(32,1,1,1) rx_axis_queue[$];
  
  gmii_item               tx_gmii_queue[$];
  axi_stream_item#(32,1,1,1) tx_axis_queue[$];

  // Statistics
  int rx_packets_matched = 0;
  int rx_packets_mismatched = 0;
  int tx_packets_matched = 0;
  int tx_packets_mismatched = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    gmii_rx_imp = new("gmii_rx_imp", this);
    axis_tx_imp = new("axis_tx_imp", this);
    gmii_tx_imp = new("gmii_tx_imp", this);
    axis_rx_imp = new("axis_rx_imp", this);
  endfunction

  // RX path: GMII → MAC → AXI-Stream
  function void write_gmii_rx(gmii_item item);
    rx_gmii_queue.push_back(item);
    check_rx_path();
  endfunction

  function void write_axis_tx(axi_stream_item#(32,1,1,1) item);
    rx_axis_queue.push_back(item);
    check_rx_path();
  endfunction

  function void check_rx_path();
    gmii_item gmii_pkt;
    axi_stream_item#(32,1,1,1) axis_pkt;
    byte unsigned gmii_payload[];
    byte unsigned axis_payload[];
    
    if(rx_gmii_queue.size() == 0 || rx_axis_queue.size() == 0) return;
    
    gmii_pkt = rx_gmii_queue.pop_front();
    axis_pkt = rx_axis_queue.pop_front();
    
    // Extract payloads (skip Ethernet header/FCS for GMII)
    gmii_payload = gmii_pkt.payload;
    axis_pkt.get_bytes(axis_payload);
    
    // Compare
    if(compare_payloads(gmii_payload, axis_payload)) begin
      `uvm_info("MAC_SB", $sformatf("RX path match: %0d bytes", gmii_payload.size()), UVM_MEDIUM)
      rx_packets_matched++;
    end else begin
      `uvm_error("MAC_SB", $sformatf("RX path mismatch!\nGMII: %p\nAXIS: %p", gmii_payload, axis_payload))
      rx_packets_mismatched++;
    end
  endfunction

  // TX path: AXI-Stream → MAC → GMII
  function void write_axis_rx(axi_stream_item#(32,1,1,1) item);
    tx_axis_queue.push_back(item);
    check_tx_path();
  endfunction

  function void write_gmii_tx(gmii_item item);
    tx_gmii_queue.push_back(item);
    check_tx_path();
  endfunction

  function void check_tx_path();
    gmii_item gmii_pkt;
    axi_stream_item#(32,1,1,1) axis_pkt;
    byte unsigned gmii_payload[];
    byte unsigned axis_payload[];
    
    if(tx_axis_queue.size() == 0 || tx_gmii_queue.size() == 0) return;
    
    axis_pkt = tx_axis_queue.pop_front();
    gmii_pkt = tx_gmii_queue.pop_front();
    
    // Extract payloads
    axis_pkt.get_bytes(axis_payload);
    gmii_payload = gmii_pkt.payload;
    
    // Compare
    if(compare_payloads(axis_payload, gmii_payload)) begin
      `uvm_info("MAC_SB", $sformatf("TX path match: %0d bytes", axis_payload.size()), UVM_MEDIUM)
      tx_packets_matched++;
    end else begin
      `uvm_error("MAC_SB", $sformatf("TX path mismatch!\nAXIS: %p\nGMII: %p", axis_payload, gmii_payload))
      tx_packets_mismatched++;
    end
  endfunction

  function bit compare_payloads(byte unsigned a[], byte unsigned b[]);
    if(a.size() != b.size()) return 0;
    foreach(a[i])
      if(a[i] != b[i]) return 0;
    return 1;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("MAC_SB", $sformatf("=== MAC Scoreboard Statistics ==="), UVM_NONE)
    `uvm_info("MAC_SB", $sformatf("RX Matched: %0d, Mismatched: %0d", rx_packets_matched, rx_packets_mismatched), UVM_NONE)
    `uvm_info("MAC_SB", $sformatf("TX Matched: %0d, Mismatched: %0d", tx_packets_matched, tx_packets_mismatched), UVM_NONE)
    
    if(rx_packets_mismatched > 0 || tx_packets_mismatched > 0)
      `uvm_error("MAC_SB", "Mismatches detected!")
  endfunction

endclass : mac_scoreboard

// Analysis port macros
`uvm_analysis_imp_decl(_gmii_rx)
`uvm_analysis_imp_decl(_axis_tx)
`uvm_analysis_imp_decl(_gmii_tx)
`uvm_analysis_imp_decl(_axis_rx)
