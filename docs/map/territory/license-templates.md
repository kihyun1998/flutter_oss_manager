# license-templates

## What it is
The built-in license descriptions under `lib/src/models/licenses/` — patterns, keywords, priority and full text per license — that the matcher scores against (glossary: *License template*).

## Governing decisions
**None.**

## Design model
From the source:
- Each implements `TemplateLicenseInfo`: `+20` per matching pattern, `+40` per unique keyword, `-30` per exclude keyword, `-20` over `maxLength`, clamped to 0..100.
- `allLicenses` is keyed by `licenseId`; two templates with one id would collide silently.
- Lower `priority` is checked first; most templates are 10 (`grep -n "priority =>" lib/src/models/licenses/*.dart`).
- Ids in use: `grep -n "licenseId =>" lib/src/models/licenses/*.dart`.

## Code
- `lib/src/models/template_license_info.dart — TemplateLicenseInfo.calculateScore`
- `lib/src/models/all_licenses.dart — allLicenses, getLicensesByPriority`
- `lib/src/models/licenses/*.dart`

## Reference behaviour
- [SPDX License List](../../agents/thegraph.md) — binding for ids and canonical texts. The ids `GPL-2.0`, `GPL-3.0`, `LGPL-2.1`, `LGPL-3.0` are deprecated in the current SPDX list in favour of `-only` / `-or-later`; not yet compared against `spdx/license-list-data`.

## Cross-cutting invariants
- [spdx-identifier-spelling](../invariant/spdx-identifier-spelling.md) — `licenseId` is one of its sites.

## Blast radius
- [license-matcher](license-matcher.md) — any score change moves which template wins.

## Known holes / open
- Template texts have not been compared to SPDX's canonical texts.
