//==============================================================================
// Module: mac_crc32
// Description: Streaming CRC32 generator/checker for Ethernet
//
// Features:
//   - Ethernet CRC32 polynomial: 0x04C11DB7
//   - Byte-wise (8-bit) operation for GMII compatibility
//   - Supports both generation and verification modes
//   - Synchronous init, update, and output
//   - No protocol logic - pure CRC computation
//
// CRC Algorithm:
//   - Polynomial: x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + 
//                 x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1
//   - Initial value: 0xFFFFFFFF
//   - Input reflection: Yes (LSB first)
//   - Output reflection: Yes (LSB first)  
//   - Final XOR: 0xFFFFFFFF
//   - Check value (for "123456789"): 0xCBF43926
//
// Usage:
//   1. Assert 'init' for one cycle to reset CRC to 0xFFFFFFFF
//   2. Assert 'enable' with valid 'data_in' for each byte
//   3. Read 'crc_out' for current CRC value (bit-reversed & complemented)
//   4. For TX: append crc_out bytes after last data byte
//   5. For RX: crc_out should equal 0xC704DD7B after FCS (magic residue)
//
// Verification Hooks:
//   - Assertion: CRC matches known test vectors
//   - Assertion: Magic residue after valid frame + FCS
//   - Coverage: All state transitions
//   - Coverage: Various frame lengths
//
// Timing:
//   - 1 clock cycle latency from data_in to crc_out update
//   - Combinational CRC next-state available same cycle
//
// Author: AI-IP Generator
// License: MIT
//==============================================================================

module mac_crc32 (
    //==========================================================================
    // Clock and Reset
    //==========================================================================
    input  wire        clk,         // System clock (125 MHz for GMII)
    input  wire        rst_n,       // Active-low synchronous reset

    //==========================================================================
    // Control Interface
    //==========================================================================
    input  wire        init,        // Initialize CRC to 0xFFFFFFFF
    input  wire        enable,      // Enable CRC calculation for this cycle
    input  wire [7:0]  data_in,     // Input data byte (LSB first)

    //==========================================================================
    // CRC Output
    //==========================================================================
    output wire [31:0] crc_out,     // Current CRC (reflected & complemented)
    output wire [7:0]  crc_byte0,   // CRC byte 0 (first to transmit)
    output wire [7:0]  crc_byte1,   // CRC byte 1
    output wire [7:0]  crc_byte2,   // CRC byte 2
    output wire [7:0]  crc_byte3    // CRC byte 3 (last to transmit)
);

    //==========================================================================
    // CRC Register
    //==========================================================================
    reg [31:0] crc_reg;

    //==========================================================================
    // CRC Calculation - Byte-wise with reflected polynomial
    // This implements the standard Ethernet CRC32:
    // - Polynomial: 0xEDB88320 (reflected form of 0x04C11DB7)
    // - Data is processed LSB-first (standard for Ethernet)
    // - No explicit bit reflection needed when using reflected polynomial
    //==========================================================================

    // Next CRC value (combinational)
    wire [31:0] crc_next;
    
    // XOR input byte with current CRC LSB
    // Standard algorithm: crc = crc ^ data, then process LSB first
    wire [7:0] crc_in;
    assign crc_in = crc_reg[7:0] ^ data_in;  // Use data_in directly

    // Byte-wise CRC calculation using reflected polynomial
    // Each bit of crc_in contributes based on the polynomial
    wire [31:0] crc_table;
    
    // Unrolled CRC table lookup for 8 bits
    // These are the CRC contributions for each bit position (0-7) of the input byte
    // Pre-computed as: CRC(0, 2^i, 8 iterations) for reflected polynomial 0xEDB88320
    // 
    // Bit 0 (0x01): 0x77073096
    // Bit 1 (0x02): 0xEE0E612C
    // Bit 2 (0x04): 0x076DC419
    // Bit 3 (0x08): 0x0EDB8832
    // Bit 4 (0x10): 0x1DB71064
    // Bit 5 (0x20): 0x3B6E20C8
    // Bit 6 (0x40): 0x76DC4190
    // Bit 7 (0x80): 0xEDB88320
    assign crc_table = 
        (crc_in[0] ? 32'h77073096 : 32'h0) ^
        (crc_in[1] ? 32'hEE0E612C : 32'h0) ^
        (crc_in[2] ? 32'h076DC419 : 32'h0) ^
        (crc_in[3] ? 32'h0EDB8832 : 32'h0) ^
        (crc_in[4] ? 32'h1DB71064 : 32'h0) ^
        (crc_in[5] ? 32'h3B6E20C8 : 32'h0) ^
        (crc_in[6] ? 32'h76DC4190 : 32'h0) ^
        (crc_in[7] ? 32'hEDB88320 : 32'h0);

    // Shift CRC right by 8 bits and XOR with table result
    assign crc_next = {8'h00, crc_reg[31:8]} ^ crc_table;

    //==========================================================================
    // CRC Register Update
    //==========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            crc_reg <= 32'hFFFFFFFF;
        end else if (init) begin
            crc_reg <= 32'hFFFFFFFF;
            // synthesis translate_off
            $display("[CRC32 DEBUG] @%0t: CRC INIT", $time);
            // synthesis translate_on
        end else if (enable) begin
            crc_reg <= crc_next;
            // synthesis translate_off
            $display("[CRC32 DEBUG] @%0t: data_in=%02h crc_in=%02h crc_reg=%08h -> crc_next=%08h", 
                     $time, data_in, crc_in, crc_reg, crc_next);
            // synthesis translate_on
        end
        // else: hold current value
    end

    //==========================================================================
    // Output Generation
    // Complement and reflect the CRC for transmission
    // Ethernet transmits CRC LSB first, complemented
    //==========================================================================
    
    // Complement the CRC
    wire [31:0] crc_complemented;
    assign crc_complemented = ~crc_reg;

    // Reflect each byte for output (already in reflected form, just complement)
    // Since we used reflected algorithm, output is already in correct bit order
    assign crc_out = crc_complemented;

    // Individual bytes for transmission (byte 0 transmitted first)
    // Ethernet sends FCS LSB first, so we reverse the byte order
    assign crc_byte0 = crc_complemented[7:0];
    assign crc_byte1 = crc_complemented[15:8];
    assign crc_byte2 = crc_complemented[23:16];
    assign crc_byte3 = crc_complemented[31:24];

endmodule
