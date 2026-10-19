"""Verify owner-provided private build inputs; never fetch game data from a server."""
import argparse
import hashlib
import io
import json
import re
import zipfile
from pathlib import Path

def assemble(inputs, out):
    listing = json.loads((inputs/'files.json').read_text())['files']
    if len(listing) != 3 or {x['name'] for x in listing} != {'game.wasm','manifest.json','shaders.zip'}:
        raise ValueError('Expected exactly engine, manifest and shaders.zip')
    verified = {}
    for entry in listing:
        parts = entry['parts']
        if not parts or len(parts)>32 or any(not re.fullmatch(r'\d{2}-\d{4}\.part', p) for p in parts):
            raise ValueError('Invalid input part name')
        if len(set(parts)) != len(parts): raise ValueError('Duplicate input part')
        for part in parts:
            path = inputs/part
            if path.is_symlink() or path.stat().st_size > 16*1024*1024:
                raise ValueError('Invalid input part size or symlink')
        data = b''.join((inputs/p).read_bytes() for p in parts)
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Input checksum mismatch: '+entry['name'])
        verified[entry['name']] = data
    with zipfile.ZipFile(io.BytesIO(verified['shaders.zip'])) as z:
        infos = z.infolist()
        if len(infos)>128 or sum(i.file_size for i in infos)>256*1024*1024:
            raise ValueError('Shader archive exceeds build input limit')
        if len({i.filename for i in infos}) != len(infos): raise ValueError('Duplicate shader entry')
        if any(not re.fullmatch(r'(index\.json|pack\d+\.[0-9a-f]+\.bin)', i.filename) for i in infos):
            raise ValueError('Unexpected shader file')
        index = json.loads(z.read('index.json'))
        expected = {'index.json'} | {p['file'] for p in index['_packs']}
        if expected != {i.filename for i in infos}: raise ValueError('Incomplete shader pack archive')
        if out.exists(): raise ValueError('Output already exists; refusing to overwrite')
        shaders = out/'b/8b0b5899ed/shaders'
        shaders.mkdir(parents=True); (out/'data').mkdir()
        for i in infos: (shaders/i.filename).write_bytes(z.read(i))
    (out/'b/8b0b5899ed/game.wasm').write_bytes(verified['game.wasm'])
    (out/'data/manifest.json').write_bytes(verified['manifest.json'])
    print('Private build inputs verified and assembled.')

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs',type=Path,required=True); p.add_argument('--out',type=Path,required=True)
    a=p.parse_args(); assemble(a.inputs.resolve(),a.out.resolve())
