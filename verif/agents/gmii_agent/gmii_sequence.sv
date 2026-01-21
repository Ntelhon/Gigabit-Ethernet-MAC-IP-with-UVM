//==============================================================================
// Class: gmii_sequence
// Description: Base sequence for GMII frame transmission
//
// Purpose:
//   Provides a simple sequence to send a single GMII frame.
//   Can be extended for more complex frame generation patterns.
//
// Usage:
//   gmii_sequence seq = gmii_sequence::type_id::create("seq");
//   seq.frame = my_frame;
//   seq.start(gmii_sequencer);
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class gmii_sequence extends uvm_sequence #(gmii_frame);

    `uvm_object_utils(gmii_sequence)
    
    //==========================================================================
    // Properties
    //==========================================================================
    
    // Frame to transmit (set before calling start())
    gmii_frame frame;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "gmii_sequence");
        super.new(name);
    endfunction
    
    //==========================================================================
    // Body Task
    //==========================================================================
    virtual task body();
        if (frame == null) begin
            `uvm_error("GMII_SEQ", "Frame is null! Must set frame before starting sequence.")
            return;
        end
        
        // Send the frame
        start_item(frame);
        finish_item(frame);
        
        `uvm_info("GMII_SEQ", $sformatf("Sent frame: DA=%012h SA=%012h len=%0d", 
                  frame.dst_mac, frame.src_mac, frame.payload.size()), UVM_HIGH)
    endtask

endclass : gmii_sequence
