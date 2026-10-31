"""Expand RPF's24-bit sentinel consistently across size, read and scheduling paths.
Only indexed mod entries are expanded; base game behavior is identical.
"""
from pathlib import Path
import re
from engine_names import fn
root=Path(__file__).resolve().parents[1]
patches={
 'rage::fiPackfile::FindFileBegin(char const*, rage::fiFindData&) const':[('var_i0','var_i1','var_l6')],
 'rage::fiPackfile::FindFileNext(fiHandle__*, rage::fiFindData&) const':[('var_i0','var_i1','var_l3')],
 'rage::fiPackfile::Seek64(fiHandle__*, long, rage::fiSeekWhence) const':[('var_i0','var_i1','var_l6'),('var_i1','var_i2','var_l6')],
 'rage::fiPackfile::ReadInternal(rage::fiPackfileState&, void*, int) const': [('var_i1','var_i2','var_l9'),('var_i0','var_i1','var_l9')],
 'rage::fiPackfile::Size(fiHandle__*) const':[('var_i0','var_i1','var_p1')],
 'rage::fiPackfile::Size64(fiHandle__*) const':[('var_i0','var_i1','var_p1')],
 'rage::fiPackfile::GetFileSize(char const*) const':[('var_i0','var_i1','var_p0')],
 'rage::pgStreamer::Read(unsigned int, rage::datResourceChunk*, int, unsigned int, void (*)(void*, void*, unsigned int, unsigned int), void*, rage::pgStreamer::Device, unsigned int, void*, float)':[('var_i0','var_i1','var_l9'),('var_j2','var_j3','var_l9')],
 'rage::strStreamingInfoManager::RegisterObject(char const*, unsigned int, int, bool&, bool, rage::fiPackEntry*, bool)':[('var_j0','var_j1','var_p5')],
 'rage::strStreamingInfoManager::GetNextFilesOnCdNew(unsigned int, bool, rage::strIndex*, int, unsigned int, unsigned int)':[('var_j0','var_j1','var_l21')],
 'rage::strStreamingLoader::LoadRequestedObjects()':[('var_j3','var_j4','var_l33')],
}
declaration='extern u32 pg_large_rpf_size(w2c_game *instance, u64 entry, u32 encoded);'
for name,sites in patches.items():
 number=fn(name);head=re.compile(r'^\w+ w2c_game_f'+str(number)+r'\([^\n]*(?:\n[^{}]*)?\) \{',re.M)
 found=None
 for p in sorted((root/'Generated').glob('game_*.c')):
  s=p.read_text();m=head.search(s)
  if m:found=(p,s,m);break
 if found is None:raise RuntimeError('Missing pinned function '+name)
 p,s,m=found;end=s.index('\n}\n',m.start());body=s[m.start():end]
 if 'pg_large_rpf_size(' in body:continue
 for value,mask,entry in sites:
  literal='16777215u' if value.startswith('var_i') else '16777215ull'
  pattern=re.compile(r'(?m)^( +)'+mask+' = '+literal+r';\n\1'+value+' &= '+mask+r';\n')
  matches=list(pattern.finditer(body))
  if len(matches)!=1:raise RuntimeError(f'Pinned {name}: ambiguous size mask {value}/{mask}')
  match=matches[0];indent=match[1]
  body=body[:match.end()]+indent+value+' = pg_large_rpf_size(instance, '+entry+', (u32)'+value+');\n'+body[match.end():]
 s=s[:m.start()]+body+s[end:]
 if declaration not in s:
  include=re.search(r'^#include "game-[a-z-]*impl.h"$',s,re.M)
  if not include:raise RuntimeError('Missing generated implementation header')
  s=s[:include.end()]+'\n'+declaration+s[include.end():]
 p.write_text(s);print(f'Extended resource sizes: patched {number} ({len(sites)} sites)')

# ReInit deletes/replaces its entry table directly; Shutdown frees it too.
for name,kind in [('rage::fiPackfile::Shutdown()','void'),('rage::fiPackfile::ReInit(char const*, bool, void*)','u32')]:
 number=fn(name)
 head=(f'void w2c_game_f{number}(w2c_game* instance, u64 var_p0) {{' if kind=='void' else
       f'u32 w2c_game_f{number}(w2c_game* instance, u64 var_p0, u64 var_p1, u32 var_p2, u64 var_p3) {{')
 for p in sorted((root/'Generated').glob('game_*.c')):
  s=p.read_text()
  if head not in s:continue
  start=s.index(head);end=s.index('\n}\n',start)
  if 'pg_large_archive_unmount(instance, var_p0)' not in s[start:end]:
   s=s.replace(head,head+'\n  pg_large_archive_unmount(instance, var_p0);',1)
   first=re.search(r'^#include "game-[a-z-]*impl.h"$',s,re.M)
   declaration='extern void pg_large_archive_unmount(w2c_game*, u64);'
   if declaration not in s:s=s[:first.end()]+'\n'+declaration+s[first.end():]
   p.write_text(s)
  break
 else:raise RuntimeError('Pinned archive lifecycle missing: '+name)
