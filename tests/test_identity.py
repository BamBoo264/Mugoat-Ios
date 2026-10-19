"""XcodeGen overwrites Info.plist: both identity declarations must agree."""
import plistlib, re, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
class IdentityTests(unittest.TestCase):
    def test_xcodegen_and_plist_agree_and_keep_old_app_separate(self):
        app=ROOT/'native-port/app'
        info=plistlib.loads((app/'App/Info.plist').read_bytes())
        project=(app/'project.yml').read_text()
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER: vn.iosvn.mugoat.recovery',project)
        for key in ['CFBundleDisplayName','CFBundleShortVersionString','CFBundleVersion']:
            match=re.search(r'^\s+'+key+r':\s*(.+)$',project,re.M)
            self.assertIsNotNone(match)
            self.assertEqual(match[1].strip().strip('"'),info[key])

if __name__=='__main__':unittest.main()
