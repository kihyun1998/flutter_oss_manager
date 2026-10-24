# flutter-sdk-probe

## What it is
Resolves the Flutter SDK root and framework version from one `flutter --version --machine` call, memoized per run (glossary: *Flutter SDK probe*).

## Governing decisions
**None.**

## Design model
From the glossary and the source:
- At most one subprocess per run (`_probed` flag); a failure memoizes `null` too.
- Any failure — non-zero exit, bad JSON, missing key, no `flutter` on PATH — is `null`, never an exception.
- `flutter.bat` on Windows.
- The process call is injectable (`RunProcess`).

## Code
- `lib/src/flutter_sdk_probe.dart — FlutterSdkProbe, ProcessFlutterSdkProbe.probe, ProcessFlutterSdkProbe._resolve`
- Tests: `test/flutter_sdk_probe_test.dart`, `test/scan_sdk_probe_test.dart`

## Reference behaviour
**None.** The `flutterRoot` / `frameworkVersion` keys are Flutter's machine output, not compared against a pinned source.

## Cross-cutting invariants
**None.**

## Blast radius
- [scan-pipeline](scan-pipeline.md) — decides when the probe is called; SDK packages get `null` → no license.
- [runtime-dependency-graph](runtime-dependency-graph.md) — a `null` root makes every SDK package a leaf.

## Known holes / open
**None.**
