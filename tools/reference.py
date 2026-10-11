#!/usr/bin/env python3
"""Independent RV32IM interpreter and retirement-trace differential checker.
No RTL helper/decoder is imported. RAM is byte-addressed, little-endian.
"""
import argparse,json
from pathlib import Path
MASK=0xffffffff

def u(x): return x&MASK
def s(x,bits=32):
 x&=(1<<bits)-1
 return x-(1<<bits) if x&(1<<(bits-1)) else x

def m_operation(op,a,b):
 if op<4:
  aa=s(a) if op in (1,2) else a
  bb=s(b) if op==1 else b
  p=(aa*bb)&0xffffffffffffffff
  return u(p if op==0 else p>>32)
 signed=op in (4,6)
 aa,bb=(s(a),s(b)) if signed else (a,b)
 if bb==0: return a if op in (6,7) else MASK
 q=abs(aa)//abs(bb)
 if (aa<0)!=(bb<0): q=-q
 return u(aa-q*bb if op in (6,7) else q)

class CPU:
 def __init__(self,image,error_addr=MASK):
  self.mem=bytearray().join(int(x,16).to_bytes(4,'little') for x in Path(image).read_text().split())
  self.r=[0]*32; self.pc=0
  self.csr={0x300:0x1800,0x301:0x40001100,0x305:0,0x341:0,0x342:0,0x343:0,0xf14:0}
  self.error_addr=error_addr
  self.counts={}; self.traps={}; self.writes=0
 def read(self,a,n): return int.from_bytes(self.mem[a:a+n],'little')
 def read_fault(self,a): return a>=len(self.mem) or (self.error_addr!=MASK and a>>4==self.error_addr>>4)
 def write_fault(self,a): return a>=len(self.mem) or (a&~3)==self.error_addr
 def step(self):
  pc=self.pc; fault=self.read_fault(pc)
  insn=0 if fault else self.read(pc,4)
  op=insn&127; rd=insn>>7&31; f=insn>>12&7; r1=insn>>15&31; r2=insn>>20&31; f7=insn>>25
  a,b=self.r[r1],self.r[r2]
  ii=s(insn>>20,12); si=s((insn>>25<<5)|(insn>>7&31),12)
  bi=s(((insn>>31)<<12)|((insn>>7&1)<<11)|((insn>>25&63)<<5)|((insn>>8&15)<<1),13)
  ji=s(((insn>>31)<<20)|((insn>>12&255)<<12)|((insn>>20&1)<<11)|((insn>>21&1023)<<1),21)
  np=u(pc+4); value=0; dest=0; cause=None; tval=0; store=0; addr=0; wdata=0; strobe=0; illegal=False
  mnemonic='illegal'
  if fault: cause,tval=1,pc; mnemonic='fetch_fault'
  elif op==0x37: value=insn&0xfffff000; dest=rd; mnemonic='lui'
  elif op==0x17: value=u(pc+(insn&0xfffff000)); dest=rd; mnemonic='auipc'
  elif op in (0x6f,0x67):
   mnemonic='jal' if op==0x6f else 'jalr'
   value=u(pc+4); dest=rd; np=u(pc+ji) if op==0x6f else u(a+ii)&~1
   if op==0x67 and f!=0: illegal=True
   elif np&3: cause,tval=0,np
  elif op==0x63:
   cond={0:a==b,1:a!=b,4:s(a)<s(b),5:s(a)>=s(b),6:a<b,7:a>=b}
   mnemonic={0:'beq',1:'bne',4:'blt',5:'bge',6:'bltu',7:'bgeu'}.get(f,'illegal')
   if f not in cond: illegal=True
   elif cond[f]:
    np=u(pc+bi)
    if np&3: cause,tval=0,np
  elif op==0x03:
   mnemonic={0:'lb',1:'lh',2:'lw',4:'lbu',5:'lhu'}.get(f,'illegal')
   if f not in (0,1,2,4,5): illegal=True
   else:
    addr=u(a+ii); n=1<<(f&3); dest=rd
    if addr%n: cause,tval=4,addr
    elif self.read_fault(addr): cause,tval=5,addr
    else: value=u(s(self.read(addr,n),n*8)) if f<4 else self.read(addr,n)
  elif op==0x23:
   mnemonic={0:'sb',1:'sh',2:'sw'}.get(f,'illegal')
   if f not in (0,1,2): illegal=True
   else:
    addr=u(a+si); n=1<<f
    if addr%n: cause,tval=6,addr
    elif self.write_fault(addr): cause,tval=7,addr
    else:
     store=1; wdata=u(b<<((addr&3)*8)); strobe=((1<<n)-1)<<(addr&3)
     self.mem[addr:addr+n]=(b&((1<<(8*n))-1)).to_bytes(n,'little'); self.writes+=1
  elif op in (0x13,0x33):
   dest=rd; rhs=u(ii) if op==0x13 else b
   if op==0x33 and f7==1:
    value=m_operation(f,a,b); mnemonic=['mul','mulh','mulhsu','mulhu','div','divu','rem','remu'][f]
   else:
    names=['add','sll','slt','sltu','xor','srl','or','and']
    mnemonic=names[f]+('i' if op==0x13 else '')
    if op==0x13 and f==3: mnemonic='sltiu'
    shift=(insn>>20&31) if op==0x13 else b&31
    if op==0x33 and f7 not in (0,0x20): illegal=True
    if op==0x33 and f7==0x20 and f not in (0,5): illegal=True
    if op==0x13 and f in (1,5) and f7 not in ((0,) if f==1 else (0,0x20)): illegal=True
    if f==0:
     value=u(a-rhs) if op==0x33 and f7==0x20 else u(a+rhs)
     if op==0x33 and f7==0x20: mnemonic='sub'
    elif f==1: value=u(a<<shift)
    elif f==2: value=int(s(a)<s(rhs))
    elif f==3: value=int(a<rhs)
    elif f==4: value=a^rhs
    elif f==5:
     value=u(s(a)>>shift) if f7==0x20 else a>>shift
     if f7==0x20: mnemonic='srai' if op==0x13 else 'sra'
    elif f==6: value=a|rhs
    elif f==7: value=a&rhs
  elif op==0x0f:
   mnemonic='fence.i' if f==1 else 'fence'
   if f not in (0,1): illegal=True
  elif op==0x73:
   if f==0:
    if insn==0x73: cause=11; mnemonic='ecall'
    elif insn==0x100073: cause,tval=3,pc; mnemonic='ebreak'
    elif insn==0x30200073:
     np=self.csr[0x341]; self.csr[0x300]=0x1880|((self.csr[0x300]>>7&1)<<3); mnemonic='mret'
    else: illegal=True
   else:
    c=insn>>20; src=r1 if f&4 else a; mode=f&3; write=(mode==1 or r1!=0)
    mnemonic={1:'csrrw',2:'csrrs',3:'csrrc',5:'csrrwi',6:'csrrsi',7:'csrrci'}.get(f,'illegal')
    if c not in self.csr or f==4 or (write and c in (0x301,0xf14)): illegal=True
    else:
     dest=rd; value=self.csr[c]
     new=src if mode==1 else (value|src if mode==2 else value&~src)
     if write:
      if c==0x300: new=0x1800|(new&0x88)
      if c in (0x305,0x341): new&=~3
      self.csr[c]=u(new)
  else: illegal=True
  if illegal: cause,tval=2,insn
  trap=int(cause is not None)
  if trap:
   dest=0; value=0; store=0; np=self.csr[0x305]
   self.csr[0x341]=pc; self.csr[0x342]=cause; self.csr[0x343]=tval
   self.csr[0x300]=0x1800|((self.csr[0x300]>>3&1)<<7)
   self.traps[str(cause)]=self.traps.get(str(cause),0)+1
  elif dest: self.r[dest]=u(value)
  if dest==0: value=0
  self.r[0]=0; self.pc=np
  self.counts[mnemonic]=self.counts.get(mnemonic,0)+1
  return [pc,insn,np,dest,u(value),trap,0 if cause is None else cause,u(tval),store,addr,wdata,strobe]

def check(image,trace,error_addr=MASK):
 cpu=CPU(image,error_addr); lines=Path(trace).read_text().splitlines()
 for i,line in enumerate(lines):
  got=[int(x,16) for x in line.split()]
  expected=cpu.step()
  indexes=list(range(9))+(list(range(9,12)) if expected[8] else [])
  if expected[5] and expected[6]==1: indexes.remove(1)
  for j in indexes:
   if got[j]!=expected[j]:
    names=['pc','insn','next_pc','rd','data','trap','cause','tval','store','mem_addr','mem_data','mem_strb']
    raise AssertionError(f'instruction {i+1}, PC={expected[0]:08x}, {names[j]} RTL={got[j]:08x}, model={expected[j]:08x}\ntrace: {line}')
 if not lines or not expected[8] or expected[9]!=0xfff0 or expected[10]!=1: raise AssertionError('missing success signature')
 return {'instructions':len(lines),'mnemonics':cpu.counts,'traps':cpu.traps,'stores':cpu.writes}

if __name__=='__main__':
 ap=argparse.ArgumentParser(); ap.add_argument('image'); ap.add_argument('trace'); ap.add_argument('--error-addr',type=lambda x:int(x,0),default=MASK)
 a=ap.parse_args(); print(json.dumps(check(a.image,a.trace,a.error_addr),indent=2))
