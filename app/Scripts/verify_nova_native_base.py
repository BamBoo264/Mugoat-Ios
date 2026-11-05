import hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1];generated=root/'Generated'
r=json.loads((generated/'nova-native-codegen.json').read_text())
assert r['cachedFunctionBases']>1000 and r['helperSites']>0 and not r['plainEngineConversion']
for name,expected in r['generatedSHA256'].items():
 assert Path(name).name==name
 assert hashlib.sha256((generated/name).read_bytes()).hexdigest()==expected,'Generated file changed after validation: '+name
print('PASS: sealed native code generation; atomic calls preserved:',r['explicitAtomicCallsPreserved'],'cached functions:',r['cachedFunctionBases'])
