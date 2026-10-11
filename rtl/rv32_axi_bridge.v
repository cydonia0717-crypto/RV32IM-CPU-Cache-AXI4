`timescale 1ns/1ps
// One read burst and one write may be outstanding. AW/W handshakes are independent.
module rv32_axi_bridge(
 input wire clk,rst,
 input wire i_valid,output wire i_ready,input wire [31:0] i_addr,
 output wire i_rsp_valid,output wire [31:0] i_rsp_data,output wire i_rsp_last,i_rsp_error,
 input wire d_valid,output wire d_ready,input wire d_write,
 input wire [31:0] d_addr,d_wdata,input wire [3:0] d_wstrb,
 output wire d_rsp_valid,output wire [31:0] d_rsp_data,output wire d_rsp_last,d_rsp_error,
 output wire [31:0] m_axi_araddr,output wire [7:0] m_axi_arlen,
 output wire [2:0] m_axi_arsize,output wire [1:0] m_axi_arburst,
 output wire [0:0] m_axi_arid,output wire m_axi_arvalid,input wire m_axi_arready,
 input wire [31:0] m_axi_rdata,input wire [1:0] m_axi_rresp,input wire m_axi_rlast,
 input wire [0:0] m_axi_rid,input wire m_axi_rvalid,output wire m_axi_rready,
 output wire [31:0] m_axi_awaddr,output wire [7:0] m_axi_awlen,
 output wire [2:0] m_axi_awsize,output wire [1:0] m_axi_awburst,
 output wire [0:0] m_axi_awid,output wire m_axi_awvalid,input wire m_axi_awready,
 output wire [31:0] m_axi_wdata,output wire [3:0] m_axi_wstrb,
 output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
 input wire [1:0] m_axi_bresp,input wire [0:0] m_axi_bid,input wire m_axi_bvalid,
 output wire m_axi_bready
);
 reg read_active,read_address,owner,last_owner;
 reg [31:0] read_addr,write_addr,write_data;
 reg [3:0] write_strb;
 reg [1:0] beat;
 reg write_active,aw_pending,w_pending;
 wire choose_d=d_valid && !d_write && (!i_valid || !last_owner);
 wire take_read=!read_active && (choose_d || i_valid);
 wire take_write=!write_active && d_valid && d_write;
 assign i_ready=!read_active && !choose_d;
 assign d_ready=d_write ? !write_active : (!read_active && choose_d);
 assign m_axi_araddr=read_addr; assign m_axi_arlen=3; assign m_axi_arsize=2;
 assign m_axi_arburst=1; assign m_axi_arid=owner;
 assign m_axi_arvalid=read_active && read_address;
 assign m_axi_rready=read_active && !read_address;
 wire r_fire=m_axi_rvalid && m_axi_rready;
 wire r_error=|m_axi_rresp || m_axi_rid!=owner || m_axi_rlast!=(beat==3);
 assign i_rsp_valid=r_fire && !owner;
 assign i_rsp_data=m_axi_rdata; assign i_rsp_last=m_axi_rlast; assign i_rsp_error=r_error;
 wire b_fire=m_axi_bvalid && m_axi_bready;
 assign d_rsp_valid=(r_fire && owner) || b_fire;
 assign d_rsp_data=m_axi_rdata;
 assign d_rsp_last=b_fire || m_axi_rlast;
 assign d_rsp_error=b_fire ? (|m_axi_bresp || m_axi_bid!=1'b1) : r_error;
 assign m_axi_awaddr=write_addr; assign m_axi_awlen=0; assign m_axi_awsize=2;
 assign m_axi_awburst=1; assign m_axi_awid=1;
 assign m_axi_awvalid=write_active && aw_pending;
 assign m_axi_wdata=write_data; assign m_axi_wstrb=write_strb;
 assign m_axi_wlast=1; assign m_axi_wvalid=write_active && w_pending;
 assign m_axi_bready=write_active && !aw_pending && !w_pending;
 always @(posedge clk) begin
  if(rst) begin
   read_active<=0; read_address<=0; owner<=0; last_owner<=1; beat<=0;
   read_addr<=0; write_addr<=0; write_data<=0; write_strb<=0;
   write_active<=0; aw_pending<=0; w_pending<=0;
  end else begin
   if(take_read) begin
    read_active<=1; read_address<=1; owner<=choose_d; last_owner<=choose_d;
    read_addr<=choose_d ? d_addr : i_addr; beat<=0;
   end
   if(m_axi_arvalid && m_axi_arready) read_address<=0;
   if(r_fire) begin beat<=beat+1'b1; if(m_axi_rlast) read_active<=0; end
   if(take_write) begin
    write_active<=1; aw_pending<=1; w_pending<=1;
    write_addr<=d_addr; write_data<=d_wdata; write_strb<=d_wstrb;
   end
   if(m_axi_awvalid && m_axi_awready) aw_pending<=0;
   if(m_axi_wvalid && m_axi_wready) w_pending<=0;
   if(b_fire) write_active<=0;
  end
 end
endmodule
