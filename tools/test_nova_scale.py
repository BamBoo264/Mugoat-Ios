from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1];out=Path(sys.argv[1]);out.mkdir(exist_ok=True,parents=True)
s=(root/'app/App/NovaUpscaling.swift').read_text(encoding='utf-8').split('final class NovaUpscalingViewController')[0].replace('import UIKit','import Foundation')
s+='\nassert(NovaUpscaling.renderSize(width:1600,height:900,mode:0)==(1600,900))\nassert(NovaUpscaling.renderSize(width:1600,height:900,mode:2)==(1072,602))\nassert(NovaUpscaling.renderSize(width:1600,height:900,mode:3)==(800,450))\nassert(NovaUpscaling.renderSize(width:960,height:540,mode:3)==(640,360))\nfor m in 0...3 {let (w,h)=NovaUpscaling.renderSize(width:2400,height:1080,mode:m);assert(w%2==0 && h%2==0 && h>=360 && w<=2400 && h<=1080)}\nprint("PASS Nova internal/output scale and 360p floor")\n'
p=out/'nova-scale.swift';p.write_text(s);binary=out/'nova-scale';subprocess.run(['swiftc',str(p),'-o',str(binary)],check=True);subprocess.run([str(binary)],check=True)
