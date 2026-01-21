//==============================================================================
// Class: gmii_rx_seq
// Description: GMII sequence for receiving a single frame
//
// Purpose:
//   Receives a single Ethernet frame from the MAC's transmit path via the GMII
//   interface. The GMII driver captures the frame as if coming from a PHY.
//
// Note: "RX" from sequence perspective means receiving FROM the MAC, which is
//       actually the MAC's RX (receive) path.
//
// Usage:
//   gmii_rx_seq seq = gmii_rx_seq::type_id::create("seq");
//   seq.frame = my_frame;  // Set the frame to receive
//   seq.start(gmii_sequencer);
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_rx_seq extends uvm_sequence #(gmii_frame);

    `uvm_object_utils(gmii_rx_seq)

    //==========================================================================
    // Properties
    //==========================================================================
    
    gmii_frame frame;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "gmii_rx_seq");
        super.new(name);
    endfunction
    
    //==========================================================================
    // Body Task
    //==========================================================================
    virtual task body();
        gmii_frame req;

        if (frame == null) begin
            `uvm_error("GMII_RX_SEQ", "Frame is null! Must set frame before starting sequence.")
            return;
        end
        
        // Create a new frame for the transaction
        req = gmii_frame::type_id::create("req");

        start_item(req);

        // Assign the frame to the transaction
        req.copy(frame);

        //// Copy frame data to the transaction
        //req.dst_mac = frame.dst_mac;
        //req.src_mac = frame.src_mac;
        //req.ether_type = frame.ether_type;
        //req.payload = new[frame.payload.size()];
        //foreach(frame.payload[i]) req.payload[i] = frame.payload[i];
        //req.has_fcs = frame.has_fcs;
        //
        //// Copy error injection flags
        //req.inject_crc_error = frame.inject_crc_error;
        //req.inject_fcs_error = frame.inject_fcs_error;
        //req.send_as_runt = frame.send_as_runt;
        //req.inject_ifg_violation = frame.inject_ifg_violation;
        //req.ifg_bytes = frame.ifg_bytes;
        //req.inject_rx_error = frame.inject_rx_error;
        //req.rx_error_byte_pos = frame.rx_error_byte_pos;
        //req.preamble_bytes = frame.preamble_bytes;

        // Send the frame to the MAC
        finish_item(req);

        `uvm_info("GMII_RX_SEQ", $sformatf("Frame send to Driver: %s", req.convert2string()), UVM_DEBUG)
    endtask

endclass : gmii_rx_seq
