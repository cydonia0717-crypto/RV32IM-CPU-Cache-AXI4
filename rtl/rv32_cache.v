`timescale 1ns/1ps
// Blocking direct mapped cache, 4 words/line. Write-through, no write allocate.
module rv32_cache #(parameter LINES=256, parameter INDEX_BITS=8, parameter READ_ONLY=0)(
 input wire clk,rst,invalidate,
 input wire req_valid, output wire req_ready, input wire [31:0] req_addr,
 input wire req_write, input wire [31:0] req_wdata, input wire [3:0] req_wstrb,
 output reg rsp_valid, output reg [31:0] rsp_data, output reg rsp_error,
 output wire mem_valid, input wire mem_ready, output wire mem_write,
 output wire [31:0] mem_addr, mem_wdata, output wire [3:0] mem_wstrb,
 input wire mem_rsp_valid, input wire [31:0] mem_rsp_data,
 input wire mem_rsp_last,mem_rsp_error,
 output reg [31:0] hits,misses
);
 localparam IDLE=0,LOOKUP=1,SEND=2,REFILL=3,WRITE_WAIT=4;
 reg [2:0] state;
 // Cache accepts word data; the core handles byte extraction and alignment.
 wire [1:0] unused_req_offset=req_addr[1:0];
 reg [LINES-1:0] valid;
 reg [27-INDEX_BITS:0] tags [0:LINES-1];
 reg [31:0] data [0:LINES*4-1];
 reg [31:2] addr;
 reg [31:0] wdata,selected;
 reg [3:0] wstrb;
 reg writing,failed,poison;
 reg [1:0] beat;
 wire [INDEX_BITS-1:0] index=addr[INDEX_BITS+3:4];
 wire [27-INDEX_BITS:0] tag=addr[31:INDEX_BITS+4];
 wire [INDEX_BITS+1:0] word_index={index,addr[3:2]};
 wire hit=valid[index] && tags[index]==tag;
 assign req_ready=state==IDLE && !invalidate;
 assign mem_valid=state==SEND;
 assign mem_write=writing;
 assign mem_addr=writing ? {addr[31:2],2'b00} : {addr[31:4],4'b0000};
 assign mem_wdata=wdata;
 assign mem_wstrb=wstrb;
 integer lane;
 always @(posedge clk) begin
  if(rst) begin
   state<=IDLE; rsp_valid<=0; rsp_data<=0; rsp_error<=0; hits<=0; misses<=0;
   addr<=0; wdata<=0; wstrb<=0; writing<=0; beat<=0; failed<=0; selected<=0; poison<=0;
   valid<={LINES{1'b0}};
  end else begin
   rsp_valid<=0;
   if(invalidate) begin
    valid<={LINES{1'b0}};
    if(state!=IDLE) poison<=1;
   end
   case(state)
    IDLE: if(req_valid && req_ready) begin
     addr<=req_addr[31:2]; wdata<=req_wdata; wstrb<=req_wstrb;
     writing<=req_write && !READ_ONLY; poison<=0; state<=LOOKUP;
    end
    LOOKUP: begin
     if(writing) state<=SEND;
     else if(hit && !invalidate && !poison) begin
      rsp_data<=data[word_index]; rsp_error<=0; rsp_valid<=1; hits<=hits+1'b1; state<=IDLE;
     end else begin
      misses<=misses+1'b1; valid[index]<=0; state<=SEND;
     end
    end
    SEND: if(mem_valid && mem_ready) begin
     state<=writing ? WRITE_WAIT : REFILL; beat<=0; failed<=0;
    end
    REFILL: if(mem_rsp_valid) begin
     data[{index,beat}]<=mem_rsp_data;
     if(beat==addr[3:2]) selected<=mem_rsp_data;
     failed<=failed || mem_rsp_error;
     if(mem_rsp_last) begin
      tags[index]<=tag;
      valid[index]<=!failed && !mem_rsp_error && beat==3 && !invalidate && !poison;
      rsp_valid<=1; rsp_error<=failed || mem_rsp_error || beat!=3;
      rsp_data<=beat==addr[3:2] ? mem_rsp_data : selected;
      state<=IDLE;
     end else beat<=beat+1'b1;
    end
    WRITE_WAIT: if(mem_rsp_valid) begin
     rsp_valid<=1; rsp_error<=mem_rsp_error; rsp_data<=0; state<=IDLE;
     // Publish the cached update only after a successful B response.
     if(hit && !mem_rsp_error && !invalidate && !poison)
      for(lane=0;lane<4;lane=lane+1)
       if(wstrb[lane]) data[word_index][lane*8+:8]<=wdata[lane*8+:8];
    end
    default: state<=IDLE;
   endcase
  end
 end
endmodule
