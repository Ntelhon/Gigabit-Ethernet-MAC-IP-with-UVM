// File: gmii_agent_includes.svh

// GMII Direction Enum
typedef enum {GMII_TX, GMII_RX} gmii_direction_e;

localparam bit [7:0] PREAMBLE_BYTE = 8'h55;
localparam bit [7:0] SFD_BYTE      = 8'hD5;