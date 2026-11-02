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

if __name__ == "__main__":
    unittest.main()
