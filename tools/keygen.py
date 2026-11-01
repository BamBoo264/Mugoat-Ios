#!/usr/bin/env python3
"""
Mugoat Nova - Key Generator (Admin Tool)
Generates offline device-bound activation keys for Mugoat Nova.
"""
import hashlib
import sys
import subprocess
import os

if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

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

def copy_to_clipboard(text: str):
    try:
        if sys.platform == "darwin":
            p = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
            p.communicate(text.encode("utf-8"))
        elif sys.platform == "win32":
            subprocess.run(["powershell", "-Command", f"Set-Clipboard -Value '{text}'"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif sys.platform.startswith("linux"):
            p = subprocess.Popen(["xclip", "-selection", "clipboard"], stdin=subprocess.PIPE)
            p.communicate(text.encode("utf-8"))
    except Exception:
        pass

def main():
    print("=" * 50)
    print("       MUGOAT NOVA - BO TAO KEY KICH HOAT")
    print("=" * 50)

    if len(sys.argv) > 1:
        dev_code = sys.argv[1]
    else:
        dev_code = input("Nhap ma thiet bi cua khach (VD: 0CD2-2316): ").strip()

    if not dev_code:
        print("Loi: Ma thiet bi khong duoc de trong!")
        return

    key = generate_key(dev_code)
    copy_to_clipboard(key)

    print("\n--------------------------------------------------")
    print(f" Ma thiet bi : {dev_code.upper()}")
    print(f" Key tao ra  : {key}")
    print("--------------------------------------------------")
    print("[OK] Da tu dong sao chep Key vao Clipboard!")
    print("Ban chi can nhan Ctrl+V / Dan de gui cho khach.")
    print("=" * 50)

if __name__ == "__main__":
    main()
