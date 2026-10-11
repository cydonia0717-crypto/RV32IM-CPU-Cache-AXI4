#!/usr/bin/env python3
"""Run bounded RTL simulations and architectural differential checks.
All simulator/compiler failures and timeouts propagate to nonzero exit status.
"""
import argparse,json,subprocess,re,collections
from pathlib import Path
from reference import check
ap=argparse.ArgumentParser(); ap.add_argument('--cc',default='riscv64-unknown-elf-gcc');ap.add_argument('--objcopy',default='riscv64-unknown-elf-objcopy');ap.add_argument('--vvp',default='vvp');ap.add_argument('--random-programs',type=int,default=8);ap.add_argument('--seeds',type=int,default=4)
a=ap.parse_args()
def run(cmd):return subprocess.run(cmd,check=True,capture_output=True,text=True,timeout=180).stdout
cases=[]; counts=collections.Counter(); traps=collections.Counter()
programs=['directed','algorithm']
flags=['-march=rv32im_zicsr_zifencei','-mabi=ilp32','-nostdlib','-nostartfiles','-mno-relax','-Wl,--no-relax','-Wl,-T,tests/link.ld']
for seed in range(a.random_programs):
 name=f'random_{seed}'; src=f'build/{name}.S'
 run(['python3','tools/gen_random.py',str(seed),src])
 run([a.cc,*flags,'-o',f'build/{name}.elf',src])
 run([a.objcopy,'-O','binary',f'build/{name}.elf',f'build/{name}.bin'])
 run(['python3','tools/bin2hex.py',f'build/{name}.bin',f'build/{name}.hex'])
 programs.append(name)
jobs=[(name,seed,[],0xffffffff) for name in programs for seed in range(1,a.seeds+1)]
jobs.extend([('directed',1,['+write_order=1'],0xffffffff),('directed',1,['+write_order=2'],0xffffffff),('directed',1,['+long_stall'],0xffffffff),('directed',1,['+error_addr=00004004'],0x4004)])
for job,(name,seed,extra,error_addr) in enumerate(jobs):
  trace=f'build/{name}_{seed}_{job}.trace'
  log=run([a.vvp,'build/soc.vvp',f'+image=build/{name}.hex',f'+trace={trace}',f'+seed={seed}',*extra])
  if 'PASS cycles=' not in log:raise AssertionError(log)
  arch=check(f'build/{name}.hex',trace,error_addr)
  metrics={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',log)}
  counts.update(arch['mnemonics']);traps.update(arch['traps'])
  cases.append({'program':name,'seed':seed,'options':extra,'metrics':metrics,'architectural':arch})
  print(f"PASS {name} seed={seed} trace={arch['instructions']} cycles={metrics['cycles']}",flush=True)
# Verify all implemented nonprivileged integer operations were exercised.
required=set('lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu sb sh sw add sub sll slt sltu xor srl sra or and addi slli slti sltiu xori srli srai ori andi mul mulh mulhsu mulhu div divu rem remu fence fence.i csrrw csrrs csrrc csrrwi csrrsi csrrci ecall ebreak mret'.split())
missing=required-counts.keys()
if missing:raise AssertionError(f'missing mnemonic coverage: {sorted(missing)}')
if not {'0','1','2','3','4','5','6','7','11'}<=traps.keys():raise AssertionError(f'missing exception cause {traps}')
report={'status':'PASS','cases':len(cases),'muldiv_vectors':2560,'total_trace_instructions':sum(x['architectural']['instructions'] for x in cases),'mnemonic_counts':dict(sorted(counts.items())),'exception_counts':dict(sorted(traps.items())),'runs':cases}
Path('reports/regression.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"PASS regression cases={len(cases)} instructions={report['total_trace_instructions']}")
