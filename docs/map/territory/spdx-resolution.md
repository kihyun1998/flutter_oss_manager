# spdx-resolution

## What it is
The 3-stage pipeline that turns a hosted package and its license text into an SPDX id: cache → pub.dev → matcher (glossary: *SPDX resolution*).

## Governing decisions
**None.** Designed in `v2_1_plan.md` (draft plan); no decision record.

## Design model
From the source (`LicenseGenerator._resolveSpdx`):
- A cache hit of any source returns immediately.
- With `offline` false, a non-null pub.dev answer is cached as `pubApi` and returned.
- Otherwise the matcher runs; `Unknown` is cached as `negative`, anything else as `heuristic`.
- Every outcome is cached, so a `<name>@<version>` is resolved at most once until the cache is cleared.
- Hosted packages only; SDK packages call `matchLicense` directly (`_findAndSummarizeSdkLicense`).
- The source label printed per package is `cache`, `pub-api`, `heuristic` or `negative`.

## Code
- `lib/src/license_generator.dart — LicenseGenerator._resolveSpdx, LicenseGenerator.resolveSpdxForTesting`
- Tests: `test/resolve_spdx_test.dart`

## Reference behaviour
- [SPDX License List](../../agents/thegraph.md) — binding for the ids this pipeline returns.

## Cross-cutting invariants
- [spdx-identifier-spelling](../invariant/spdx-identifier-spelling.md) — results from pub.dev and from the matcher land in the same cache and the same `licenseSummary`.

## Blast radius
- [license-cache](license-cache.md) — the cache stores what this decides; a new outcome needs a `CacheSource`.
- [pub-dev-lookup](pub-dev-lookup.md) — its `null` means "fall through", for every failure.
- [license-matcher](license-matcher.md) — its `Unknown` string is what makes an entry `negative`.

## Known holes / open
- A heuristic or negative entry cached during an `--offline` run, or on any pub.dev miss (timeout, outage), is served on every later online scan; pub.dev is not asked again until `--refresh-cache`. Not intended (maintainer, 2026-10-24). `CacheSource` already records the source an invalidation policy would need (comment on `CacheSource`). Tracked: #13
- README "License Detection" says the heuristic is used when `--no-cache` was set; in the code `--no-cache` only skips the cache and still asks pub.dev. Tracked: #15
