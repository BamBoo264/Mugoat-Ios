from pathlib import Path
import hashlib,json,re,struct,unittest
ROOT=Path(__file__).resolve().parents[1]
class NovaIntegrity(unittest.TestCase):
 def test_original_audio_memory_sections(self):
  source=(ROOT/'app/Source/EngineHost.c').read_text(encoding='utf-8',errors='replace')
  for name,expected in json.loads((ROOT/'tools/nova-baseline-sections.json').read_text(encoding='utf-8',errors='replace')).items():
   with self.subTest(name=name):
    m=re.search(r'^.*?\b'+name+r'\([^;\n]*\)\s*\{',source,re.M);self.assertIsNotNone(m)
    end=source.index('\n}',m.start())+2
    self.assertEqual(hashlib.sha256(source[m.start():end].encode()).hexdigest(),expected)
 def test_original_audio_decoder_scripts(self):
  lock=json.loads((ROOT/'upstream-source-lock.json').read_text())
  # Locate the recorded source hashes without relying on incidental lock metadata.
  raw=(ROOT/'upstream-source-lock.json').read_text()
  for rel in ['app/Scripts/prepare_plain_dsp.py','app/Scripts/prepare_native_opus.py']:
   self.assertIn(hashlib.sha256((ROOT/rel).read_bytes().replace(b'\r\n', b'\n')).hexdigest(),raw)
 def test_pack_bounds_and_english_bank(self):
  if not (ROOT/'app/Resources/VietnameseAccented.nvp').exists():self.skipTest('Bundled resources pending public redistribution approval')
  for kind in ['Accented','Plain']:
   data=(ROOT/f'app/Resources/Vietnamese{kind}.nvp').read_bytes();self.assertEqual(data[:8],b'NOVAPAK1')
   length=struct.unpack_from('<Q',data,8)[0];rows=json.loads(data[16:16+length]);self.assertGreater(len(rows),1000)
   names=set();end=0
   for name,start,size in rows:
    self.assertNotIn(name.lower(),names);names.add(name.lower());self.assertEqual(start,end);end+=size
    self.assertNotIn('..',name.split('/'));self.assertLessEqual(16+length+end,len(data))
   self.assertEqual(16+length+end,len(data))
   if kind=='Accented':self.assertTrue('common/data/ui/fontmap.xml' in names)
 def test_no_v5_runtime_policies(self):
  host=(ROOT/'app/Source/EngineHost.c').read_text(encoding='utf-8',errors='replace')
  for item in ['NativeDistanceStreaming','NativeRuntimePolicy','NativeAudioDownmix','NativeLazyCPU','pg_distance_streaming']:
   self.assertNotIn(item,host)
  sound=(ROOT/'app/Source/NativeSoundMods.inc').read_text(encoding='utf-8',errors='replace');self.assertNotIn('stockSound',sound)
 def test_metal_binary_archive_and_data_optimizer(self):
  renderer = (ROOT/'app/Source/MetalRenderer/MRRenderer.mm').read_text(encoding='utf-8',errors='replace')
  self.assertIn('MTLBinaryArchive', renderer)
  self.assertIn('flushBinaryArchive', renderer)
  self.assertIn('metal_pso_cache.metallib', renderer)
  self.assertTrue((ROOT/'tools/optimize_game_data.py').exists())
if __name__=='__main__':unittest.main(verbosity=2)
