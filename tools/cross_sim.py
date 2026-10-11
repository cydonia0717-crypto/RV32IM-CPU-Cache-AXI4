#!/usr/bin/env python3
"""Independently simulate the directed and compiled-C images with Verilator."""
import subprocess,json
from pathlib import Path
from reference import check
results=[]
for name,options in [('directed',[]),('algorithm',[]),('directed',['+long_stall'])]:
 trace=f'build/{name}_verilator_{len(results)}.trace'
 p=subprocess.run(['build/obj_verilator/soc_verilator',f'+image=build/{name}.hex',f'+trace={trace}','+seed=17',*options],capture_output=True,text=True,timeout=180,check=True)
 if 'PASS cycles=' not in p.stdout:raise AssertionError(p.stdout)
 arch=check(f'build/{name}.hex',trace)
 results.append({'program':name,'options':options,'architectural':arch,'output':p.stdout.strip()})
 print(f"PASS Verilator {name} {options} instructions={arch['instructions']}",flush=True)
Path('reports/cross-simulator.json').write_text(json.dumps({'status':'PASS','runs':results},indent=2)+'\n')
