# spdx-identifier-spelling

## The fact
Every SPDX id the system produces or compares is spelled exactly as a license template's `licenseId` spells it: `_spdxCanonical`'s values, `_problematicLicenses`, and the literal `'Unknown'` all agree with `licenseId` strings, byte for byte.

## Why it is cross-cutting
Three independent string sets, none derived from another and no shared constant: template `licenseId` getters, the pub.dev lowercase→canonical table, and the copyleft list. The matcher's output and pub.dev's output land in the same cache entry and the same `OssLicense.licenseSummary`, and the copyleft check compares with `==`. The comment on `_spdxCanonical` states the intent: "Keeping this aligned with [LicenseGenerator]'s heuristic output lets cache entries be compared across sources."

## Territories it holds in
- [license-templates](../territory/license-templates.md) — `TemplateLicenseInfo.licenseId` in each `models/licenses/*.dart`
- [pub-dev-lookup](../territory/pub-dev-lookup.md) — `_spdxCanonical`, and the lowercase pass-through in `extractSpdxFromTags`
- [copyleft-warning](../territory/copyleft-warning.md) — `LicenseGenerator._problematicLicenses`
- [license-matcher](../territory/license-matcher.md) — the `'Unknown'` literal
- [spdx-resolution](../territory/spdx-resolution.md) — compares to `'Unknown'` to decide a negative entry
- [license-cache](../territory/license-cache.md) — stores both sources' strings
- [scan-pipeline](../territory/scan-pipeline.md) — writes `licenseSummary`

## What a violation looks like
One package reported under two spellings depending on whether pub.dev answered (`BSD-4-Clause` vs `bsd-4-clause`), or a copyleft license that does not warn. Reproduces whenever pub.dev returns a tag missing from `_spdxCanonical`.

## Discovery history
- Found by reading, 2026-10-24: `BSD-4-Clause` is a template id, but `bsd-4-clause` is not a key in `_spdxCanonical`, so a pub.dev answer for it passes through lowercase. Live violation. Tracked: #10
- `AGPL-3.0` is in `_problematicLicenses` and `_spdxCanonical` but has no template; it can only arrive from pub.dev.

## Where it will recur
Any change that adds a template, adds a pub.dev mapping, or adds a license to a list compared by string: check `grep -n "licenseId =>" lib/src/models/licenses/*.dart` against `_spdxCanonical` and `_problematicLicenses`. A move to current SPDX ids (`GPL-3.0-only`) must change all three at once.
