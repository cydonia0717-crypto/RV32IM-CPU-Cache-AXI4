`timescale 1ns/1ps
module tb_muldiv;
 reg clk=0,rst=1,start=0;
 always #5 clk=~clk;
 reg [2:0] op; reg [31:0] a,b; wire busy,done; wire [31:0] result;
 rv32_muldiv dut(clk,rst,start,op,a,b,busy,done,result);
 reg [99:0] vectors[0:2559];
 integer i,latency;
 initial begin
  $readmemh("build/muldiv.hex",vectors);
  repeat(3) @(negedge clk);rst=0;
  for(i=0;i<2560;i=i+1) begin
   @(negedge clk); op=vectors[i][98:96]; a=vectors[i][95:64]; b=vectors[i][63:32]; start=1;
   @(negedge clk); start=0; latency=0;
   while(!done) begin @(negedge clk); latency=latency+1; if(latency>33) $fatal(1,"unit timeout"); end
   if(result!==vectors[i][31:0]) $fatal(1,"op=%0d a=%x b=%x got=%x expected=%x",op,a,b,result,vectors[i][31:0]);
   if(latency!=32) $fatal(1,"unexpected latency %d",latency);
  end
  $display("PASS muldiv vectors=2560 latency=32"); $finish;
 end
endmodule
