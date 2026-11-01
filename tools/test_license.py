#!/usr/bin/env python3
import unittest
import hashlib

SALT = "MugoatNova#2026@SecretLicenseSalt!"

def format_device_id(raw_uuid: str) -> str:
    clean = raw_uuid.replace("-", "").strip().upper()
    h = hashlib.sha256(clean.encode("utf-8")).hexdigest().upper()
    code = h[:8]
    return f"{code[:4]}-{code[4:8]}"

def generate_key(device_code: str) -> str:
    clean = (
        device_code.replace("NOVA-", "")
        .replace("-", "")
        .replace(" ", "")
        .strip()
        .upper()
    )
    h = hashlib.sha256(f"{clean}:{SALT}".encode("utf-8")).hexdigest().upper()
    code = h[8:16]
    return f"NOVA-{code[:4]}-{code[4:8]}"

def compute_signature(device_id: str, key: str) -> str:
    clean_id = device_id.replace("-", "").upper()
    clean_key = key.replace("-", "").upper()
    payload = f"ACTIVATED:{clean_id}:{clean_key}:{SALT}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest().upper()

class TestLicense(unittest.TestCase):
    def test_device_id_format(self):
        dev = format_device_id("E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
        self.assertEqual(len(dev), 9)
        self.assertEqual(dev[4], "-")
        self.assertEqual(dev, "0CD2-2316")

    def test_key_generation(self):
        key = generate_key("0CD2-2316")
        self.assertTrue(key.startswith("NOVA-"))
        self.assertEqual(key, "NOVA-3B2B-18B9")

    def test_case_and_dash_tolerance(self):
        k1 = generate_key("0cd22316")
        k2 = generate_key("0CD2-2316")
        k3 = generate_key(" 0cd2-2316 ")
        self.assertEqual(k1, k2)
        self.assertEqual(k2, k3)

    def test_tamper_signature(self):
        dev = "0CD2-2316"
        key = generate_key(dev)
        sig = compute_signature(dev, key)
        self.assertEqual(len(sig), 64)
        tampered_sig = compute_signature("FFFF-FFFF", key)
        self.assertNotEqual(sig, tampered_sig)

if __name__ == "__main__":
    unittest.main()
