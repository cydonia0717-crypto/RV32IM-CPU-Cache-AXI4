`timescale 1ns/1ps
module tb_soc;
 `include "soc_signals.vh"
 `include "soc_instance.vh"
 always #5 clk=~clk;
 reg [31:0] memory[0:16383];
 reg read_active,aw_seen,w_seen;
 reg [31:0] read_addr,aw_addr,w_data;
 reg [3:0] w_strb;
 reg read_id,aw_id;
 reg [7:0] read_len,read_beat;
 reg [31:0] rng;
 reg [31:0] error_addr;
 integer seed,max_cycles,fd,n,lane,write_order;
 reg long_stall;
 integer ar_count,aw_count,r_count,b_count,w_before_aw,aw_before_w;
 reg [1023:0] image_path,trace_path;
 reg [31:0] prev_araddr,prev_awaddr,prev_wdata;
 reg [3:0] prev_wstrb;
 reg ar_stalled,aw_stalled,w_stalled;
 reg [31:0] hold_rdata; reg [1:0] hold_rresp; reg hold_rlast,hold_rid,r_stalled;
 reg [1:0] hold_bresp; reg hold_bid,b_stalled;
 initial begin
  seed=1; write_order=0; long_stall=$test$plusargs("long_stall"); max_cycles=2000000; error_addr=32'hffffffff;
  if($value$plusargs("seed=%d",seed)) begin end
  if($value$plusargs("write_order=%d",write_order)) begin end
  if($value$plusargs("max_cycles=%d",max_cycles)) begin end
  if($value$plusargs("error_addr=%h",error_addr)) begin end
  if(!$value$plusargs("image=%s",image_path)) $fatal(1,"missing image");
  if(!$value$plusargs("trace=%s",trace_path)) $fatal(1,"missing trace");
  for(n=0;n<16384;n=n+1) memory[n]=0;
  $readmemh(image_path,memory);
  fd=$fopen(trace_path,"w"); if(!fd) $fatal(1,"trace open failed");
  rng=seed==0 ? 32'd1 : seed;
  read_active=0; aw_seen=0; w_seen=0;
  read_addr=0; aw_addr=0; w_data=0; w_strb=0; read_id=0; aw_id=0; read_len=0; read_beat=0;
  m_axi_arready=0; m_axi_awready=0; m_axi_wready=0;
  m_axi_rvalid=0; m_axi_rdata=0; m_axi_rresp=0; m_axi_rlast=0; m_axi_rid=0;
  m_axi_bvalid=0; m_axi_bresp=0; m_axi_bid=0;
  ar_stalled=0; aw_stalled=0; w_stalled=0; r_stalled=0; b_stalled=0;
  ar_count=0; aw_count=0; r_count=0; b_count=0; w_before_aw=0; aw_before_w=0;
  if($test$plusargs("vcd")) begin $dumpfile("build/soc.vcd"); $dumpvars(0,tb_soc); end
  repeat(5) @(negedge clk); rst=0;
 end
 // Slave models completely independent AW and W acceptance.
 always @(negedge clk) begin
  if(!rst) begin
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   m_axi_arready=!read_active && rng[0] && (!long_stall || cycles[6:0]>64);
   m_axi_awready=!aw_seen && !m_axi_bvalid && rng[3] && (write_order!=1 || w_seen) && (!long_stall || cycles[6:0]>64);
   m_axi_wready=!w_seen && !m_axi_bvalid && rng[7] && (write_order!=2 || aw_seen) && (!long_stall || cycles[6:0]>64);
  end
 end
 always @(posedge clk) if(!rst) begin
  if(ar_stalled && (!m_axi_arvalid || m_axi_araddr!==prev_araddr)) $fatal(1,"AR unstable");
  if(aw_stalled && (!m_axi_awvalid || m_axi_awaddr!==prev_awaddr)) $fatal(1,"AW unstable");
  if(w_stalled && (!m_axi_wvalid || m_axi_wdata!==prev_wdata || m_axi_wstrb!==prev_wstrb || !m_axi_wlast)) $fatal(1,"W unstable");
  if(r_stalled && (!m_axi_rvalid || {m_axi_rdata,m_axi_rresp,m_axi_rlast,m_axi_rid}!=={hold_rdata,hold_rresp,hold_rlast,hold_rid})) $fatal(1,"slave R unstable");
  if(b_stalled && (!m_axi_bvalid || {m_axi_bresp,m_axi_bid}!=={hold_bresp,hold_bid})) $fatal(1,"slave B unstable");
  ar_stalled<=m_axi_arvalid && !m_axi_arready; prev_araddr<=m_axi_araddr;
  aw_stalled<=m_axi_awvalid && !m_axi_awready; prev_awaddr<=m_axi_awaddr;
  w_stalled<=m_axi_wvalid && !m_axi_wready; prev_wdata<=m_axi_wdata; prev_wstrb<=m_axi_wstrb;
  r_stalled<=m_axi_rvalid && !m_axi_rready; hold_rdata<=m_axi_rdata; hold_rresp<=m_axi_rresp; hold_rlast<=m_axi_rlast; hold_rid<=m_axi_rid;
  b_stalled<=m_axi_bvalid && !m_axi_bready; hold_bresp<=m_axi_bresp; hold_bid<=m_axi_bid;
  if(m_axi_arvalid && m_axi_arready) begin
   if(m_axi_arlen!=3 || m_axi_arsize!=2 || m_axi_arburst!=1 || m_axi_araddr[3:0]!=0) $fatal(1,"bad read burst");
   if({1'b0,m_axi_araddr[11:0]}+13'd16>13'd4096) $fatal(1,"4KB crossing");
   read_active<=1; read_addr<=m_axi_araddr; read_len<=m_axi_arlen; read_beat<=0; read_id<=m_axi_arid; ar_count<=ar_count+1;
  end
  if(read_active && !m_axi_rvalid && rng[11] && (!long_stall || cycles[6:0]>64)) begin
   m_axi_rvalid<=1; m_axi_rid<=read_id; m_axi_rlast<=read_beat==read_len;
   m_axi_rresp<=read_addr>=65536 || read_addr==error_addr ? 2'b10 : 2'b00;
   m_axi_rdata<=read_addr<65536 ? memory[read_addr>>2] : 32'd0;
  end
  if(m_axi_rvalid && m_axi_rready) begin
   m_axi_rvalid<=0; r_count<=r_count+1;
   if(m_axi_rlast) read_active<=0;
   else begin read_addr<=read_addr+4; read_beat<=read_beat+1'b1; end
  end
  if(m_axi_awvalid && m_axi_awready) begin
   if(m_axi_awlen!=0 || m_axi_awsize!=2 || m_axi_awburst!=1 || |m_axi_awaddr[1:0]) $fatal(1,"bad write address");
   aw_seen<=1; aw_addr<=m_axi_awaddr; aw_id<=m_axi_awid; aw_count<=aw_count+1;
   if(!w_seen) aw_before_w<=aw_before_w+1;
  end
  if(m_axi_wvalid && m_axi_wready) begin
   if(!m_axi_wlast) $fatal(1,"missing WLAST");
   w_seen<=1; w_data<=m_axi_wdata; w_strb<=m_axi_wstrb;
   if(!aw_seen) w_before_aw<=w_before_aw+1;
  end
  if(aw_seen && w_seen && !m_axi_bvalid && rng[15] && (!long_stall || cycles[6:0]>64)) begin
   m_axi_bvalid<=1; m_axi_bid<=aw_id;
   m_axi_bresp<=aw_addr>=65536 || aw_addr==error_addr ? 2'b10 : 2'b00;
   if(aw_addr<65536 && aw_addr!=error_addr)
    for(lane=0;lane<4;lane=lane+1) if(w_strb[lane]) memory[aw_addr>>2][lane*8+:8]<=w_data[lane*8+:8];
  end
  if(m_axi_bvalid && m_axi_bready) begin m_axi_bvalid<=0; aw_seen<=0; w_seen<=0; b_count<=b_count+1; end
  if(trace_valid) begin
   $fwrite(fd,"%08x %08x %08x %02x %08x %01x %08x %08x %01x %08x %08x %01x\n",
    trace_pc,trace_insn,trace_next_pc,trace_rd,trace_data,trace_trap,trace_cause,trace_tval,
    trace_store,trace_mem_addr,trace_mem_data,trace_mem_strb);
   if(trace_store && trace_mem_addr==32'hfff0) begin
    if(trace_mem_data!=1) $fatal(1,"program reported failure %x",trace_mem_data);
    $display("PASS cycles=%0d retired=%0d i_hit=%0d i_miss=%0d d_hit=%0d d_miss=%0d load_stall=%0d flush=%0d AR=%0d AW=%0d R=%0d B=%0d Wfirst=%0d AWfirst=%0d",
     cycles,retired,i_hits,i_misses,d_hits,d_misses,load_stalls,branch_flushes,ar_count,aw_count,r_count,b_count,w_before_aw,aw_before_w);
    $fclose(fd); $finish;
   end
  end
  if(cycles>max_cycles) $fatal(1,"timeout pc=%x",dut.u_core.fetch_pc);
  if(dut.u_core.regs[0]!==0) $fatal(1,"x0 changed");
 end
endmodule
