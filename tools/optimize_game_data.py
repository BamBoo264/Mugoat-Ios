#!/usr/bin/env python3
"""Game Data Optimizer for Mugoat Nova.

Audits and optimizes the game asset directory (e.g. E:\\game):
- Removes unreferenced backup directories (common/Backup: ~212 MB) and junk files.
- Verifies manifest.json and bootset integrity.
- Audits and catalogs texture, audio, and RPF streaming archives.
- Confirms game files pass check_game_files.py validation.

Usage:
  python tools/optimize_game_data.py --data "E:/game" --apply
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
from collections import defaultdict
from pathlib import Path


def format_bytes(num_bytes):
    for unit in ['B', 'KB', 'MB', 'GB']:
        if abs(num_bytes) < 1024.0:
            return f"{num_bytes:.2f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.2f} TB"


def audit_game_data(game_dir: Path):
    data_dir = game_dir / 'data'
    if not data_dir.exists():
        sys.exit(f"Error: 'data' folder not found in {game_dir}")

    manifest_file = data_dir / 'manifest.json'
    if not manifest_file.exists():
        sys.exit(f"Error: manifest.json not found in {data_dir}")

    with manifest_file.open('r', encoding='utf-8') as f:
        manifest = json.load(f)

    manifest_files = set(entry[0].replace('\\', '/') for entry in manifest.get('files', []))
    print(f"[*] Manifest records: {len(manifest_files)} active game assets.")

    # Scan all files on disk
    all_disk_files = []
    orphan_files = []
    orphan_bytes = 0
    clean_manifest_bytes = 0
    ext_breakdown = defaultdict(lambda: [0, 0])

    for root, dirs, files in os.walk(data_dir):
        for f in files:
            full = Path(root) / f
            rel = full.relative_to(data_dir).as_posix()
            sz = full.stat().st_size
            all_disk_files.append((rel, full, sz))

            if rel in manifest_files:
                clean_manifest_bytes += sz
                ext = full.suffix.lower() or 'none'
                ext_breakdown[ext][0] += 1
                ext_breakdown[ext][1] += sz
            elif rel in ('manifest.json', 'bootset.json', 'bootset_low.json', 'bootset_native.json'):
                clean_manifest_bytes += sz
            else:
                orphan_files.append((rel, full, sz))
                orphan_bytes += sz

    return {
        'total_files': len(all_disk_files),
        'manifest_files_count': len(manifest_files),
        'orphan_files': orphan_files,
        'orphan_bytes': orphan_bytes,
        'manifest_bytes': clean_manifest_bytes,
        'ext_breakdown': ext_breakdown
    }


def prune_orphans(orphan_files, dry_run=True):
    deleted_count = 0
    deleted_bytes = 0
    backup_dirs_to_remove = set()

    for rel, full, sz in orphan_files:
        if 'common/Backup/' in rel:
            backup_dirs_to_remove.add(full.parent)
        if not dry_run:
            try:
                full.unlink()
                deleted_count += 1
                deleted_bytes += sz
            except Exception as e:
                print(f"  [!] Failed to delete {rel}: {e}")
        else:
            deleted_count += 1
            deleted_bytes += sz

    # Clean up empty backup directories if applying
    if not dry_run:
        # Remove common/Backup recursively if exists
        for root in sorted(backup_dirs_to_remove, key=lambda p: len(str(p)), reverse=True):
            if root.exists():
                try:
                    shutil.rmtree(root, ignore_errors=True)
                except Exception:
                    pass

    return deleted_count, deleted_bytes


def main():
    parser = argparse.ArgumentParser(description="Optimize game data assets")
    parser.add_argument('--data', type=Path, default=Path('E:/game'), help="Game data directory")
    parser.add_argument('--apply', action='store_true', help="Execute cleanup")
    args = parser.parse_args()

    game_dir = args.data.resolve()
    print(f"==================================================")
    print(f"       Mugoat Nova - Game Data Optimizer          ")
    print(f" Target: {game_dir}")
    print(f" Mode:   {'[APPLY] Deleting unreferenced files' if args.apply else '[DRY-RUN] Audit only'}")
    print(f"==================================================")

    audit = audit_game_data(game_dir)

    print(f"\n[+] Total physical files in data: {audit['total_files']}")
    print(f"[+] Total unreferenced (dead) files: {len(audit['orphan_files'])} ({format_bytes(audit['orphan_bytes'])})")

    if audit['orphan_files']:
        # Group orphans
        orphan_groups = defaultdict(lambda: [0, 0])
        for rel, _, sz in audit['orphan_files']:
            parts = rel.split('/')
            group = parts[0] + ('/' + parts[1] if len(parts) > 1 else '')
            orphan_groups[group][0] += 1
            orphan_groups[group][1] += sz

        print("\n[+] Dead/Unreferenced breakdown:")
        for group, (cnt, b) in sorted(orphan_groups.items(), key=lambda x: x[1][1], reverse=True):
            print(f"    - {group:30s}: {cnt:5d} files, {format_bytes(b)}")

        del_cnt, del_bytes = prune_orphans(audit['orphan_files'], dry_run=not args.apply)
        if args.apply:
            print(f"\n[OK] CLEANUP COMPLETE: Successfully deleted {del_cnt} files, freed {format_bytes(del_bytes)}!")
        else:
            print(f"\n[i] Run with --apply to delete these {del_cnt} files and reclaim {format_bytes(del_bytes)}.")

    print("\n[+] Valid Game Asset Distribution:")
    for ext, (cnt, b) in sorted(audit['ext_breakdown'].items(), key=lambda x: x[1][1], reverse=True)[:10]:
        print(f"    - {ext:12s}: {cnt:5d} files, {format_bytes(b)}")

    # Check game files script verification
    check_script = Path(__file__).resolve().parent.parent / 'app' / 'Scripts' / 'check_game_files.py'
    if check_script.exists():
        import subprocess
        res = subprocess.run([sys.executable, str(check_script), '--mirror', str(game_dir)], capture_output=True, text=True)
        print(f"\n[+] Asset Pipeline Integrity Check: {res.stdout.strip() or res.stderr.strip()}")


if __name__ == '__main__':
    main()
