# Context — flutter_oss_manager

Domain glossary for this project. Skills and contributors should use these terms
(not synonyms) when naming modules, tests, issues, and proposals.

## Purpose

A Flutter package + CLI that scans a project's dependencies, identifies each
dependency's open-source license, and generates a Dart file embedding that
license information for use at runtime.

## Glossary

### License template

A built-in description of one known license type (MIT, Apache-2.0, GPL-3.0, …)
under `lib/src/models/licenses/`, implementing `TemplateLicenseInfo`. Carries the
patterns, keywords, and priority used to heuristically identify a license.

### License matcher

Decides which SPDX identifier a raw license text corresponds to. The pure
top-level `matchLicense(text)` scores the text against the license templates
(heuristic) and, as a fallback, by Jaccard paragraph similarity, returning a
`MatchResult { spdx, method, confidence }` — a decision record, never printing.
`MatchMethod` is `heuristic`, `similarity`, or `none` (the `Unknown` outcome).

### SPDX resolution

The 3-stage pipeline that turns a package + its license text into a canonical
SPDX identifier: cache → pub.dev API → license matcher (heuristic). Lives on
`LicenseGenerator._resolveSpdx`.

### PackageLocator

The single authority on **where a dependency's source lives on disk**. Given a
package name and its `pubspec.lock` entry, it resolves the package's root
`Directory` for every pub source type (hosted, sdk, path, git), and exposes the
environment roots (`pubCacheDir`, `flutterSdkRoot`). Both the license scanner and
the `PubspecReader` obtain package locations through it, so filesystem-layout
knowledge (e.g. `hosted/pub.dev/<name>-<version>`) lives in exactly one place.
Returns directories only; deciding which files inside a directory count as
licenses is a license-domain concern, not a location concern.

### GeneratedFiles

The four Dart files this tool emits: the main file (embedding the license payload
+ lifecycle controller) plus three platform decoder sidecars (stub / io / web).
Produced as **data** by a pure renderer (`renderGeneratedFiles`), so the file
format is verifiable without writing to disk; the caller performs the actual
write. Each file's content already has its `content-hash` (crc32) embedded.

### Runtime dependency graph

The BFS over `dependencies:` (never `dev_dependencies:`) from the root pubspec,
used by `--runtime-only` to exclude dev-only packages and their transitives.
Depends on the `PubspecReader` seam, never on the filesystem directly.
