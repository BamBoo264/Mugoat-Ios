from pathlib import Path
import hashlib,plistlib,shutil,subprocess,tempfile,zipfile,json
root=Path(__file__).resolve().parents[1]
source=root/'app/Build/Release/Build/Products/Release-iphoneos/PlayGTA5Native.app'
entitlements=root/'app/App/Full.entitlements'
records=[]
for low in [False]:
 name='Mugoat-Nova-NativeRuntime-V8.1-UDP'
 with tempfile.TemporaryDirectory(prefix='nova-package-') as tmp:
  stage=Path(tmp);app=stage/'Payload/PlayGTA5Native.app';app.parent.mkdir();shutil.copytree(source,app,symlinks=True)
  p=app/'Info.plist';info=plistlib.loads(p.read_bytes());info.update(PGLiteMode=False,CFBundleDisplayName='Mugoat Nova',CFBundleIdentifier='vn.gta.newgen',CFBundleShortVersionString='1.1.8',CFBundleVersion='109',MinimumOSVersion='15.0');p.write_bytes(plistlib.dumps(info))
  subprocess.run(['codesign','--force','--sign','-','--entitlements',str(entitlements),'--generate-entitlement-der',str(app)],check=True)
  granted=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)],stderr=subprocess.DEVNULL))
  for key in ['com.apple.developer.kernel.increased-memory-limit','com.apple.developer.kernel.extended-virtual-addressing']:assert granted.get(key) is True
  subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
  target=root/(name+'.ipa')
  subprocess.run(['ditto','-c','-k','--keepParent',str(stage/'Payload'),str(target)],check=True)
  with zipfile.ZipFile(target) as z:
   packaged=plistlib.loads(z.read('Payload/PlayGTA5Native.app/Info.plist'));assert packaged['PGLiteMode']==low and packaged['CFBundleIdentifier']=='vn.gta.newgen'
  records.append({'file':target.name,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'lowRAM':low,'requestedEntitlements':granted})
(root/'Nova-NativeRuntime-V8.1-UDP-artifacts.json').write_text(json.dumps(records,indent=2))
print(json.dumps(records,indent=2))
