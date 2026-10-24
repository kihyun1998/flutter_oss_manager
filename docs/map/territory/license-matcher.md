# license-matcher

## What it is
`matchLicense(text)`: the pure decision of which SPDX id a raw license text is, by template heuristic then Jaccard paragraph similarity (glossary: *License matcher*).

## Governing decisions
**None.**

## Design model
From the glossary and the source:
- Pure; returns a `MatchResult {spdx, method, confidence}` and prints nothing.
- Heuristic: every template whose `calculateScore` reaches `minMatches` is a candidate; the highest confidence wins. Ties keep priority order (Dart's `sort` is not guaranteed stable, so a tie's winner is not guaranteed).
- Fallback: normalize (drop `copyright (c) …` lines and `<…>`, collapse whitespace), split paragraphs, average per-paragraph best Jaccard against each template; above **0.5** wins as `similarity`.
- Otherwise `Unknown` / `none`.
- `_normalizeText` collapses all whitespace before splitting on blank lines, so the scanned text is always one paragraph.

## Code
- `lib/src/license_matcher.dart — matchLicense, MatchResult, MatchMethod, _normalizeText, _tokenize, _calculateJaccardSimilarity`
- Tests: `test/license_matcher_test.dart`

## Reference behaviour
- [SPDX License List](../../agents/thegraph.md) — binding for the ids returned.

## Cross-cutting invariants
- [spdx-identifier-spelling](../invariant/spdx-identifier-spelling.md) — returns a template's `licenseId` verbatim, or the literal `Unknown`.

## Blast radius
- [license-templates](license-templates.md) — the scores, thresholds and texts it reads are theirs.
- [spdx-resolution](spdx-resolution.md) — compares the result to the string `Unknown` to decide a negative entry.
- [scan-pipeline](scan-pipeline.md) — SDK packages and `generate` use it directly.

## Known holes / open
- Because `_normalizeText` collapses newlines before the paragraph split, the "paragraph" similarity compares whole texts; the 0.5 threshold was set against that behaviour, not against real paragraphs (found by reading, 2026-10-24). Tracked: #14
