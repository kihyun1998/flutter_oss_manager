<!-- grill-map build stamp: 8e5a943 -->
<!-- grill-map synced at: b99a0d5 (2026-10-24) -->

# Map — flutter_oss_manager

The territory map. A comment's why, trap and measured value go to a note here. Notes are added as they come up, or all at once with `grill-map`, which also reads hand-written notes as leads and keeps their paths.

## The two questions

- **If I touch this, what else moves?** Open the territory and follow `## Blast radius`, then `## Cross-cutting invariants`.
- **What decision is this shape derived from?** Open the territory's `## Governing decisions`. A **None.** is the answer: nothing recorded; the design model says where its rules come from.

## How to read it

`## Blast radius` is a checklist; an edge with nothing to do is a correct outcome. Every claim carries its evidence (a symbol, a record, a commit) or its source and date. Symbols, never line numbers. Empty sections hold **None.**. Source files and issues are text inside notes, not nodes.

## Shape

A single-package Dart CLI with no public library API: `bin/` parses flags, `LicenseGenerator` orchestrates a scan of `pubspec.lock`, each hosted package's SPDX id comes from cache → pub.dev → a template matcher, and a pure renderer emits four `.g.dart` files whose runtime half is a string template only `example/` compiles and tests. The largest gaps: `path`/`git` dependencies are dropped from the output, and cached heuristic answers are never re-asked of pub.dev.

## Territories

- [cli](territory/cli.md)
- [scan-pipeline](territory/scan-pipeline.md)
- [package-location](territory/package-location.md)
- [runtime-dependency-graph](territory/runtime-dependency-graph.md)
- [flutter-sdk-probe](territory/flutter-sdk-probe.md)
- [spdx-resolution](territory/spdx-resolution.md)
- [license-cache](territory/license-cache.md)
- [pub-dev-lookup](territory/pub-dev-lookup.md)
- [license-matcher](territory/license-matcher.md)
- [license-templates](territory/license-templates.md)
- [copyleft-warning](territory/copyleft-warning.md)
- [generated-files](territory/generated-files.md)
- [generated-runtime](territory/generated-runtime.md)
- [example-app](territory/example-app.md)
- [publishing](territory/publishing.md)
- [ci](territory/ci.md)

## Invariants

- [spdx-identifier-spelling](invariant/spdx-identifier-spelling.md)
- [payload-schema](invariant/payload-schema.md)

## Scope

Out of scope: `v2_plan.md`, `v2_1_plan.md`, `v2_2_plan.md` (design history; notes cite them as sources), and `test_license.txt` (nothing but `.pubignore` names it). A territory appears when something in the repo commits to it — code, a decision record, or an open issue with a design; an absent note means nothing has yet.
