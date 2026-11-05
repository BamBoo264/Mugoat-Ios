import importlib.util,tempfile,unittest,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('patcher',root/'app/Scripts/prepare_nova_native_base.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class CodegenTests(unittest.TestCase):
 def fixture(self,p):
  d=p/'Generated';d.mkdir()
  (d/'game_0.c').write_text('u32 w2c_game_f1(w2c_game* instance) {\n'+module.OLD+'\n i32_atomic_store_shared(NULL,0,mem,0,1);\n pg_atomic_wait32(mem,0,1,0);\n return 1;\n}\n')
  (d/'game-impl.h').write_text('MEM_ADDR(mem, addr, sizeof(t1))\nMEM_ADDR(mem, addr, 16)\n')
  return d
 def test_idempotent_and_atomics_preserved(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t);d=self.fixture(p);a=module.patch(p);before={f.name:f.read_bytes() for f in d.iterdir()};b=module.patch(p)
   self.assertEqual(before,{f.name:f.read_bytes() for f in d.iterdir()});self.assertEqual(a,b);self.assertEqual(a['explicitAtomicCallsPreserved'],2)
   self.assertIn(module.NEW,(d/'game_0.c').read_text());self.assertIn('NOVA_MEM_ADDR(wasm_rt_local_memory_base',(d/'game-impl.h').read_text())
 def test_unknown_generator_fails_without_writes(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t);d=self.fixture(p);f=d/'game_0.c';f.write_text('unknown new generator');before={x.name:x.read_bytes() for x in d.iterdir()}
   with self.assertRaises(RuntimeError):module.patch(p)
   self.assertEqual(before,{x.name:x.read_bytes() for x in d.iterdir()})
 def test_pinned_memory_is_not_reallocated(self):
  s=(root/'app/Source/NativeThreads.c').read_text();s=s[s.index('u32 w2c_env_emscripten_resize_heap'):s.index('u64 w2c_env_emscripten_stack_snapshot')]
  self.assertNotIn('realloc(',s);self.assertNotIn('memory->data=',s);self.assertNotIn('memory->data =',s);self.assertIn('memory->size=pages*memory->page_size',s)
if __name__=='__main__':unittest.main(verbosity=2)
