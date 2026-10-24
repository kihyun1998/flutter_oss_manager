# scan-pipeline

## What it is
`LicenseGenerator.scanPackages`: the orchestration of one `scan` — read `pubspec.lock`, optionally filter to runtime packages, find each package's license file, resolve its SPDX id, warn on copyleft, write the generated files.

## Governing decisions
**None.** The glossary ([GLOSSARY.md](../../../GLOSSARY.md)) names the parts; no decision record governs the orchestration.

## Design model
From reading the source:
- Packages are processed in fixed batches of `_concurrency` (default 8) with `Future.wait`; results land by index so output order equals `pubspec.lock` order regardless of completion order.
- Each package's `print`s are captured in a zone (`_scanOne`) and flushed as one write, so parallel workers do not interleave log lines.
- Only `hosted` and `sdk` sources produce a license. Every other source prints `[unknown source: …]` and yields `null`, so the package is absent from the generated file.
- Hosted: the license file is the first of `_licenseFileNames` (`LICENSE`, `LICENSE.txt`, `COPYING`, `COPYING.txt`, `LICENCE`, `LICENCE.txt`) present in the package root; `repositoryUrl` is pubspec `repository` falling back to `homepage`.
- SDK: every SDK package gets the license at `<flutter root>/LICENSE` and the framework version; `flutter`, `flutter_test`, `sky_engine` get hard-coded repository URLs and descriptions.
- The Flutter SDK is probed only when `runtimeOnly` is set or an SDK package is met (CHANGELOG 2.3.0, `scanPackages` comment).
- The pub client is `close()`d in a `finally` after all batches; the cache is saved once after.
- Inputs from outside: `pubspec.lock` and each license file are read whole with no size bound.

## Code
- `lib/src/license_generator.dart — LicenseGenerator.scanPackages, _scanOne, _scanOneInner, _findAndSummarizeHostedLicense, _findAndSummarizeSdkLicense, _getPubCacheDir, _writeGeneratedFiles, generateLicenses`
- Tests: `test/scan_packages_test.dart`, `test/scan_sdk_probe_test.dart`, `test/license_generator_test.dart`

## Reference behaviour
**None.**

## Cross-cutting invariants
- [spdx-identifier-spelling](../invariant/spdx-identifier-spelling.md) — the copyleft check compares `licenseSummary` strings.

## Blast radius
- [spdx-resolution](spdx-resolution.md) — the pipeline is only called from `_findAndSummarizeHostedLicense`; SDK packages bypass it and call the matcher directly.
- [package-location](package-location.md) — the hosted path assumes the locator returns a directory even when it does not exist, and checks for license files itself.
- [flutter-sdk-probe](flutter-sdk-probe.md) — when the probe runs is decided here; an eager probe re-introduces the spurious SDK error on pure-Dart projects (CHANGELOG 2.3.0).
- [copyleft-warning](copyleft-warning.md) — fed from the collected list.
- [generated-files](generated-files.md) — the collected `OssLicense` list is the renderer's only input, in this order.
- [runtime-dependency-graph](runtime-dependency-graph.md) — filters the entry list before batching.

## Known holes / open
- `path` and `git` dependencies are silently dropped from the output, though `PackageLocator` can find them. Not intended (maintainer, 2026-10-24). Tracked: #12
- `PUB_CACHE` is ignored; the cache dir is `$HOME/.pub-cache` or `%LOCALAPPDATA%\Pub\Cache` (`_getPubCacheDir`; README "Known limitations"). A missing `HOME` throws on the `!`. Tracked: #16
- pub workspaces (`resolution: workspace`) are not supported (README "Known limitations"). Tracked: #17
- `generate` and `scanPackages` print errors and return instead of failing; the CLI exits 0 on a missing `pubspec.lock`.
