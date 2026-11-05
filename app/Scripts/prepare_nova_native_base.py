"""Cache a stable engine memory base per generated function; preserve all access semantics.
Design reference: upstream 9357c18 prepare_memory_base.py (MIT). Independent fail-closed patcher.
"""
import argparse,hashlib,json,re
from pathlib import Path
OLD='  uint8_t* const wasm_rt_local_memory_base = NULL;'
NEW='  uint8_t* const wasm_rt_local_memory_base = NOVA_FUNCTION_MEMORY_BASE(instance);'
ACCESS=re.compile(r'(?<![A-Za-z0-9_])MEM_ADDR\(mem, addr, (sizeof\(t[12]\)|16)\)')
def patch(root):
 generated=root/'Generated';units=sorted(generated.glob('game_*.c'))
 if not units:raise RuntimeError('No generated engine units; refusing silent no-op')
 plans=[];count=0;atomic_before=[]
 for path in units:
  source=path.read_text();count+=source.count(OLD)+source.count(NEW)
  # All explicit atomic/wait/notify call sites remain byte-identical in order.
  atomics=re.findall(r'\b(?:i(?:32|64)_atomic_\w+|pg_atomic_\w+)\s*\([^;]*;',source)
  changed=source.replace(OLD,NEW)
  if atomics!=re.findall(r'\b(?:i(?:32|64)_atomic_\w+|pg_atomic_\w+)\s*\([^;]*;',changed):raise RuntimeError('Atomic operations changed')
  plans.append((path,changed));atomic_before+=atomics
 if count==0:raise RuntimeError('Unknown generator memory-base declarations')
 helpers=0
 for name in ['game-impl.h','game-heap-impl.h','game-plain-impl.h']:
  path=generated/name
  if not path.exists():
   if name=='game-impl.h':raise RuntimeError('Missing main helper header')
   continue
  source=path.read_text();base='base' if name=='game-plain-impl.h' else 'wasm_rt_local_memory_base'
  changed,n=ACCESS.subn(lambda m:'NOVA_MEM_ADDR('+base+', mem, addr, '+m[1]+')',source)
  helpers+=n+changed.count('NOVA_MEM_ADDR(')-n
  plans.append((path,changed))
 if helpers==0:raise RuntimeError('Unknown shared scalar helper shape')
 # Validate everything before writing; report only hashes/counts, never engine bytes.
 for path,text in plans:
  if path.read_text()!=text:path.write_text(text)
 report={'variant':'Nova Native Runtime V1','cachedFunctionBases':count,'helperSites':helpers,'explicitAtomicCallsPreserved':len(atomic_before),'atomicCallSHA256':hashlib.sha256('\n'.join(atomic_before).encode()).hexdigest(),'plainEngineConversion':False,'generatedSHA256':{path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path,_ in plans}}
 (generated/'nova-native-codegen.json').write_text(json.dumps(report,indent=2));return report
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);a=parser.parse_args();print(json.dumps(patch(a.root)))
