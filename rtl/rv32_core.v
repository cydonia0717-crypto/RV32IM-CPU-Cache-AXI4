`timescale 1ns/1ps
// Five valid-bit stages: IF response buffer / ID / EX / MEM / WB.
// In-order retirement; blocking memory; forwarding and load-use interlock.
module rv32_core #(parameter RESET_PC=32'h0)(
 input wire clk,rst,
 output wire i_valid,input wire i_ready,output wire [31:0] i_addr,
 input wire i_rsp_valid,input wire [31:0] i_rsp_data,input wire i_rsp_error,
 output wire d_valid,input wire d_ready,output wire [31:0] d_addr,
 output wire d_write,output wire [31:0] d_wdata,output wire [3:0] d_wstrb,
 input wire d_rsp_valid,input wire [31:0] d_rsp_data,input wire d_rsp_error,
 output wire i_invalidate,
 output reg trace_valid,output reg [31:0] trace_pc,trace_insn,trace_next_pc,
 output reg [4:0] trace_rd,output reg [31:0] trace_data,
 output reg trace_trap,output reg [31:0] trace_cause,trace_tval,
 output reg trace_store,output reg [31:0] trace_mem_addr,trace_mem_data,
 output reg [3:0] trace_mem_strb,
 output reg [31:0] cycles,retired,load_stalls,branch_flushes
);
 reg [31:0] regs [0:31];
 reg [31:0] fetch_pc,pending_pc;
 reg fetch_pending,fetch_drop;
 reg f_valid,f_error;
 reg [31:0] f_pc,f_insn;
 reg id_valid,id_error;
 reg [31:0] id_pc,id_insn;
 reg ex_valid,ex_fetch_error;
 reg [31:0] ex_pc,ex_insn,ex_a,ex_b;
 reg mem_valid,mem_sent,mem_exc,mem_load,mem_store,mem_regwrite;
 reg [31:0] mem_pc,mem_insn,mem_result,mem_addr,mem_store_data,mem_next_pc,mem_cause,mem_tval;
 reg [3:0] mem_strb;
 reg [4:0] mem_rd;
 reg [2:0] mem_funct3;
 reg mem_csr_write,mem_mret;
 reg [11:0] mem_csr_addr;
 reg [31:0] mem_csr_value;
 reg wb_valid,wb_exc,wb_regwrite,wb_store;
 reg [31:0] wb_pc,wb_insn,wb_result,wb_next_pc,wb_cause,wb_tval,wb_addr,wb_store_data;
 reg [3:0] wb_strb;
 reg [4:0] wb_rd;
 reg [31:0] csr_mstatus,csr_mtvec,csr_mepc,csr_mcause,csr_mtval;
 wire [6:0] opcode=ex_insn[6:0];
 wire [2:0] funct3=ex_insn[14:12];
 wire [6:0] funct7=ex_insn[31:25];
 wire [4:0] rs1=ex_insn[19:15], rs2=ex_insn[24:20], rd=ex_insn[11:7];
 wire [31:0] imm_i={{20{ex_insn[31]}},ex_insn[31:20]};
 wire [31:0] imm_s={{20{ex_insn[31]}},ex_insn[31:25],ex_insn[11:7]};
 wire [31:0] imm_b={{19{ex_insn[31]}},ex_insn[31],ex_insn[7],ex_insn[30:25],ex_insn[11:8],1'b0};
 wire [31:0] imm_u={ex_insn[31:12],12'd0};
 wire [31:0] imm_j={{11{ex_insn[31]}},ex_insn[31],ex_insn[19:12],ex_insn[20],ex_insn[30:21],1'b0};
 reg [31:0] operand_a,operand_b;
 wire [31:0] shifted_load=d_rsp_data >> (mem_addr[1:0]*8);
 reg [31:0] load_value;
 always @* begin
  case(mem_funct3)
   0: load_value={{24{shifted_load[7]}},shifted_load[7:0]};
   1: load_value={{16{shifted_load[15]}},shifted_load[15:0]};
   2: load_value=shifted_load;
   4: load_value={24'd0,shifted_load[7:0]};
   5: load_value={16'd0,shifted_load[15:0]};
   default: load_value=0;
  endcase
 end
 wire mem_done=mem_valid && (!(mem_load || mem_store) || mem_exc || (mem_sent && d_rsp_valid));
 wire mem_bus_error=mem_done && (mem_load || mem_store) && !mem_exc && d_rsp_error;
 wire mem_trap=mem_done && (mem_exc || mem_bus_error);
 wire [31:0] mem_value=mem_load ? load_value : mem_result;
 wire [31:0] trap_cause=mem_bus_error ? (mem_store ? 32'd7 : 32'd5) : mem_cause;
 wire [31:0] trap_tval=mem_bus_error ? mem_addr : mem_tval;
 wire mem_ready=!mem_valid || mem_done;
 wire system_op=opcode==7'h73 || opcode==7'h0f;
 wire system_ready=!mem_valid && !wb_valid;
 always @* begin
  operand_a=ex_a; operand_b=ex_b;
  if(wb_valid && wb_regwrite && !wb_exc && wb_rd!=0) begin
   if(wb_rd==rs1) operand_a=wb_result;
   if(wb_rd==rs2) operand_b=wb_result;
  end
  if(mem_valid && mem_regwrite && !mem_exc && !mem_bus_error && mem_rd!=0 && (!mem_load || mem_done)) begin
   if(mem_rd==rs1) operand_a=mem_value;
   if(mem_rd==rs2) operand_b=mem_value;
  end
 end
 reg [31:0] result,address,store_data,next_pc,cause,tval,csr_old,csr_new;
 reg [3:0] strb;
 reg regwrite,is_load,is_store,illegal,exception,branch_taken,is_m,is_mret,is_fence_i,csr_write,csr_legal;
 wire [11:0] csr_addr=ex_insn[31:20];
 reg [31:0] csr_source;
 always @* begin
  csr_legal=1;
  case(csr_addr)
   12'h300: csr_old=csr_mstatus;
   12'h301: csr_old=32'h40001100; // RV32 I+M
   12'h305: csr_old=csr_mtvec;
   12'h341: csr_old=csr_mepc;
   12'h342: csr_old=csr_mcause;
   12'h343: csr_old=csr_mtval;
   12'hf14: csr_old=0;
   default: begin csr_old=0; csr_legal=0; end
  endcase
  csr_source=funct3[2] ? {27'd0,rs1} : operand_a;
  csr_new=csr_old; csr_write=0;
  case(funct3[1:0])
   1: begin csr_new=csr_source; csr_write=1; end
   2: begin csr_new=csr_old | csr_source; csr_write=rs1!=0; end
   3: begin csr_new=csr_old & ~csr_source; csr_write=rs1!=0; end
   default: begin end
  endcase
  result=0; address=0; store_data=0; next_pc=ex_pc+4; strb=0;
  regwrite=0; is_load=0; is_store=0; illegal=0; exception=0;
  branch_taken=0; is_m=0; is_mret=0; is_fence_i=0; cause=0; tval=0;
  case(opcode)
   7'h37: begin result=imm_u; regwrite=1; end
   7'h17: begin result=ex_pc+imm_u; regwrite=1; end
   7'h6f: begin result=ex_pc+4; regwrite=1; branch_taken=1; next_pc=ex_pc+imm_j; end
   7'h67: begin
    result=ex_pc+4; regwrite=1; branch_taken=1; next_pc=(operand_a+imm_i)&32'hfffffffe;
    if(funct3!=0) illegal=1;
   end
   7'h63: begin
    case(funct3)
     0: branch_taken=operand_a==operand_b;
     1: branch_taken=operand_a!=operand_b;
     4: branch_taken=$signed(operand_a)<$signed(operand_b);
     5: branch_taken=$signed(operand_a)>=$signed(operand_b);
     6: branch_taken=operand_a<operand_b;
     7: branch_taken=operand_a>=operand_b;
     default: illegal=1;
    endcase
    if(branch_taken) next_pc=ex_pc+imm_b;
   end
   7'h03: begin
    is_load=1; regwrite=1; address=operand_a+imm_i;
    if(!(funct3==0 || funct3==1 || funct3==2 || funct3==4 || funct3==5)) illegal=1;
    else if((funct3[1:0]==1 && address[0]) || (funct3==2 && |address[1:0])) begin
     exception=1; cause=4; tval=address;
    end
   end
   7'h23: begin
    is_store=1; address=operand_a+imm_s; store_data=operand_b << (address[1:0]*8);
    case(funct3)
     0: strb=4'b0001 << address[1:0];
     1: strb=4'b0011 << address[1:0];
     2: strb=4'b1111;
     default: illegal=1;
    endcase
    if((funct3==1 && address[0]) || (funct3==2 && |address[1:0])) begin
     exception=1; cause=6; tval=address;
    end
   end
   7'h13: begin
    regwrite=1;
    case(funct3)
     0: result=operand_a+imm_i;
     2: result={31'd0,$signed(operand_a)<$signed(imm_i)};
     3: result={31'd0,operand_a<imm_i};
     4: result=operand_a^imm_i;
     6: result=operand_a|imm_i;
     7: result=operand_a&imm_i;
     1: begin result=operand_a<<ex_insn[24:20]; if(funct7!=0) illegal=1; end
     5: begin
      if(funct7==7'h20) result=$signed(operand_a) >>> ex_insn[24:20];
      else result=operand_a >> ex_insn[24:20];
      if(funct7!=0 && funct7!=7'h20) illegal=1;
     end
     default: illegal=1;
    endcase
   end
   7'h33: begin
    regwrite=1;
    if(funct7==1) is_m=1;
    else begin
     if(funct7!=0 && !(funct7==7'h20 && (funct3==0 || funct3==5))) illegal=1;
     case(funct3)
      0: result=funct7==7'h20 ? operand_a-operand_b : operand_a+operand_b;
      1: result=operand_a << operand_b[4:0];
      2: result={31'd0,$signed(operand_a)<$signed(operand_b)};
      3: result={31'd0,operand_a<operand_b};
      4: result=operand_a^operand_b;
      5: begin
       if(funct7==7'h20) result=$signed(operand_a) >>> operand_b[4:0];
       else result=operand_a >> operand_b[4:0];
      end
      6: result=operand_a|operand_b;
      7: result=operand_a&operand_b;
     endcase
    end
   end
   7'h0f: begin
    if(funct3==1) is_fence_i=1;
    else if(funct3!=0) illegal=1;
   end
   7'h73: begin
    if(funct3==0) begin
     case(ex_insn)
      32'h00000073: begin exception=1; cause=11; end
      32'h00100073: begin exception=1; cause=3; tval=ex_pc; end
      32'h30200073: begin is_mret=1; next_pc=csr_mepc; end
      default: illegal=1;
     endcase
    end else begin
     result=csr_old; regwrite=1;
     if(!csr_legal || funct3==4 || (csr_write && (csr_addr==12'h301 || csr_addr==12'hf14))) illegal=1;
    end
   end
   default: illegal=1;
  endcase
  if(branch_taken && |next_pc[1:0]) begin exception=1; cause=0; tval=next_pc; end
  if(illegal) begin exception=1; cause=2; tval=ex_insn; end
  if(ex_fetch_error) begin exception=1; cause=1; tval=ex_pc; end
 end
 reg md_started,md_ready;
 reg [31:0] md_saved;
 wire md_busy,md_done;
 wire [31:0] md_result;
 wire md_start=ex_valid && is_m && !exception && !md_started && !md_busy && !mem_trap && mem_ready;
 rv32_muldiv u_muldiv(clk,rst,md_start,funct3,operand_a,operand_b,md_busy,md_done,md_result);
 wire ex_done=ex_valid && mem_ready && !mem_trap && (!system_op || system_ready) &&
                        (!is_m || exception || md_ready);
 wire ex_redirect=ex_done && !exception && (branch_taken || is_mret || is_fence_i);
 wire redirect=mem_trap || ex_redirect;
 wire [31:0] redirect_pc=mem_trap ? csr_mtvec : next_pc;
 assign i_invalidate=ex_done && is_fence_i && !exception;
 assign i_valid=!fetch_pending && !f_valid && !redirect;
 assign i_addr=fetch_pc;
 assign d_valid=mem_valid && (mem_load || mem_store) && !mem_exc && !mem_sent;
 assign d_addr=mem_addr; assign d_write=mem_store;
 assign d_wdata=mem_store_data; assign d_wstrb=mem_strb;
 wire [4:0] id_rs1=id_insn[19:15],id_rs2=id_insn[24:20];
 wire [6:0] id_opcode=id_insn[6:0];
 wire id_use1=!(id_opcode==7'h37 || id_opcode==7'h17 || id_opcode==7'h6f || id_opcode==7'h0f) &&
              !(id_opcode==7'h73 && (id_insn[14] || id_insn[14:12]==0));
 wire id_use2=id_opcode==7'h33 || id_opcode==7'h23 || id_opcode==7'h63;
 wire load_hazard=id_valid && ex_valid && is_load && rd!=0 &&
                  ((id_use1 && id_rs1==rd) || (id_use2 && id_rs2==rd));
 wire id_advance=id_valid && (!ex_valid || ex_done) && !load_hazard && !redirect;
 wire f_advance=f_valid && (!id_valid || id_advance) && !redirect;
 function [31:0] read_reg;
  input [4:0] r;
  begin
   if(r==0) read_reg=0;
   else if(wb_valid && wb_regwrite && !wb_exc && wb_rd==r) read_reg=wb_result;
   else read_reg=regs[r];
  end
 endfunction
 integer j;
 always @(posedge clk) begin
  if(rst) begin
   fetch_pc<=RESET_PC; pending_pc<=0; fetch_pending<=0; fetch_drop<=0;
   f_valid<=0; id_valid<=0; ex_valid<=0; mem_valid<=0; wb_valid<=0;
   f_pc<=0; f_insn<=0; f_error<=0; id_pc<=0; id_insn<=0; id_error<=0;
   ex_pc<=0; ex_insn<=0; ex_a<=0; ex_b<=0; ex_fetch_error<=0;
   mem_sent<=0; mem_exc<=0; mem_load<=0; mem_store<=0; mem_regwrite<=0;
   mem_pc<=0; mem_insn<=0; mem_result<=0; mem_addr<=0; mem_store_data<=0;
   mem_next_pc<=0; mem_cause<=0; mem_tval<=0; mem_strb<=0; mem_rd<=0; mem_funct3<=0;
   mem_csr_write<=0; mem_mret<=0; mem_csr_addr<=0; mem_csr_value<=0;
   wb_exc<=0; wb_regwrite<=0; wb_store<=0; wb_pc<=0; wb_insn<=0; wb_result<=0;
   wb_next_pc<=0; wb_cause<=0; wb_tval<=0; wb_addr<=0; wb_store_data<=0; wb_strb<=0; wb_rd<=0;
   csr_mstatus<=32'h1800; csr_mtvec<=0; csr_mepc<=0; csr_mcause<=0; csr_mtval<=0;
   md_started<=0; md_ready<=0; md_saved<=0;
   trace_valid<=0; trace_pc<=0; trace_insn<=0; trace_next_pc<=0; trace_rd<=0; trace_data<=0;
   trace_trap<=0; trace_cause<=0; trace_tval<=0; trace_store<=0;
   trace_mem_addr<=0; trace_mem_data<=0; trace_mem_strb<=0;
   cycles<=0; retired<=0; load_stalls<=0; branch_flushes<=0;
   for(j=0;j<32;j=j+1) regs[j]<=0;
  end else begin
   cycles<=cycles+1'b1;
   if(load_hazard) load_stalls<=load_stalls+1'b1;
   if(ex_redirect) branch_flushes<=branch_flushes+1'b1;
   trace_valid<=wb_valid;
   if(wb_valid) begin
    trace_pc<=wb_pc; trace_insn<=wb_insn; trace_next_pc<=wb_next_pc;
    trace_rd<=wb_regwrite && !wb_exc ? wb_rd : 5'd0;
    trace_data<=wb_regwrite && wb_rd!=0 && !wb_exc ? wb_result : 32'd0;
    trace_trap<=wb_exc; trace_cause<=wb_exc ? wb_cause : 32'd0; trace_tval<=wb_exc ? wb_tval : 32'd0;
    trace_store<=wb_store && !wb_exc; trace_mem_addr<=wb_addr;
    trace_mem_data<=wb_store_data; trace_mem_strb<=wb_strb;
    if(!wb_exc) begin
     retired<=retired+1'b1;
     if(wb_regwrite && wb_rd!=0) regs[wb_rd]<=wb_result;
    end
   end
   wb_valid<=mem_done;
   if(mem_done) begin
    wb_pc<=mem_pc; wb_insn<=mem_insn; wb_result<=mem_value;
    wb_rd<=mem_rd; wb_regwrite<=mem_regwrite; wb_exc<=mem_trap;
    wb_next_pc<=mem_trap ? csr_mtvec : mem_next_pc;
    wb_cause<=trap_cause; wb_tval<=trap_tval; wb_store<=mem_store;
    wb_addr<=mem_addr; wb_store_data<=mem_store_data; wb_strb<=mem_strb;
    mem_valid<=0; mem_sent<=0;
    if(mem_trap) begin
     csr_mepc<=mem_pc; csr_mcause<=trap_cause; csr_mtval<=trap_tval;
     csr_mstatus<={19'd0,2'b11,3'd0,csr_mstatus[3],3'd0,1'b0,3'd0};
    end else begin
     if(mem_csr_write) case(mem_csr_addr)
      12'h300: csr_mstatus<=32'h1800 | (mem_csr_value & 32'h88);
      12'h305: csr_mtvec<=mem_csr_value & 32'hfffffffc;
      12'h341: csr_mepc<=mem_csr_value & 32'hfffffffc;
      12'h342: csr_mcause<=mem_csr_value;
      12'h343: csr_mtval<=mem_csr_value;
      default: begin end
     endcase
     if(mem_mret) csr_mstatus<=32'h1880 | {28'd0,csr_mstatus[7],3'd0};
    end
   end
   if(d_valid && d_ready) mem_sent<=1;
   if(md_start) md_started<=1;
   if(md_done) begin md_ready<=1; md_saved<=md_result; end
   if(ex_done) begin
    mem_valid<=1; mem_sent<=0; mem_pc<=ex_pc; mem_insn<=ex_insn;
    mem_result<=is_m ? md_saved : result; mem_addr<=address;
    mem_store_data<=store_data; mem_strb<=strb; mem_funct3<=funct3;
    mem_rd<=rd; mem_regwrite<=regwrite; mem_load<=is_load; mem_store<=is_store;
    mem_exc<=exception; mem_cause<=cause; mem_tval<=tval; mem_next_pc<=next_pc;
    mem_csr_write<=opcode==7'h73 && funct3!=0 && csr_write;
    mem_csr_addr<=csr_addr; mem_csr_value<=csr_new; mem_mret<=is_mret;
    ex_valid<=0; md_started<=0; md_ready<=0;
   end
   // Latch forwarded EX operands during stalls before the producer leaves MEM/WB.
   if(ex_valid && !ex_done) begin ex_a<=operand_a; ex_b<=operand_b; end
   if(id_advance) begin
    ex_valid<=1; ex_pc<=id_pc; ex_insn<=id_insn; ex_fetch_error<=id_error;
    ex_a<=read_reg(id_rs1); ex_b<=read_reg(id_rs2); id_valid<=0;
   end
   if(f_advance) begin
    id_valid<=1; id_pc<=f_pc; id_insn<=f_insn; id_error<=f_error; f_valid<=0;
   end
   if(i_valid && i_ready) begin
    fetch_pending<=1; pending_pc<=fetch_pc; fetch_pc<=fetch_pc+4; fetch_drop<=0;
   end
   if(i_rsp_valid && fetch_pending) begin
    fetch_pending<=0;
    if(!fetch_drop && !redirect) begin f_valid<=1; f_pc<=pending_pc; f_insn<=i_rsp_data; f_error<=i_rsp_error; end
   end
   if(redirect) begin
    fetch_pc<=redirect_pc; f_valid<=0; id_valid<=0;
    if(fetch_pending && !i_rsp_valid) fetch_drop<=1;
    if(mem_trap) begin ex_valid<=0; md_started<=0; md_ready<=0; end
   end
  end
 end
endmodule
