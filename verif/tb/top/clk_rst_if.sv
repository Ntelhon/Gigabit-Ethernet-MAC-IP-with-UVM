// File: clk_rst_if.sv
interface clk_rst_if;
  logic clk;
  logic rst_n;
  interface clk_rst_if (
    input logic clk,
    input logic rst_n
  );
    task automatic wait_clks(int num_clks);
      repeat(num_clks) @(posedge clk);
    endtask
    task automatic assert_reset(int cycles = 10);
      rst_n = 1'b0;
      repeat(cycles) @(posedge clk);
      rst_n = 1'b1;
    endtask
endinterface : clk_rst_if
