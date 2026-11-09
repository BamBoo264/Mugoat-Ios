import unittest
import os
import struct
import json
from pathlib import Path

class TestPortRPFLoader(unittest.TestCase):
    def setUp(self):
        self.gtav_dir = Path("E:/GTAV_IOS")
        self.has_gtav = self.gtav_dir.exists() and (self.gtav_dir / "common.rpf").exists()

    def test_rpf_header_and_magic(self):
        if not self.has_gtav:
            self.skipTest("E:/GTAV_IOS not available on this runner")
        common_path = self.gtav_dir / "common.rpf"
        with open(common_path, "rb") as f:
            header = f.read(16)
            magic, count, names_len, enc = struct.unpack("<IIII", header)
            self.assertEqual(magic, 0x52504637, "common.rpf must have RPF7 magic")
            self.assertGreater(count, 0, "entry count must be positive")
            self.assertGreater(names_len, 0, "names length must be positive")

    def test_commandline_options(self):
        if not self.has_gtav:
            self.skipTest("E:/GTAV_IOS not available on this runner")
        cmd_path = self.gtav_dir / "commandline.txt"
        self.assertTrue(cmd_path.exists(), "commandline.txt should exist in Port folder")
        content = cmd_path.read_text(encoding="utf-8")
        self.assertIn("-memrestrict=850", content)
        self.assertIn("-minimapTopLeft", content)
        self.assertIn("-fpsCounter", content)

    def test_native_port_rpf_source_contract(self):
        root = Path(__file__).resolve().parents[1]
        rpf_h = root / "app/Source/NativePortRPF.h"
        self.assertTrue(rpf_h.exists(), "NativePortRPF.h must exist")
        content = rpf_h.read_text(encoding="utf-8")
        self.assertIn("PGInitPortRPF", content)
        self.assertIn("PGReadPortRPFAsset", content)
        self.assertIn("PGIndexRPFChildren", content)

        assets_m = root / "app/Source/NativeAssets.m"
        assets_content = assets_m.read_text(encoding="utf-8")
        self.assertIn("NativePortRPF.h", assets_content)
        self.assertIn("isLocalPortRPF", assets_content)

        game_files_swift = root / "app/App/GameFiles.swift"
        gf_content = game_files_swift.read_text(encoding="utf-8")
        self.assertIn("isPortRPF", gf_content)
        self.assertIn("checkPortRPF", gf_content)

    def test_cache_root_declared_before_use(self):
        root = Path(__file__).resolve().parents[1]
        assets_m = root / "app/Source/NativeAssets.m"
        lines = assets_m.read_text(encoding="utf-8").splitlines()
        cache_root_decl = -1
        set_folder_decl = -1
        for idx, line in enumerate(lines):
            if "static NSString *cacheRoot;" in line and cache_root_decl == -1:
                cache_root_decl = idx
            if "void PGSetLocalGameFolder(" in line and set_folder_decl == -1:
                set_folder_decl = idx
        self.assertGreater(cache_root_decl, -1, "cacheRoot must be declared")
        self.assertGreater(set_folder_decl, -1, "PGSetLocalGameFolder must exist")
        self.assertLess(cache_root_decl, set_folder_decl, "cacheRoot must be declared before PGSetLocalGameFolder")

    def test_rpf_unencrypted_spoof_contract(self):
        root = Path(__file__).resolve().parents[1]
        rpf_h = root / "app/Source/NativePortRPF.h"
        content_h = rpf_h.read_text(encoding="utf-8")
        self.assertIn("PGPatchRPFEncryptionHeader", content_h)
        self.assertIn("0x4E45504F", content_h)

        assets_m = root / "app/Source/NativeAssets.m"
        content_m = assets_m.read_text(encoding="utf-8")
        self.assertIn("PGPatchRPFEncryptionHeader", content_m)

        prep_mod = root / "app/Scripts/prepare_mod_archives.py"
        content_prep = prep_mod.read_text(encoding="utf-8")
        self.assertIn("var_p0 == 0u", content_prep, "prepare_mod_archives.py must bypass AES for key 0")

    def test_audio_rel_structure(self):
        if not self.has_gtav:
            self.skipTest("E:/GTAV_IOS not available on this runner")
        audio_rel = self.gtav_dir / "x64/audio/audio_rel.rpf"
        self.assertTrue(audio_rel.exists(), "audio_rel.rpf must exist in E:/GTAV_IOS/x64/audio")
        with open(audio_rel, "rb") as f:
            header = f.read(16)
            magic, count, names_len, enc = struct.unpack("<IIII", header)
            self.assertEqual(magic, 0x52504637)
            raw_entries = [f.read(16) for _ in range(count)]
            names_data = f.read(names_len)
            names = []
            for raw in raw_entries:
                e0, e1 = struct.unpack("<QQ", raw)
                no = e0 & 0xFFFF
                name = names_data[no:].split(b"\x00")[0].decode("latin1")
                names.append(name)
            self.assertIn("game.dat151.rel", names)
            self.assertIn("sounds.dat54.rel", names)
            self.assertIn("packlist_rel.txt", names)

    def test_rpf_encryption_patch_simulation(self):
        def simulate_patch(rel_path, offset, data):
            length = len(data)
            out = bytearray(data)
            if offset <= 12 and (offset + length) >= 16:
                enc_idx = 12 - offset
                if enc_idx + 4 <= length:
                    enc = struct.unpack("<I", out[enc_idx:enc_idx+4])[0]
                    if enc == 0:
                        if offset == 0:
                            magic = struct.unpack("<I", out[:4])[0]
                            if magic == 0x52504637:
                                out[enc_idx:enc_idx+4] = struct.pack("<I", 0x4E45504F)
                        elif rel_path.lower().endswith(".rpf"):
                            out[enc_idx:enc_idx+4] = struct.pack("<I", 0x4E45504F)
            return bytes(out)

        # 1. offset 0, len 16: zero enc -> OPEN
        raw = struct.pack("<IIII", 0x52504637, 20, 384, 0)
        res = simulate_patch("x64/audio/audio.rpf", 0, raw)
        _, _, _, enc = struct.unpack("<IIII", res)
        self.assertEqual(enc, 0x4E45504F)

        # 2. offset 12, len 4: zero enc -> OPEN
        raw = struct.pack("<I", 0)
        res = simulate_patch("x64/audio/occlusion.rpf", 12, raw)
        enc = struct.unpack("<I", res)[0]
        self.assertEqual(enc, 0x4E45504F)

        # 3. non-rpf: preserved
        raw = b"123456789012" + struct.pack("<I", 0)
        res = simulate_patch("common/data/file.meta", 0, raw)
        enc = struct.unpack("<I", res[12:16])[0]
        self.assertEqual(enc, 0)

        # 4. PC encrypted archive (0x0FFFFFF9): preserved
        raw = struct.pack("<IIII", 0x52504637, 551, 13408, 0x0FFFFFF9)
        res = simulate_patch("x64/audio/audio.rpf", 0, raw)
        _, _, _, enc = struct.unpack("<IIII", res)
        self.assertEqual(enc, 0x0FFFFFF9)

    def test_persistent_archive_fd_cache_and_optimization(self):
        root = Path(__file__).resolve().parents[1]
        rpf_h = root / "app/Source/NativePortRPF.h"
        content_h = rpf_h.read_text(encoding="utf-8")
        self.assertIn("PGGetPortArchiveFD", content_h, "PGGetPortArchiveFD must exist for persistent FD caching")
        self.assertIn("portArchiveFDs", content_h, "portArchiveFDs table must be defined")
        self.assertIn("PGTryReadBlockCache", content_h, "RAM block cache lookup must be implemented")
        self.assertIn("PGStoreBlockCache", content_h, "RAM block cache store must be implemented")

        assets_m = root / "app/Source/NativeAssets.m"
        content_m = assets_m.read_text(encoding="utf-8")
        # Ensure isLocalPortRPF check precedes loose file open() to eliminate ENOENT churn
        port_check_idx = content_m.find("if(isLocalPortRPF)")
        loose_open_idx = content_m.find("int descriptor=open(file.fileSystemRepresentation,O_RDONLY);")
        self.assertGreater(port_check_idx, -1)
        self.assertGreater(loose_open_idx, -1)
        self.assertLess(port_check_idx, loose_open_idx, "isLocalPortRPF check must come before loose file open()")

    def test_lspatrol_blip_natives_and_callout_support(self):
        root = Path(__file__).resolve().parents[1]
        inc = root / "app/Generated/asi-natives.inc"
        self.assertTrue(inc.exists(), "asi-natives.inc must exist")
        inc_content = inc.read_text(encoding="utf-8")
        self.assertIn("0x586afe3ff72d996eull", inc_content, "GET_BLIP_COORDS must be in asi-natives.inc")
        self.assertIn("0xc0296a2edf545e92ull", inc_content, "IS_MODEL_VALID must be in asi-natives.inc")
        self.assertIn("0xe83a3e3557a56640ull", inc_content, "SCALEFORM_MOVIE_METHOD_ADD_PARAM_PLAYER_NAME_STRING must be in asi-natives.inc")

        asi_h = root / "app/Source/NativeASI.h"
        asi_h_content = asi_h.read_text(encoding="utf-8")
        self.assertIn("lspatrolCalloutPending", asi_h_content, "lspatrolCalloutPending must be declared in PGAsiKeyInfo")
        self.assertIn("lspatrolLoaded", asi_h_content, "lspatrolLoaded must be declared in PGAsiKeyInfo")

        modkeys_swift = root / "app/App/ModKeysView.swift"
        mk_content = modkeys_swift.read_text(encoding="utf-8")
        self.assertIn("calloutPad", mk_content, "ModKeysView must define calloutPad for callout acceptance")
        self.assertIn("calloutAcceptDown", mk_content, "ModKeysView must have accept handler")
        self.assertIn("calloutDeclineDown", mk_content, "ModKeysView must have decline handler")
        self.assertIn("PGAsiSetKey(0x59", mk_content, "ModKeysView must send key 0x59 (Y)")
        self.assertIn("PGAsiSetKey(0x4E", mk_content, "ModKeysView must send key 0x4E (N)")

if __name__ == "__main__":
    unittest.main()
