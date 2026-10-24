# example-app

## What it is
`example/`: a Flutter app that path-depends on this package, renders the license list, and is the only place the generated runtime is compiled and tested.

## Governing decisions
**None.**

## Design model
From the source and `.github/workflows/ci.yml`:
- A separate package; CI runs its own `pub get`, `analyze`, `test` because the root job does not cover it (CI comment).
- Commits its generated `.g.dart` files; `test/generated_integrity_test.dart` (root) checks their hashes.
- `lib/main.dart` uses `acquire()` in `initState`-style `late final` and closes in `dispose`.
- Pins Riverpod 2.x (issue #8).

## Code
- `example/lib/main.dart — LicenseListPage`
- `example/lib/oss_licenses*.g.dart`
- `example/test/oss_licenses_use_test.dart`

## Reference behaviour
**None.**

## Cross-cutting invariants
**None.**

## Blast radius
- [generated-runtime](generated-runtime.md) — its tests are that code's only coverage.
- [ci](ci.md) — the `example` job builds it with the pinned Flutter.

## Known holes / open
- Riverpod majors are to be kept out of automated update PRs (issue #8, not built).
