from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1];out=Path(sys.argv[1])
s=(root/'app/App/ControlsLayout.swift').read_text(encoding='utf8');s=s[:s.index('/// Full-screen editor:')].replace('import UIKit','import Foundation\nimport CoreGraphics')
fixture=out/'ControlsLayoutStorage.swift';fixture.write_text(s)
binary=out/'mission-controls'
subprocess.run(['swiftc',str(root/'app/App/ManualPadLayout.swift'),str(fixture),str(root/'app/Tests/mission_controls.swift'),'-o',str(binary)],check=True)
subprocess.run([str(binary)],check=True)
