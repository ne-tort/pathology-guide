#!/usr/bin/env python3
"""Regenerate the per-leaf `files` map in manifest.json.

Every pack leaf (toc.json, pages/*, media/*, schema/*, training/*) gets a
sha256 + size entry. The client's leaf-based OTA compares these hashes and
downloads only the changed leaves. manifest.json itself is the descriptor and
is intentionally not listed.

Run from the repo root: python3 tool/guide_manifest.py
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK_TOP_FILES = ("toc.json",)
PACK_DIRS = ("pages", "media", "schema", "training")


def pack_leaves() -> list[Path]:
    leaves: list[Path] = [ROOT / name for name in PACK_TOP_FILES if (ROOT / name).is_file()]
    for folder in PACK_DIRS:
        directory = ROOT / folder
        if not directory.is_dir():
            continue
        leaves.extend(p for p in sorted(directory.rglob("*")) if p.is_file() and not p.name.startswith("."))
    return [p for p in leaves if p.is_file()]


def main() -> None:
    manifest_path = ROOT / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))

    files = {}
    for leaf in pack_leaves():
        data = leaf.read_bytes()
        files[leaf.relative_to(ROOT).as_posix()] = {
            "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data),
        }

    manifest.pop("contentHash", None)  # legacy placeholder, superseded by `files`
    manifest["files"] = dict(sorted(files.items()))
    # Explicit LF: pack leaves are eol=lf (.gitattributes) and the client's
    # leaf-based OTA compares sha256 against raw.githubusercontent bytes, so a
    # Windows CRLF translation here would desync the descriptor from the repo.
    with manifest_path.open("w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"manifest.json: {len(files)} leaves")


if __name__ == "__main__":
    main()
