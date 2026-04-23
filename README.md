# Flutter OSS Manager

[![pub package](https://img.shields.io/pub/v/flutter_oss_manager.svg)](https://pub.dev/packages/flutter_oss_manager)

A CLI tool that scans open-source licenses in your Flutter project and generates a Dart file containing all license information.

## Installation

Add to `dev_dependencies` in your `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_oss_manager: ^2.2.0
```

```bash
flutter pub get
```

## Commands

### `scan` — Scan project dependency licenses

Reads `pubspec.lock`, analyzes licenses for all dependencies, and generates an `oss_licenses.g.dart` file (plus 3 platform decoder sidecars).

```bash
dart run flutter_oss_manager scan
```

**Options:**

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--output` | `-o` | Output file path (main file; 3 sidecars are derived) | `lib/oss_licenses.g.dart` |
| `--offline` |  | Skip pub.dev; use cache + heuristic only | off |
| `--refresh-cache` |  | Clear the cache and re-fetch everything | off |
| `--no-cache` |  | Do not read or write the cache file | off |
| `--runtime-only` |  | Scan only packages reachable from the root `dependencies:` — excludes `dev_dependencies` and their transitives | off |

```bash
dart run flutter_oss_manager scan --output lib/src/licenses.g.dart
```

**What it does:**

1. Reads dependencies from `pubspec.lock`. With `--runtime-only`, the list
   is filtered to packages reachable from the root `dependencies:` section
   (dev tooling and its transitives are excluded).
2. Finds license files (`LICENSE`, `COPYING`, etc.) in the Pub cache for each package.
3. Includes licenses for Flutter SDK packages (`flutter`, `flutter_test`, `sky_engine`).
4. Identifies the license type via the pipeline below (pub.dev → heuristic).
5. Warns if GPL/LGPL/AGPL licenses are detected.
6. Generates the result as a Dart file.

### License Detection

For each hosted package, the SPDX license identifier is resolved through a
3-stage fallback pipeline:

1. **Cache** — `.dart_tool/flutter_oss_manager/pub_license_cache.json`, keyed
   by `<name>@<version>`. Hits return immediately with zero network traffic.
   Bumping a package version in `pubspec.lock` naturally invalidates its
   entry; no manual cache-busting needed.
2. **pub.dev API** — `GET https://pub.dev/api/packages/<name>/score`. The
   SPDX identifier is extracted from the `tags` array (`license:mit`,
   `license:bsd-3-clause`, …). Classifier-only tags (`license:fsf-libre`,
   `license:osi-approved`) are filtered out. Successful results are cached.
3. **Heuristic** — Falls back to pattern/similarity matching against the
   bundled license templates (the 2.0.x behavior). Used when pub.dev is
   unreachable, the package isn't on pub.dev, the user passed `--offline`,
   or `--no-cache` was set.

SDK packages (`flutter`, `flutter_test`, `sky_engine`) always use the
heuristic — pub.dev doesn't analyze them.

Each package prints its source in the scan log, so mis-identifications are
easy to attribute:

```
- args (2.4.2) [hosted]
  → BSD-3-Clause [cache]
- path (1.9.0) [hosted]
  → BSD-3-Clause [pub-api]
- my_internal_pkg (1.0.0) [hosted]
  → MIT [heuristic]
- obscure (0.0.1) [hosted]
  → Unknown [negative]
```

The cache directory (`.dart_tool/`) is ignored by default `flutter create`
`.gitignore` files, so the cache never ends up in version control. If you
want to share the cache across CI builds, add
`.dart_tool/flutter_oss_manager/` to your CI cache key.

**Privacy note:** On first run (or `--refresh-cache`), the package names
from `pubspec.lock` are sent to pub.dev to look up license metadata. These
names are already public, but if your build environment must not reach the
internet, pass `--offline`.

### Excluding dev dependencies

By default, `scan` walks every entry in `pubspec.lock`, which includes
`dev_dependencies` and their transitive packages (e.g. `build_runner`,
`flutter_lints`, `test`, `analyzer`, `leak_tracker`). These tools are not
bundled with your released app, and usually don't need to appear in
user-facing license notices.

To limit the scan to packages that actually ship with your app:

```bash
dart run flutter_oss_manager scan --runtime-only
```

This performs a dependency graph walk starting from the `dependencies:`
section of your project's root `pubspec.yaml`, following each package's own
`dependencies:` recursively. `dev_dependencies:` and
`dependency_overrides:` are ignored at every level of the graph, not just
at the root.

**Shared packages are still included.** If a package is reachable from
*both* a runtime and a dev path (for example, `collection` is used by
Flutter itself *and* by `test`), it stays in the output — it ships with
your app either way.

The log shows how many packages were kept vs. skipped:

```
Scanning packages for licenses...
Runtime-only mode: keeping 24 packages, skipping 20 dev/dev-transitive packages.
- characters (1.4.0) [hosted]
  → BSD-3-Clause [cache]
...
```

The graph walker resolves pubspecs for every source type your lockfile can
produce: `hosted` (pub cache), `sdk` (Flutter SDK, including the
`sky_engine` fallback location), `path` (resolved relative to the project
root), and `git` (pub cache git checkouts).

**Known limitations:**

- **pub workspaces** (Dart 3.6+ `resolution: workspace`) are not yet
  supported — the walker assumes a single root `pubspec.yaml`. File an
  issue if you need this.
- The `PUB_CACHE` environment variable is ignored; the default pub cache
  location is used. This matches the existing `scan` behavior.

### `generate` — Convert a single license file

Reads a single license file and converts it to a Dart file. Useful for including your own project's license.

```bash
dart run flutter_oss_manager generate --license-file LICENSE --output lib/my_license.dart
```

**Options:**

| Option | Short | Description | Required |
|--------|-------|-------------|----------|
| `--license-file` | `-l` | Path to the license file | Yes |
| `--output` | `-o` | Output file path (main file; 3 sidecars are derived) | No (default: `lib/oss_licenses.g.dart`) |

### Global Options

| Option | Short | Description |
|--------|-------|-------------|
| `--verbose` | `-v` | Enable verbose output |

## Generated File Structure

The generator emits **four files** per `--output` target: one main file plus
three platform-specific decoder sidecars. For the default output path
`lib/oss_licenses.g.dart`:

```
lib/
  oss_licenses.g.dart                  # public API + encoded payload (import this)
  oss_licenses_decoder_stub.g.dart     # fallback that throws UnsupportedError
  oss_licenses_decoder_io.g.dart       # dart:io gzip implementation
  oss_licenses_decoder_web.g.dart      # dart:js_interop + DecompressionStream
```

Each file starts with a tool-owned header:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: 2.0.0
// content-hash: crc32:a1b2c3d4
// ignore_for_file: type=lint
```

- `content-hash` is a CRC32 of the file body and changes whenever the
  generator's input (your license list) changes. It's informational —
  there's no runtime enforcement — but makes tamper/staleness diffs stand
  out in code review.
- `type=lint` disables all lint checks for generated files (payload lines
  are inherently long).
- Regenerating overwrites existing files silently, matching `build_runner`
  conventions. The `.g.dart` suffix is the warning; don't hand-edit.

The main file selects a decoder at compile time via conditional imports. **Only
import the main file in your app code** — never reference the sidecar files
directly. If you use VCS, commit all four together; deleting any one breaks
compilation.

The main file exposes:

```dart
class OssLicense {
  final String name;           // Package name
  final String version;        // Version
  final String licenseText;    // Full license text (plain String, zero-cost read)
  final String licenseSummary; // License type (e.g., "MIT", "Apache-2.0")
  final String? repositoryUrl; // Repository URL
  final String? description;   // Package description
}

class OssLicensesHandle {
  List<OssLicense> get licenses;
  void close();                // Idempotent; releases refcount
}

class OssLicenses {
  static Future<OssLicensesHandle> acquire();  // Decode lazily, refcounted
  static void resetForTest();                  // Test-only
}
```

### Memory behavior

The entire license list is stored as a **single gzip+base64-encoded JSON blob**
in a `const String`. At startup, only this compact string (tens to hundreds
of KB, depending on project size) is resident. Nothing is decoded until you
call `OssLicenses.acquire()`.

`acquire()` decodes the blob once and hands out a reference-counted
`OssLicensesHandle`. Concurrent callers share the same decoded list. When
all handles are closed, the cache is dropped and the decoded strings become
garbage-collectable. The lifecycle is under your control, not the library's.

Typical pattern:

- `acquire()` when entering a license screen or dialog.
- `close()` on dispose, to release memory when the user navigates away.

The lifecycle is all-or-nothing: either the list is loaded (fully) or not.
There is no per-license lazy field access. This gives you predictable GC
behavior and zero per-access cost, at the price of explicit lifecycle
management.

### Dev note: hot reload

`OssLicenses` caches state in static fields, which survive hot reload. After
regenerating `oss_licenses.g.dart` during development, use **hot restart** (not
hot reload) so the new payload takes effect.

## Platform support

| Platform | Supported | Notes |
|---|---|---|
| iOS / Android | Yes | `dart:io` gzip |
| macOS / Windows / Linux (desktop) | Yes | `dart:io` gzip |
| Flutter Web (dart2js) | Yes | `DecompressionStream`; Chrome 80+, Firefox 113+, Safari 16.4+ |
| Flutter Web (dart2wasm) | Yes | Same browser floor as dart2js |
| Dart native CLI / VM | Yes | `dart:io` gzip |

Dart SDK floor: **3.4.0**. Flutter SDK floor: **3.22.0**.

## Usage in Your App

```dart
import 'package:your_project/oss_licenses.g.dart';

class LicensePage extends StatefulWidget {
  const LicensePage({super.key});
  @override
  State<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends State<LicensePage> {
  late final Future<OssLicensesHandle> _handle = OssLicenses.acquire();

  @override
  void dispose() {
    _handle.then((h) => h.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Licenses')),
        body: FutureBuilder<OssLicensesHandle>(
          future: _handle,
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final licenses = snap.data!.licenses;
            return ListView.builder(
              itemCount: licenses.length,
              itemBuilder: (_, i) {
                final l = licenses[i];
                return ListTile(
                  title: Text('${l.name} v${l.version}'),
                  subtitle: Text(l.licenseSummary),
                  // l.licenseText is a plain String field — access is free
                  // once the handle is resolved.
                );
              },
            );
          },
        ),
      );
}
```

Multiple screens/subsystems can call `acquire()` concurrently — the decoded
list is shared via refcount. The cache is released only after every caller
has called `close()`.

### Migrating from 1.1.0

The top-level `const ossLicenses` list is gone. Replace direct list access
with the handle pattern shown above. If you previously used `ossLicenses`
inside a `StatelessWidget`, convert it to a `StatefulWidget` (or an
`InheritedWidget` / state-management provider) so the handle can be closed
on dispose.

For one-time eager loading at app startup:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final handle = await OssLicenses.acquire();
  runApp(MyApp(licensesHandle: handle));
}
```

## License Detection

Licenses are identified in two stages:

1. **Heuristic matching**: Uses regex patterns and keywords for fast, high-confidence identification.
2. **Similarity matching (fallback)**: If heuristic matching fails, compares against license templates using Jaccard similarity.

**Supported licenses:** MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, BSD-4-Clause, ISC, GPL-2.0, GPL-3.0, LGPL-2.1, LGPL-3.0, MPL-2.0

## License Warnings

When GPL, LGPL, or AGPL licenses are detected, a warning is displayed in the scan output. These licenses may impose source code disclosure obligations that could affect commercial software.

## Limitations

- Only scans Dart/Flutter dependencies. Native dependencies from Gradle (Android) or CocoaPods (iOS) are not included.
- Non-standard or heavily modified license files may not be identified correctly.
- On Flutter Web, browsers older than Chrome 80 / Firefox 113 / Safari 16.4 lack the `DecompressionStream` API required by the generated decoder.

## License

[MIT License](LICENSE)
