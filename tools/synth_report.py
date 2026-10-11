import sys,json,collections
from pathlib import Path
net=json.loads(Path(sys.argv[1]).read_text())
modules={}
for name,module in net['modules'].items():
 cells=collections.Counter(c['type'] for c in module['cells'].values())
 memories=[{'width':int(c['parameters']['WIDTH'],2),'words':int(c['parameters']['SIZE'],2)} for c in module['cells'].values() if c['type']=='$mem_v2']
 modules[name]={'cells':dict(sorted(cells.items())),'inferred_memories':memories}
for module in net['modules'].values():
 for cell in module['cells'].values():
  assert cell['type'] not in ('$dlatch','$adlatch','$mul','$div','$mod'), f"unexpected operator {cell['type']}"
mapped=json.loads(Path(sys.argv[1]).with_name('muldiv-stat.json').read_text())['design']
report={'mapped_muldiv':mapped,'checked_no_latches_or_multiply_divide_cells':True,'flow':'Yosys proc/opt/memory_collect/check; un-mapped whole-SoC elaboration, mapped muldiv','technology':'generic, no Liberty/process/STA','modules':modules}
Path(sys.argv[2]).write_text(json.dumps(report,indent=2)+'\n')
print('PASS synthesis structural check; inferred memories retained')
