// File: tb/env/eth_controller/eth_scoreboard.sv
class eth_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(eth_scoreboard)

  // Analysis ports for end-to-end checking
  uvm_analysis_imp_gmii#(gmii_item, eth_scoreboard)                     gmii_imp;
  uvm_analysis_imp_axi4#(axi4_item#(32,64,4,1), eth_scoreboard)         axi4_imp;
  uvm_analysis_imp_axis_mac_tx#(axi_stream_item#(32,1,1,1), eth_scoreboard) axis_mac_tx_imp;
  uvm_analysis_imp_axis_mac_rx#(axi_stream_item#(32,1,1,1), eth_scoreboard) axis_mac_rx_imp;

  // Reference to memory model
  memory_model mem;
  
  // Packet tracking
  typedef struct {
    byte unsigned payload[];
    bit [31:0]    buffer_addr;
    time          timestamp;
  } packet_tracker_t;
  
  packet_tracker_t tx_packets[$];  // Packets sent to memory by DMA
  packet_tracker_t rx_packets[$];  // Packets received from PHY
  
  // Statistics
  int end_to_end_tx_matched = 0;
  int end_to_end_rx_matched = 0;
  int end_to_end_mismatches = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    gmii_imp         = new("gmii_imp", this);
    axi4_imp         = new("axi4_imp", this);
    axis_mac_tx_imp  = new("axis_mac_tx_imp", this);
    axis_mac_rx_imp  = new("axis_mac_rx_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(memory_model)::get(this, "", "mem", mem))
      `uvm_warning("ETH_SB", "Memory model not found")
  endfunction

  // GMII packets (PHY side)
  function void write_gmii(gmii_item item);
    packet_tracker_t pkt;
    pkt.payload = item.payload;
    pkt.timestamp = $time;
    rx_packets.push_back(pkt);
    `uvm_info("ETH_SB", $sformatf("RX packet from PHY: %0d bytes", item.payload.size()), UVM_MEDIUM)
  endfunction

  // AXI4 transactions (Memory side)
  function void write_axi4(axi4_item#(32,64,4,1) item);
    if(item.trans_type == AXI4_WRITE) begin
      packet_tracker_t pkt;
      byte unsigned byte_data[];
      int byte_idx = 0;
      
      // Extract bytes from AXI4 write
      byte_data = new[item.data.size() * 8];
      foreach(item.data[i]) begin
        for(int j = 0; j < 8; j++) begin
          if(item.strb[i][j])
            byte_data[byte_idx++] = item.data[i][j*8 +: 8];
        end
      end
      byte_data = new[byte_idx](byte_data);
      
      pkt.payload = byte_data;
      pkt.buffer_addr = item.addr;
      pkt.timestamp = $time;
      tx_packets.push_back(pkt);
      `uvm_info("ETH_SB", $sformatf("TX packet to memory: addr=0x%0h, %0d bytes", 
                                     item.addr, byte_data.size()), UVM_MEDIUM)
    end
  endfunction

  // AXI-Stream MAC TX (MAC → DMA)
  function void write_axis_mac_tx(axi_stream_item#(32,1,1,1) item);
    // Could track for additional checks
    `uvm_info("ETH_SB", "AXI-Stream MAC TX observed", UVM_HIGH)
  endfunction

  // AXI-Stream MAC RX (DMA → MAC)
  function void write_axis_mac_rx(axi_stream_item#(32,1,1,1) item);
    // Could track for additional checks
    `uvm_info("ETH_SB", "AXI-Stream MAC RX observed", UVM_HIGH)
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("ETH_SB", "=== System-Level Scoreboard Statistics ===", UVM_NONE)
    `uvm_info("ETH_SB", $sformatf("End-to-end TX matched: %0d", end_to_end_tx_matched), UVM_NONE)
    `uvm_info("ETH_SB", $sformatf("End-to-end RX matched: %0d", end_to_end_rx_matched), UVM_NONE)
    `uvm_info("ETH_SB", $sformatf("Mismatches: %0d", end_to_end_mismatches), UVM_NONE)
    
    if(tx_packets.size() > 0)
      `uvm_warning("ETH_SB", $sformatf("Unmatched TX packets: %0d", tx_packets.size()))
    if(rx_packets.size() > 0)
      `uvm_warning("ETH_SB", $sformatf("Unmatched RX packets: %0d", rx_packets.size()))
  endfunction

endclass : eth_scoreboard

`uvm_analysis_imp_decl(_gmii)
`uvm_analysis_imp_decl(_axi4)
`uvm_analysis_imp_decl(_axis_mac_tx)
`uvm_analysis_imp_decl(_axis_mac_rx)
