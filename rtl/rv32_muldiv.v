`timescale 1ns/1ps
// 32-cycle shift/add multiplier and restoring divider. No RTL * / % operators.
module rv32_muldiv(
 input wire clk, rst, start, input wire [2:0] op,
 input wire [31:0] a,b, output reg busy, done, output reg [31:0] result
);
 reg [2:0] operation;
 reg [5:0] count;
 reg negate_product, negate_q, negate_r, zero_div;
 reg [63:0] product, multiplicand;
 reg [31:0] multiplier, dividend, divisor, original_a;
 reg [30:0] quotient;
 reg [31:0] remainder;
 wire signed_a = (op==3'b001 || op==3'b010 || op==3'b100 || op==3'b110);
 wire signed_b = (op==3'b001 || op==3'b100 || op==3'b110);
 wire [31:0] abs_a = signed_a && a[31] ? (~a+32'd1) : a;
 wire [31:0] abs_b = signed_b && b[31] ? (~b+32'd1) : b;
 wire [63:0] next_product = product + (multiplier[0] ? multiplicand : 64'd0);
 wire [63:0] final_product = negate_product ? (~next_product+64'd1) : next_product;
 wire [32:0] trial = {remainder[31:0],dividend[31]};
 wire take = trial >= {1'b0,divisor};
 wire [31:0] next_remainder = take ? trial[31:0]-divisor : trial[31:0];
 wire [31:0] next_quotient = {quotient,take};
 wire [31:0] final_q = negate_q ? (~next_quotient+32'd1) : next_quotient;
 wire [31:0] final_r = negate_r ? (~next_remainder[31:0]+32'd1) : next_remainder[31:0];
 always @(posedge clk) begin
  if (rst) begin
   busy<=0; done<=0; result<=0; count<=0; operation<=0;
   product<=0; multiplicand<=0; multiplier<=0; dividend<=0; divisor<=0;
   quotient<=0; remainder<=0; negate_product<=0; negate_q<=0;
   negate_r<=0; zero_div<=0; original_a<=0;
  end else begin
   done<=0;
   if(start && !busy) begin
    busy<=1; count<=0; operation<=op;
    negate_product<=(signed_a && a[31]) ^ (signed_b && b[31]);
    negate_q<=(signed_a && a[31]) ^ (signed_b && b[31]);
    negate_r<=signed_a && a[31]; zero_div<=b==0; original_a<=a;
    product<=0; multiplicand<={32'd0,abs_a}; multiplier<=abs_b;
    dividend<=abs_a; divisor<=abs_b; quotient<=0; remainder<=0;
   end else if(busy) begin
    count<=count+1'b1;
    if(!operation[2]) begin
     product<=next_product; multiplicand<=multiplicand<<1; multiplier<=multiplier>>1;
     if(count==31) result<=operation==0 ? final_product[31:0] : final_product[63:32];
    end else begin
     remainder<=next_remainder; dividend<=dividend<<1; quotient<=next_quotient[30:0];
     if(count==31) result<=zero_div ? (operation[1] ? original_a : 32'hffffffff) :
                              (operation[1] ? final_r : final_q);
    end
    if(count==31) begin busy<=0; done<=1; end
   end
  end
 end
endmodule
