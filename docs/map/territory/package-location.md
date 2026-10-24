# package-location

## What it is
`PackageLocator`: the single authority on where a dependency's source lives on disk, for every `pubspec.lock` source type (glossary: *PackageLocator*).

## Governing decisions
**None.** The glossary entry states the rule; no decision record.

## Design model
From the glossary and the source:
- Returns directories only; which files count as a license or manifest is the caller's concern.
- Receives pub-cache and Flutter-SDK roots pre-computed; never reads env vars or spawns a process.
- hosted → `<pub-cache>/hosted/pub.dev/<name>-<version>`; path → `description.path`, joined to the project root when `relative: true`; git → `<pub-cache>/git/<name>-<resolved-ref>/<description.path>`; sdk → `<sdk>/packages/<name>` else `<sdk>/bin/cache/pkg/<name>` (for `sky_engine`), chosen by a `pubspec.yaml` being present.
- Existence is checked only for sdk.

## Code
- `lib/src/package_locator.dart — PackageLocator.packageRootDir, PackageLocator._sdkDir`
- Tests: `test/package_locator_test.dart`

## Reference behaviour
**None.** The pub-cache layout is pub's, not compared against a pinned source.

## Cross-cutting invariants
**None.**

## Blast radius
- [scan-pipeline](scan-pipeline.md) — assumes a non-null hosted dir may not exist and probes license files inside it.
- [runtime-dependency-graph](runtime-dependency-graph.md) — `FilePubspecReader` treats a `null` dir as a leaf, so a wrong path silently prunes the runtime set.

## Known holes / open
- The hosted host is hard-coded to `pub.dev`; packages from another hosted server (private registry, `pub.flutter-io.cn` mirror) are not found. Tracked: #18
- The git checkout path `<name>-<resolved-ref>` is from pub's layout as read by the author (comment in `packageRootDir`), not checked against pub's source.
