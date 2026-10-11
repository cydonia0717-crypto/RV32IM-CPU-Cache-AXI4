#!/usr/bin/env python3
"""Deterministic assembly stress generator; expected values come only from reference.py."""
import argparse,random
from pathlib import Path
ap=argparse.ArgumentParser(); ap.add_argument('seed',type=int); ap.add_argument('output'); ap.add_argument('--count',type=int,default=600)
a=ap.parse_args(); r=random.Random(a.seed)
out=['.option norvc','.section .text.start','.globl _start','_start:', 'li x31,0x8000']
for i in range(1,30):out.append(f'li x{i},0x{r.getrandbits(32):08x}')
for offset in range(0,256,4):out.append(f'sw x{r.randrange(1,30)},{offset}(x31)')
rr=['add','sub','sll','slt','sltu','xor','srl','sra','or','and','mul','mulh','mulhsu','mulhu','div','divu','rem','remu']
ri=['addi','slti','sltiu','xori','ori','andi']
for i in range(a.count):
 d,s1,s2=[r.randrange(0,30) for _ in range(3)]; kind=r.randrange(8)
 if kind<3:out.append(f'{r.choice(rr)} x{d},x{s1},x{s2}')
 elif kind==3:out.append(f'{r.choice(ri)} x{d},x{s1},{r.randrange(-2048,2048)}')
 elif kind==4:out.append(f'{r.choice(["slli","srli","srai"])} x{d},x{s1},{r.randrange(32)}')
 elif kind==5:
  op=r.choice(['lb','lbu','lh','lhu','lw']); align=4 if op=='lw' else (2 if op in ('lh','lhu') else 1)
  off=r.randrange(256//align)*align
  out.append(f'{op} x{d},{off}(x31)')
  out.append(f'add x{r.randrange(1,30)},x{d},x{s2}')
 elif kind==6:
  op=r.choice(['sb','sh','sw']); align={'sb':1,'sh':2,'sw':4}[op]
  off=r.randrange(256//align)*align
  out.append(f'{op} x{s1},{off}(x31)')
 else:
  out.extend([f'{r.choice(["beq","bne","blt","bge","bltu","bgeu"])} x{s1},x{s2},label_{i}',f'addi x{d},x{d},1',f'label_{i}:'])
# exercises repeated branch flushes and data conflicts
out+=['li x30,12','loop:','lw x1,0(x31)','addi x1,x1,1','sw x1,0(x31)','addi x30,x30,-1','bne x30,zero,loop','li x1,0x9000','lw x2,0(x1)','lw x3,0(x31)','li x1,0xfff0','li x2,1','sw x2,0(x1)','stop: j stop']
Path(a.output).write_text('\n'.join(out)+'\n')
