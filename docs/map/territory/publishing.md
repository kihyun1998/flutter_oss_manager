# publishing

## What it is
Shipping the package to pub.dev: the version, what the archive contains, the changelog and README, and the committed sample output.

## Governing decisions
**None.**

## Design model
From the source:
- `lib/src/version.dart — packageVersion` is the in-code version, used by the User-Agent and every generated header; `test/version_test.dart` fails when it differs from `pubspec.yaml`.
- `.pubignore` replaces `.gitignore` for pub, so build outputs are re-listed there; `docs/`, `GLOSSARY.md`, `*_plan.md`, `test_license.txt`, `.github/` are kept out of the archive (comments in `.pubignore`).
- `lib/oss_licenses.g.dart` and its sidecars are committed and shipped on purpose as a dogfood / sample output (maintainer, 2026-10-24).
- `lib/flutter_oss_manager.dart` exports nothing; the product is the CLI and the generated file.

## Code
- `pubspec.yaml`, `lib/src/version.dart`, `.pubignore`, `CHANGELOG.md`, `README.md`
- `lib/oss_licenses.g.dart`, `lib/oss_licenses_decoder_{stub,io,web}.g.dart`

## Reference behaviour
**None.**

## Cross-cutting invariants
**None.**

## Blast radius
- [generated-files](generated-files.md) — a template change must regenerate the shipped `lib/*.g.dart` too.
- [ci](ci.md) — CI's Flutter pin and the pubspec's SDK floor (`>=3.4.0`) decide the format style ADR-0001 describes.

## Known holes / open
- README's install snippet says `^2.2.0` while the package is at the version in `pubspec.yaml`.
- No release automation; publishing is by hand.
