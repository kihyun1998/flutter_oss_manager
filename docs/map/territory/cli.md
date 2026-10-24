# cli

## What it is
The command surface users run: `dart run flutter_oss_manager scan|generate`. Parses flags, builds the `LicenseCache` and `LicenseGenerator`, and hands off. Holds no license logic of its own.

## Governing decisions
**None.** [ADR-0001](../../adr/0001-generated-files-excluded-from-dart-format.md) governs the output files' formatting, not the commands.

## Design model
From reading the source (`bin/flutter_oss_manager.dart — main`):
- `scan` flags: `--output`, `--offline`, `--refresh-cache`, `--no-cache`, `--runtime-only`. `--no-cache` means no `LicenseCache` is constructed at all; `--refresh-cache` loads and then `clear()`s it, so the next `save()` overwrites the file.
- `generate` takes one `--license-file` (mandatory) and runs only the matcher — no cache, no pub.dev.
- The project root is `Directory.current`; nothing lets a user point at another root.
- `--verbose` is parsed and only prints that it is enabled; no code reads it beyond that (`grep -rn verbose lib` is empty).

## Code
- `bin/flutter_oss_manager.dart — main`
- `pubspec.yaml — executables:`

## Reference behaviour
**None.**

## Cross-cutting invariants
**None.**

## Blast radius
- [scan-pipeline](scan-pipeline.md) — every `scan` flag is a parameter `scanPackages` or the `LicenseGenerator` constructor must still accept.
- [license-cache](license-cache.md) — the CLI owns the cache's load/clear lifecycle before the scan; a scan that also loads (`scanPackages` calls `_cache?.load()`) re-reads the file and would undo a `clear()` if ordering changed.
- [publishing](publishing.md) — the flag tables in README are hand-written copies of these options.

## Known holes / open
- `scanPackages` calls `_cache?.load()` again after the CLI already called `load()` and `clear()` for `--refresh-cache`. `load()` clears and re-reads the file, so the `clear()` appears to be undone and `--refresh-cache` would serve the old entries. No test covers it, and it was not run: no Dart toolchain was available (found by reading, 2026-10-24).
- `--verbose` does nothing.
