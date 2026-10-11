`timescale 1ns/1ps
module tb_cache;
 reg clk=0,rst=1,invalidate=0;
 always #5 clk=~clk;
 reg req_valid=0,req_write=0;
 wire req_ready,rsp_valid,rsp_error,mem_valid,mem_write;
 reg [31:0] req_addr=0,req_wdata=0; reg [3:0] req_wstrb=0;
 wire [31:0] rsp_data,mem_addr,mem_wdata,hits,misses;
 wire [3:0] mem_wstrb;
 reg mem_rsp_valid=0,mem_rsp_last=0,mem_rsp_error=0;
 reg [31:0] mem_rsp_data=0;
 rv32_cache #(.LINES(4),.INDEX_BITS(2)) dut(
  clk,rst,invalidate,req_valid,req_ready,req_addr,req_write,req_wdata,req_wstrb,
  rsp_valid,rsp_data,rsp_error,mem_valid,1'b1,mem_write,mem_addr,mem_wdata,mem_wstrb,
  mem_rsp_valid,mem_rsp_data,mem_rsp_last,mem_rsp_error,hits,misses);
 reg [31:0] ram[0:63];
 reg active=0,writing=0,fail_read=0,fail_write=0;
 reg [31:0] addr,data; reg [3:0] strb; reg [1:0] beat=0;
 integer i,lane,requests=0;
 reg [31:0] old_misses;
 always @(posedge clk) begin
  if(rst) begin active<=0; mem_rsp_valid<=0; end
  else begin
   mem_rsp_valid<=0;
   if(mem_valid) begin
    active<=1; writing<=mem_write; addr<=mem_addr; data<=mem_wdata; strb<=mem_wstrb; beat<=0;
    requests<=requests+1;
   end
   if(active && !mem_rsp_valid) begin
    mem_rsp_valid<=1;
    mem_rsp_data<=ram[addr>>2]; mem_rsp_last<=writing || beat==3;
    mem_rsp_error<=writing ? fail_write : (fail_read && beat==1);
    if(writing && !fail_write)
     for(lane=0;lane<4;lane=lane+1) if(strb[lane]) ram[addr>>2][8*lane+:8]<=data[8*lane+:8];
    if(writing || beat==3) active<=0;
    else begin addr<=addr+4; beat<=beat+1; end
   end
  end
 end
 task request;
  input wr; input [31:0] a,d; input [3:0] mask; input [31:0] expected; input error;
  integer timeout;
  begin
   @(negedge clk); while(!req_ready) @(negedge clk);
   req_valid=1; req_write=wr; req_addr=a; req_wdata=d; req_wstrb=mask;
   @(negedge clk); req_valid=0; timeout=0;
   while(!rsp_valid) begin @(negedge clk); timeout=timeout+1; if(timeout>100) $fatal(1,"cache timeout"); end
   if(rsp_error!==error || (!wr && rsp_data!==expected)) $fatal(1,"cache a=%x error=%b data=%x expected=%x",a,rsp_error,rsp_data,expected);
  end
 endtask
 initial begin
  for(i=0;i<64;i=i+1) ram[i]=32'h12340000+i;
  repeat(3) @(negedge clk); rst=0;
  request(0,4,0,0,32'h12340001,0); // allocate
  request(0,12,0,0,32'h12340003,0); // hit
  if(misses!=1 || hits!=1) $fatal(1,"bad hit/miss counters");
  request(1,4,32'hdeadbeef,4'b0101,0,0);
  request(0,4,0,0,32'h12ad00ef,0); // byte merge
  fail_write=1;
  request(1,4,32'hffffffff,4'b1111,0,1);
  fail_write=0;
  request(0,4,0,0,32'h12ad00ef,0); // failed write must preserve cached value
  old_misses=misses;
  request(1,64,32'h87654321,4'b1111,0,0); // no allocate and don't evict current line
  request(0,4,0,0,32'h12ad00ef,0);
  if(misses!=old_misses) $fatal(1,"store miss allocated/evicted");
  request(0,64,0,0,32'h87654321,0); // conflicting tag
  request(0,4,0,0,32'h12ad00ef,0); // displaced line reloaded
  fail_read=1;
  request(0,128,0,0,32'h12340020,1); // error on nonselected beat must poison line
  fail_read=0; old_misses=misses;
  request(0,128,0,0,32'h12340020,0);
  if(misses!=old_misses+1) $fatal(1,"failed refill installed");
  // Invalidate while refill is outstanding; response allowed, line installation forbidden.
  fork
   request(0,192,0,0,32'h12340030,0);
   begin wait(mem_rsp_valid && !mem_rsp_last); @(negedge clk); invalidate=1; @(negedge clk); invalidate=0; end
  join
  old_misses=misses;
  request(0,192,0,0,32'h12340030,0);
  if(misses!=old_misses+1) $fatal(1,"invalidated refill installed stale line");
  @(negedge clk);rst=1;@(negedge clk);rst=0;
  request(0,192,0,0,32'h12340030,0);
  if(misses!=1 || hits!=0) $fatal(1,"reset retained valid data");
  $display("PASS cache rollback/noallocate/conflict/error/invalidate/reset requests=%0d",requests); $finish;
 end
 initial begin #100000; $fatal(1,"cache global timeout"); end
endmodule
