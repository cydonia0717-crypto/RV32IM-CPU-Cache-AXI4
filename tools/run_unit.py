#!/usr/bin/env python3
import argparse,json,subprocess
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('--vvp',default='vvp');a=ap.parse_args()
results=[]
for name in ['muldiv','cache']:
 p=subprocess.run([a.vvp,f'build/{name}.vvp'],capture_output=True,text=True,timeout=60,check=True)
 print(p.stdout,end='')
 if f'PASS {name}' not in p.stdout: raise AssertionError('missing unit PASS')
 results.append({'name':name,'status':'PASS','output':p.stdout.strip()})
Path('reports/unit.json').write_text(json.dumps({'status':'PASS','tests':results},indent=2)+'\n')
