.option norvc
.section .text.start
.globl _start
_start:
 li sp,0xf000
 la t0,handler
 csrw mtvec,t0
 # ALU dependencies, x0 writes, both forwarding operands
 li s0,0x4000
 li t0,0x80000001
 li t1,-3
 add t2,t0,t1
 sub t3,t2,t0
 xor t4,t3,t2
 or t5,t4,t1
 and t6,t5,t0
 slt a0,t1,t0
 sltu a1,t1,t0
 sll a2,t0,t1
 srl a3,t0,t1
 sra a4,t0,t1
 addi x0,t0,3
 slti a5,t1,4
 sltiu a6,t0,-1
 xori a7,t0,-1
 ori a0,t0,31
 andi a1,t1,127
 slli a2,t0,31
 srli a3,t0,31
 srai a4,t0,31
 auipc a5,0
 # all M ops, result dependent instructions
 mul a0,t0,t1
 add a1,a0,t1
 mulh a2,t0,t1
 mulhsu a3,t0,t1
 mulhu a4,t0,t1
 div a5,t0,t1
 rem a6,t0,t1
 divu a7,t0,t1
 remu a0,t0,t1
 li t0,0x80000000
 li t1,-1
 div a1,t0,t1
 rem a2,t0,t1
 div a3,t0,zero
 rem a4,t0,zero
 divu a5,t0,zero
 remu a6,t0,zero
 # stores, load-use and byte lanes, WB data and long stalls
 sw t0,0(s0)
 lw t2,0(s0)
 add t3,t2,t2
 sb t1,1(s0)
 sh t1,2(s0)
 lb t4,1(s0)
 lbu t5,1(s0)
 lh t6,2(s0)
 lhu a0,2(s0)
 lw a1,0(s0)
 sw a1,12(s0)
 lw a2,12(s0)
 add a3,a2,a1
 # conflict replacement and 4KB line boundary
 li s1,0x5000
 sw a3,0(s1)
 lw a4,0(s1)
 lw a5,0(s0)
 li s2,0x4ffc
 sw a5,0(s2)
 lw a6,0(s2)
 # branch forwarding, loops, all branch conditions
 li t0,7
1: addi t0,t0,-1
 bne t0,zero,1b
 beq t0,zero,2f
 sw t1,4(s0)
2: blt t1,zero,3f
 sw t1,4(s0)
3: bge zero,t1,4f
 sw t1,4(s0)
4: bltu zero,t1,5f
 sw t1,4(s0)
5: bgeu t1,zero,6f
 sw t1,4(s0)
6: jal ra,subroutine
 la t0,7f
 jalr ra,0(t0)
7: fence
 fence.i
 # CSR set/clear, immediate variants and no-write reads
 li t0,0x88
 csrrw t1,mstatus,t0
 csrrs t2,mstatus,zero
 csrrc t3,mstatus,t0
 csrrwi t4,mtval,7
 csrrsi t5,mtval,8
 csrrci t6,mtval,3
 csrr a0,misa
 csrr a1,mhartid
 # precise exceptions: illegal, ecall, ebreak, nonaligned load/store/jump
 .word 0xffffffff
 ecall
 ebreak
 lw a0,1(s0)
 sh a1,1(s0)
 jalr zero,2(zero)
 # illegal encodings + unsupported CSR + read-only CSR write
 .word 0x02001013
 .word 0x40001033
 csrr t0,0x777
 csrw misa,t0
 # accesses beyond implemented physical memory: load/store faults
 li t0,0x10000
 lw t1,0(t0)
 sw t1,0(t0)
 # instruction fetch access fault, handler installs known return address
 la s3,after_fetch_fault
 jalr zero,0(t0)
after_fetch_fault:
 # self modifying code must be refetched after FENCE.I
 la t0,patched
 jalr ra,0(t0)
 li t1,0x02a00513
 sw t1,0(t0)
 fence.i
 jalr ra,0(t0)
 li t0,0xfff0
 li t1,1
 sw t1,0(t0)
9: j 9b
subroutine:
 addi s4,s4,1
 ret
patched:
 addi a0,zero,1
 ret
.balign 16
handler:
 csrr t4,mcause
 csrr t5,mtval
 csrr t6,mepc
 li t3,1
 beq t4,t3,fetch_return
 addi t6,t6,4
 csrw mepc,t6
 mret
fetch_return:
 csrw mepc,s3
 mret
