import hashlib, importlib.util, io, json, tempfile, unittest, zipfile
from pathlib import Path

spec=importlib.util.spec_from_file_location('assemble',Path(__file__).resolve().parents[1]/'tools/assemble_inputs.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class InputTests(unittest.TestCase):
    def fixture(self, folder, bad_member=None):
        b=io.BytesIO()
        with zipfile.ZipFile(b,'w') as z:
            z.writestr('index.json',json.dumps({'_packs':[{'file':'pack0.abcd.bin'}]}))
            z.writestr('pack0.abcd.bin',b'shader')
            if bad_member: z.writestr(bad_member,b'bad')
        listing=[]
        for n,(name,data) in enumerate([('game.wasm',b'engine'),('manifest.json',b'{}'),('shaders.zip',b.getvalue())]):
            part=f'{n:02d}-0000.part'; (folder/part).write_bytes(data)
            listing.append(dict(name=name,parts=[part],bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
        (folder/'files.json').write_text(json.dumps({'files':listing}))
        return listing
    def test_roundtrip_preserves_bytes_and_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); self.fixture(p); out=p/'out'; module.assemble(p,out)
            self.assertEqual((out/'b/8b0b5899ed/game.wasm').read_bytes(),b'engine')
            with self.assertRaises(ValueError): module.assemble(p,out)
    def test_corruption_rejected_before_creating_output(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); self.fixture(p); (p/'00-0000.part').write_bytes(b'broken')
            with self.assertRaises(ValueError): module.assemble(p,p/'out')
            self.assertFalse((p/'out').exists())
    def test_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); self.fixture(p,'../escape')
            with self.assertRaises(ValueError): module.assemble(p,p/'out')
            self.assertFalse((p/'out').exists())
    def test_part_path_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); listing=self.fixture(p); listing[0]['parts']=['../secret']
            (p/'files.json').write_text(json.dumps({'files':listing}))
            with self.assertRaises(ValueError): module.assemble(p,p/'out')

if __name__=='__main__': unittest.main()
