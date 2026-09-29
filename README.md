# Pathology Guide Pack

Content pack for the in-app guide («инструкция») of the
[Pathology](https://github.com/ne-tort/Pathology-Client) VPN client.

This repository is the **single source of truth** for guide content:

- the client consumes it as a git submodule (`assets/guide`) so a fresh
  install ships with a bundled snapshot;
- the client's **leaf-based OTA** watches `manifest.json` on the `main`
  branch (served via `raw.githubusercontent.com`) and downloads only the
  leaves whose `sha256` changed — not the whole pack.

## Layout

```
manifest.json                pack meta + per-leaf sha256/size map (generated)
toc.json                     sections → pages tree
pages/<pageId>.<locale>.json one file per page per locale
media/                       images referenced by pages
schema/guide-pack.schema.json JSON Schema of the pack
training/hotspots.json       training-mode hotspot map
tool/                        validation + manifest generation
```

## Workflow

1. Edit pages / toc / media as needed.
2. Bump `version` in `manifest.json` when content changes (semver; the
   client refuses packs with `schemaVersion` newer than it supports and
   gates by `minAppVersion`/`maxAppVersion`).
3. Push to `main`. CI validates the pack, regenerates the `files` map and
   commits it back, and tags `guide-v<version>` when the version changed.

Do not edit the `files` map by hand — `python3 tool/guide_manifest.py`
regenerates it (CI does this automatically).

## Validation

```
dart run tool/guide_validate.dart .
python3 tool/guide_manifest.py
```
