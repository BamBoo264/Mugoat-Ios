"""Prepare ONLY the owner's engine, manifest and shader packs for a private build."""
import argparse
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def prepare(mirror, out):
    subprocess.run([sys.executable, str(ROOT/'native-port/app/Scripts/check_game_files.py'),
                    '--mirror', str(mirror)], check=True)
    if out.exists():
        raise ValueError('Output already exists; choose a fresh directory.')
    shader = mirror/'b/8b0b5899ed/shaders'
    index = json.loads((shader/'index.json').read_text())
    import tempfile
    with tempfile.TemporaryDirectory() as temp:
        archive = Path(temp)/'shaders.zip'
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
            z.write(shader/'index.json', 'index.json')
            for p in index['_packs']:
                name = p['file']
                if Path(name).name != name or '/' in name or '\\' in name:
                    raise ValueError('Invalid shader pack name')
                z.write(shader/name, name)
        inputs = out/'inputs'
        inputs.mkdir(parents=True)
        listing = []
        for n, (name, path) in enumerate([
            ('game.wasm', mirror/'b/8b0b5899ed/game.wasm'),
            ('manifest.json', mirror/'data/manifest.json'), ('shaders.zip', archive)]):
            parts, digest, size = [], hashlib.sha256(), 0
            with path.open('rb') as stream:
                while chunk := stream.read(16*1024*1024):
                    part = f'{n:02d}-{len(parts):04d}.part'
                    (inputs/part).write_bytes(chunk)
                    parts.append(part); digest.update(chunk); size += len(chunk)
            listing.append(dict(name=name, parts=parts, sha256=digest.hexdigest(), bytes=size))
        (inputs/'files.json').write_text(json.dumps({'files':listing}, indent=2)+'\n')
        print(json.dumps({'files':len(listing), 'bytes':sum(x['bytes'] for x in listing),
                          'out':str(out)}, indent=2))

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mirror', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args(); prepare(a.mirror.resolve(), a.out.resolve())
