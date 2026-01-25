// File: eth_tb_top.sv
module eth_tb_top;
	import eth_pkg::*;
	logic clk;
	logic rst_n;
	initial begin
		clk = 0;
		forever #5 clk = ~clk;
	end
	initial begin
		rst_n = 0;
		#100 rst_n = 1;
	end
	axi_lite_if axi_lite_if_inst(clk, rst_n);
	gmii_if gmii_if_inst(clk, rst_n);
	initial begin
		run_test();
	end
endmodule : eth_tb_top
