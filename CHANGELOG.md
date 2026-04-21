## 2.0.0

> Upgrade path: **1.1.0 → 2.0.0 direct jump.** 1.2.0 was an internal iteration
> and is not published; its per-license encoding approach is superseded by the
> whole-blob approach below.

* **breaking**: Complete redesign of the generated file. The top-level
  `const List<OssLicense> ossLicenses` is removed. The entire license list
  is now stored as a single gzip+base64-encoded JSON blob, decoded lazily
  via a reference-counted handle API.
* **api**: New surface in the generated file:
  * `OssLicenses.acquire()` returns a `Future<OssLicensesHandle>`.
  * `OssLicensesHandle.licenses` exposes the decoded `List<OssLicense>`.
  * `OssLicensesHandle.close()` releases the reference. When all handles
    are closed, the cache is dropped and becomes GC-eligible.
  * `OssLicense.licenseText` is a plain `String` field (no getter, no
    decode cost at access time).
* **output**: `dart run flutter_oss_manager scan` (or `generate`) now writes
  **4 files** per `--output` target: the main file + 3 platform decoder
  sidecars (`*_decoder_stub.g.dart`, `*_decoder_io.g.dart`,
  `*_decoder_web.g.dart`). Commit all four if you check generated files
  into VCS; deleting any one breaks compilation.
* **default path**: Default `--output` changed to `lib/oss_licenses.g.dart`
  (was `lib/oss_licenses.dart`). The `.g.dart` suffix signals tool-owned
  files. To keep the old path, pass `--output lib/oss_licenses.dart`
  explicitly — the generator falls back to plain `.dart` sidecars in that
  case.
* **headers**: Each generated file starts with a `// GENERATED CODE - DO
  NOT MODIFY BY HAND` marker, the generator version, a `content-hash:
  crc32:XXXXXXXX` fingerprint, and `// ignore_for_file: type=lint`. The
  hash is informational (no runtime verification) but makes tamper/staleness
  diffs obvious in code review and CI.
* **regeneration**: The generator overwrites existing files unconditionally,
  matching `build_runner` conventions. The `.g.dart` suffix is the warning;
  never hand-edit generated files.
* **platforms**: Flutter Web (dart2js and dart2wasm) is supported via
  `dart:js_interop` + browser-native `DecompressionStream`. Requires
  Chrome 80+, Firefox 113+, Safari 16.4+.
* **sdk**: Minimum Dart SDK bumped to 3.4.0 (for stable `dart:js_interop`
  typed-data bridge). Minimum Flutter bumped to 3.22.0.
* **determinism**: Generated gzip output is byte-stable across runs (mtime
  and OS bytes zeroed). VCS diffs stay clean as long as license inputs
  don't change.
* **action required**: Delete your old `oss_licenses.dart` and re-run
  `dart run flutter_oss_manager scan`. Old 1.1.0 generated files do not
  compile against 2.0.0.
* **dev note**: Static cache state survives hot reload. After regenerating
  during development, use **hot restart**, not hot reload.

### Migrating from 1.1.0

**Before:**

```dart
import 'package:your_app/oss_licenses.dart';

ListView.builder(
  itemCount: ossLicenses.length,
  itemBuilder: (c, i) => ListTile(
    title: Text(ossLicenses[i].name),
    subtitle: Text(ossLicenses[i].licenseSummary),
  ),
);
```

**After:**

```dart
import 'package:your_app/oss_licenses.g.dart';

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
  Widget build(BuildContext context) =>
      FutureBuilder<OssLicensesHandle>(
        future: _handle,
        builder: (_, snap) {
          if (!snap.hasData) return const CircularProgressIndicator();
          final licenses = snap.data!.licenses;
          return ListView.builder(
            itemCount: licenses.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(licenses[i].name),
              subtitle: Text(licenses[i].licenseSummary),
            ),
          );
        },
      );
}
```

If you previously used `ossLicenses` from a `StatelessWidget`, convert it
to a `StatefulWidget` (or an `InheritedWidget` / state-management provider)
so the acquired handle can be closed on dispose.

If you prefer one-time eager loading at app startup:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final handle = await OssLicenses.acquire();
  runApp(MyApp(licensesHandle: handle));
}
```

## 1.1.0

* **fix**: CLI tool이 dart:ui를 사용하지 않도록 수정하여 `dart run` 명령어로 정상 실행 가능하도록 개선

## 1.0.2

* **feat**: Added prominent warnings for potentially problematic licenses (GPL, LGPL, AGPL) during scan.

## 1.0.1

* Added comprehensive Dartdoc comments to public API elements to improve documentation score on pub.dev.

## 1.0.0

* **Initial release of `flutter_oss_manager`.**
* Implemented CLI for scanning dependencies and generating a `oss_licenses.dart` file.
* Features a two-tier license detection system (Heuristic and Similarity-based) for high accuracy.
* Supports a wide range of licenses including MIT, Apache, BSD, GPL, LGPL, and MPL.
* Extracts comprehensive package details like version, description, and repository URL.
* Automatically handles Flutter SDK licenses.