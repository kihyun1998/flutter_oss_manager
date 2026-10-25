# copyleft-warning

## What it is
The banner a `scan` prints when a collected license is in `_problematicLicenses` (GPL/LGPL/AGPL), with a tip to re-run with `--runtime-only`.

## Governing decisions
**None.**

## Design model
From the source:
- Exact string match on `licenseSummary`: `GPL-2.0`, `GPL-3.0`, `LGPL-2.1`, `LGPL-3.0`, `AGPL-3.0`.
- Only printed; the scan still writes the files and exits 0.
- The `--runtime-only` tip is shown only when that flag is off (CHANGELOG 2.2.0).

## Code
- `lib/src/license_generator.dart — LicenseGenerator._problematicLicenses, LicenseGenerator._printLicenseWarnings`

## Reference behaviour
**None.**

## Cross-cutting invariants
- [spdx-identifier-spelling](../invariant/spdx-identifier-spelling.md) — `_problematicLicenses` is one of its sites.

## Blast radius
- [scan-pipeline](scan-pipeline.md) — fed from its collected list.

## Known holes / open
- `GPL-3.0-only`, `GPL-2.0-or-later` and other current SPDX forms are not in the list, so a pub.dev answer in that form would not warn (tracked: #19). No exit code a CI could gate on.
