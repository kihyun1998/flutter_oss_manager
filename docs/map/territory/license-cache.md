# license-cache

## What it is
`LicenseCache`: the JSON file of resolved SPDX ids keyed by `<name>@<version>`, so repeat scans of one lockfile make no network calls.

## Governing decisions
**None.**

## Design model
From the source:
- File: `.dart_tool/flutter_oss_manager/pub_license_cache.json` under the project root; `.dart_tool/` is gitignored by Flutter's default template, so the cache is never committed.
- Schema `{schemaVersion: 1, entries: {key: {spdx, source, fetchedAt}}}`. A different `schemaVersion`, a non-map, a corrupt file, or an entry that fails `tryFromJson` is dropped silently — the next `save()` rewrites the file.
- Lifecycle: `load` once, `get`/`put` during a scan, `save` once. `get` asserts `load` ran.
- A version bump changes the key, so it invalidates naturally (README).
- Input from outside: the file is read whole, no size bound.

## Code
- `lib/src/license_cache.dart — CacheSource, CachedLicense.tryFromJson, LicenseCache.load, LicenseCache.get, LicenseCache.put, LicenseCache.save, LicenseCache.clear`
- Tests: `test/license_cache_test.dart`

## Reference behaviour
**None.**

## Cross-cutting invariants
- [spdx-identifier-spelling](../invariant/spdx-identifier-spelling.md) — stores ids from both sources side by side.

## Blast radius
- [spdx-resolution](spdx-resolution.md) — decides what is cached and that any hit wins.
- [cli](cli.md) — owns `load` / `clear` for `--refresh-cache` and skips the cache for `--no-cache`.

## Known holes / open
- No invalidation by age or source; see [spdx-resolution](spdx-resolution.md).
