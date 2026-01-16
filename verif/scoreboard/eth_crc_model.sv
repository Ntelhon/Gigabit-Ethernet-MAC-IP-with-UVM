//==============================================================================
// Class: eth_crc_model
// Description: Ethernet CRC32 reference model for scoreboard verification
//
// Purpose:
//   Provides a pure SystemVerilog implementation of the Ethernet CRC32
//   algorithm for validating frame integrity in the scoreboard.
//
// Algorithm:
//   - Polynomial: 0x04C11DB7
//   - Reflected polynomial: 0xEDB88320
//   - Initial value: 0xFFFFFFFF
//   - Input reflection: Yes (LSB first)
//   - Output reflection: Yes
//   - Final XOR: 0xFFFFFFFF
//   - Check value for "123456789": 0xCBF43926
//   - Magic residue (after valid FCS): 0xC704DD7B
//
// Features:
//   - Byte-wise CRC calculation
//   - Frame CRC generation
//   - Frame CRC verification
//   - No DPI dependencies
//   - Deterministic behavior
//
// Compatibility:
//   - UVM 1.2
//   - Vivado xsim
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

class eth_crc_model extends uvm_object;

    //==========================================================================
    // UVM Factory Registration
    //==========================================================================
    `uvm_object_utils(eth_crc_model)

    //==========================================================================
    // Constants
    //==========================================================================
    
    // Reflected polynomial (0x04C11DB7 reflected)
    localparam bit [31:0] POLY = 32'hEDB88320;
    
    // Initial CRC value
    localparam bit [31:0] INIT_CRC = 32'hFFFFFFFF;
    
    // Magic residue after valid frame with FCS
    localparam bit [31:0] MAGIC_RESIDUE = 32'hC704DD7B;

    //==========================================================================
    // CRC Lookup Table
    // Pre-computed for faster calculation
    //==========================================================================
    static bit [31:0] crc_table[256];
    static bit table_initialized = 0;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "eth_crc_model");
        super.new(name);
        
        // Initialize CRC table on first instantiation
        if (!table_initialized) begin
            init_crc_table();
            table_initialized = 1;
        end
    endfunction

    //==========================================================================
    // Initialize CRC lookup table
    //==========================================================================
    static function void init_crc_table();
        bit [31:0] crc;
        
        for (int i = 0; i < 256; i++) begin
            crc = i;
            for (int j = 0; j < 8; j++) begin
                if (crc[0])
                    crc = (crc >> 1) ^ POLY;
                else
                    crc = crc >> 1;
            end
            crc_table[i] = crc;
        end
    endfunction

    //==========================================================================
    // Calculate CRC for a single byte (update running CRC)
    //==========================================================================
    function bit [31:0] crc_byte(bit [31:0] crc, bit [7:0] data);
        bit [7:0] table_index;
        
        table_index = crc[7:0] ^ data;
        return (crc >> 8) ^ crc_table[table_index];
    endfunction

    //==========================================================================
    // Calculate CRC32 for a byte array
    // Returns the final CRC value (complemented)
    //==========================================================================
    function bit [31:0] calculate_crc(input bit [7:0] data[], int length = -1);
        bit [31:0] crc;
        int len;
        
        crc = INIT_CRC;
        len = (length < 0) ? data.size() : length;
        
        for (int i = 0; i < len; i++) begin
            crc = crc_byte(crc, data[i]);
        end
        
        // Final complement
        return ~crc;
    endfunction

    //==========================================================================
    // Calculate CRC32 for a byte queue
    //==========================================================================
    function bit [31:0] calculate_crc_queue(input bit [7:0] data[$], int length = -1);
        bit [31:0] crc;
        int len;
        
        crc = INIT_CRC;
        len = (length < 0) ? data.size() : length;
        
        for (int i = 0; i < len; i++) begin
            crc = crc_byte(crc, data[i]);
        end
        
        // Final complement
        return ~crc;
    endfunction

    //==========================================================================
    // Generate FCS bytes (to be appended to frame)
    // Returns 4 bytes in transmission order (LSB first)
    //==========================================================================
    function void generate_fcs(
        input bit [7:0] data[],
        output bit [7:0] fcs[4]
    );
        bit [31:0] crc;
        
        crc = calculate_crc(data);
        
        // FCS transmitted LSB first
        fcs[0] = crc[7:0];
        fcs[1] = crc[15:8];
        fcs[2] = crc[23:16];
        fcs[3] = crc[31:24];
    endfunction

    //==========================================================================
    // Verify CRC of a complete frame (including FCS)
    // Returns 1 if CRC is valid (residue matches)
    //==========================================================================
    function bit verify_crc(input bit [7:0] frame_with_fcs[]);
        bit [31:0] crc;
        
        crc = INIT_CRC;
        
        // Process entire frame including FCS
        for (int i = 0; i < frame_with_fcs.size(); i++) begin
            crc = crc_byte(crc, frame_with_fcs[i]);
        end
        
        // Check for magic residue (CRC register value after valid frame)
        // Note: We compare against ~MAGIC_RESIDUE because we haven't complemented
        return (crc == 32'hDEBB20E3);  // ~0xC704DD7B before complement
    endfunction

    //==========================================================================
    // Verify CRC and return expected vs actual
    //==========================================================================
    function bit verify_crc_detailed(
        input bit [7:0] frame_with_fcs[],
        output bit [31:0] expected_crc,
        output bit [31:0] received_crc
    );
        int data_len;
        bit [7:0] data_only[];
        
        if (frame_with_fcs.size() < 4) begin
            expected_crc = 32'h0;
            received_crc = 32'h0;
            return 0;
        end
        
        // Extract data portion (excluding FCS)
        data_len = frame_with_fcs.size() - 4;
        data_only = new[data_len];
        
        for (int i = 0; i < data_len; i++) begin
            data_only[i] = frame_with_fcs[i];
        end
        
        // Calculate expected CRC
        expected_crc = calculate_crc(data_only);
        
        // Extract received CRC (last 4 bytes, LSB first)
        received_crc = {frame_with_fcs[frame_with_fcs.size()-1],
                        frame_with_fcs[frame_with_fcs.size()-2],
                        frame_with_fcs[frame_with_fcs.size()-3],
                        frame_with_fcs[frame_with_fcs.size()-4]};
        
        return (expected_crc == received_crc);
    endfunction

    //==========================================================================
    // Self-test function
    // Verifies CRC implementation with known test vector
    //==========================================================================
    function bit self_test();
        bit [7:0] test_data[9];
        bit [31:0] crc;
        bit [31:0] expected_crc;
        
        // Test vector: "123456789"
        test_data[0] = 8'h31;  // '1'
        test_data[1] = 8'h32;  // '2'
        test_data[2] = 8'h33;  // '3'
        test_data[3] = 8'h34;  // '4'
        test_data[4] = 8'h35;  // '5'
        test_data[5] = 8'h36;  // '6'
        test_data[6] = 8'h37;  // '7'
        test_data[7] = 8'h38;  // '8'
        test_data[8] = 8'h39;  // '9'
        
        // Expected CRC for "123456789"
        expected_crc = 32'hCBF43926;
        
        crc = calculate_crc(test_data);
        
        if (crc !== expected_crc) begin
            `uvm_error("CRC_MODEL", $sformatf(
                "Self-test FAILED: expected=0x%08h, calculated=0x%08h",
                expected_crc, crc))
            return 0;
        end
        
        `uvm_info("CRC_MODEL", "Self-test PASSED", UVM_LOW)
        return 1;
    endfunction

    //==========================================================================
    // Compare two byte arrays
    //==========================================================================
    static function bit compare_bytes(
        input bit [7:0] a[],
        input bit [7:0] b[],
        output int first_mismatch
    );
        first_mismatch = -1;
        
        if (a.size() != b.size()) begin
            first_mismatch = (a.size() < b.size()) ? a.size() : b.size();
            return 0;
        end
        
        for (int i = 0; i < a.size(); i++) begin
            if (a[i] !== b[i]) begin
                first_mismatch = i;
                return 0;
            end
        end
        
        return 1;
    endfunction

endclass : eth_crc_model
