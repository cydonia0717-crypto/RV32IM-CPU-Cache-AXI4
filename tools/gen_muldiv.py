#!/usr/bin/env python3
import random,sys
from pathlib import Path
from reference import m_operation
r=random.Random(20261011)
edge=[0,1,2,0x7fffffff,0x80000000,0x80000001,0xfffffffe,0xffffffff]
v=[]
for op in range(8):
 for a in edge:
  for b in edge:v.append((op,a,b,m_operation(op,a,b)))
 for _ in range(256):
  a,b=r.getrandbits(32),r.getrandbits(32);v.append((op,a,b,m_operation(op,a,b)))
Path(sys.argv[1]).write_text(''.join(f'{op:x}{a:08x}{b:08x}{x:08x}\n' for op,a,b,x in v))
print(len(v))
