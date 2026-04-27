module isa (
    input wire CLOCK_50,
    input wire KEY0,
	output reg LEDG8
);

	wire reset = ~KEY0;
	reg clk;
	reg [25:0] counter;
	
	always @(posedge CLOCK_50 or posedge reset) begin
		if(reset)
			counter <= 26'd0;
		else
			counter <= counter + 26'd1;
	end
	
	always @(*) begin
		LEDG8 <= counter[25];  // blink for clock
		clk <= counter[25];
	end
	
	cpu uut (
		.clk(clk),
		.reset(reset)
	);
endmodule