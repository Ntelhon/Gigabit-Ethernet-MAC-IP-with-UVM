package mac_subenvironment_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Import agent packages (needed for sub-environment)
  import axi_stream_pkg::*;
  import axi4_pkg::*;

  // MAC Sub-Environment Components
  `include "mac_scoreboard.sv"
  `include "mac_config.sv"
  `include "mac_env.sv"

endpackage : mac_subenvironment_pkg
