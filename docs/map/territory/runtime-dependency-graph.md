# runtime-dependency-graph

## What it is
The `--runtime-only` filter: a BFS over `dependencies:` from the root pubspec that decides which `pubspec.lock` entries ship with the app (glossary: *Runtime dependency graph*).

## Governing decisions
**None.** Designed in `v2_2_plan.md` (draft plan, Korean); no decision record.

## Design model
From the glossary, the plan and the source:
- Follows `dependencies:` only, at every node; `dev_dependencies:` and `dependency_overrides:` are never followed. Applying it only at the root would leak a runtime package's dev tools.
- A package reachable from both a runtime and a dev path stays (README "Shared packages are still included").
- The walker depends only on `PubspecReader`; `FilePubspecReader` delegates location to `PackageLocator`. An unreadable pubspec makes the package a leaf: included, not descended — the conservative choice.
- The root project itself is not in the result.

## Code
- `lib/src/dependency_graph.dart — PubspecReader, RuntimeDependencyGraph.compute, RuntimeDependencyGraph._extractDependencyNames, FilePubspecReader.read`
- `lib/src/license_generator.dart — LicenseGenerator.filterToRuntimeEntries`
- Tests: `test/dependency_graph_test.dart`, `test/dependency_graph_e2e_test.dart`, `test/file_pubspec_reader_test.dart`, `test/runtime_filter_test.dart`

## Reference behaviour
**None.**

## Cross-cutting invariants
**None.**

## Blast radius
- [package-location](package-location.md) — every pubspec it reads is located there; a wrong path prunes silently.
- [flutter-sdk-probe](flutter-sdk-probe.md) — SDK packages are only descended into when the probe found a root.
- [scan-pipeline](scan-pipeline.md) — the filtered list replaces the entry list.

## Known holes / open
- pub workspaces are not supported: one root `pubspec.yaml` is assumed (README).
- A `dependencies:` name absent from `pubspec.lock` is skipped without a note (`compute`: `lockEntry is! YamlMap → continue`).
