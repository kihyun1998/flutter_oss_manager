# Flutter OSS Manager

[![pub package](https://img.shields.io/pub/v/flutter_oss_manager.svg)](https://pub.dev/packages/flutter_oss_manager)

A CLI tool that scans open-source licenses in your Flutter project and generates a Dart file containing all license information.

## Installation

Add to `dev_dependencies` in your `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_oss_manager: ^1.1.0
```

```bash
flutter pub get
```

## Commands

### `scan` — Scan project dependency licenses

Reads `pubspec.lock`, analyzes licenses for all dependencies, and generates an `oss_licenses.dart` file.

```bash
dart run flutter_oss_manager scan
```

**Options:**

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--output` | `-o` | Output file path | `lib/oss_licenses.dart` |

```bash
dart run flutter_oss_manager scan --output lib/src/licenses.dart
```

**What it does:**

1. Reads all dependencies (hosted, sdk) from `pubspec.lock`.
2. Finds license files (`LICENSE`, `COPYING`, etc.) in the Pub cache for each package.
3. Includes licenses for Flutter SDK packages (`flutter`, `flutter_test`, `sky_engine`).
4. Identifies the license type automatically.
5. Warns if GPL/LGPL/AGPL licenses are detected.
6. Generates the result as a Dart file.

### `generate` — Convert a single license file

Reads a single license file and converts it to a Dart file. Useful for including your own project's license.

```bash
dart run flutter_oss_manager generate --license-file LICENSE --output lib/my_license.dart
```

**Options:**

| Option | Short | Description | Required |
|--------|-------|-------------|----------|
| `--license-file` | `-l` | Path to the license file | Yes |
| `--output` | `-o` | Output file path | No (default: `lib/oss_licenses.dart`) |

### Global Options

| Option | Short | Description |
|--------|-------|-------------|
| `--verbose` | `-v` | Enable verbose output |

## Generated File Structure

The generated Dart file contains:

```dart
class OssLicense {
  final String name;           // Package name
  final String version;        // Version
  final String licenseSummary; // License type (e.g., "MIT", "Apache-2.0")
  final String? repositoryUrl; // Repository URL
  final String? description;   // Package description

  String get licenseText;      // Full license text (decoded on access)
}

const List<OssLicense> ossLicenses = [ ... ];
```

License text is stored gzip+base64 encoded inside the generated file to
minimise resident memory. The `licenseText` getter decodes on each call,
producing a fresh, garbage-collectable `String` that is released when the
caller drops its reference.

> **Platform note:** The generated file imports `dart:io` for gzip decoding
> and is **not compatible with Flutter Web**. Use on mobile, desktop, or
> standalone Dart VM targets.

## Usage in Your App

Import the generated file and display the license list:

```dart
import 'package:your_project/oss_licenses.dart';

ListView.builder(
  itemCount: ossLicenses.length,
  itemBuilder: (context, index) {
    final license = ossLicenses[index];
    return ListTile(
      title: Text('${license.name} v${license.version}'),
      subtitle: Text(license.licenseSummary),
      onTap: () {
        // Navigate to a detail page showing license.licenseText
      },
    );
  },
);
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

## License

[MIT License](LICENSE)
