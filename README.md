# Flutter OSS Manager

[![pub package](https://img.shields.io/pub/v/flutter_oss_manager.svg)](https://pub.dev/packages/flutter_oss_manager)

A powerful command-line interface (CLI) to streamline open-source license management in your Flutter projects. It scans all dependencies, identifies their licenses with high accuracy, and generates a single Dart file to easily display license information within your app.

This tool simplifies compliance with open-source licensing requirements, saving you time and effort.

## Key Features

- **Automated CLI Tool**: A robust CLI for scanning dependencies and generating a `oss_licenses.dart` file.
- **Comprehensive Dependency Scanning**: Scans `pubspec.yaml` and `pubspec.lock` to identify all direct and transitive Dart/Flutter dependencies.
- **Accurate License Discovery**: Automatically finds and reads standard license files (`LICENSE`, `COPYING`, etc.) from package directories in the Pub cache.
- **Flutter SDK License Handling**: Correctly identifies and includes licenses for Flutter SDK packages (e.g., `flutter`, `flutter_test`).
- **Advanced Two-Tier License Detection**:
  - **Tier 1: Heuristic Matching**: Uses a sophisticated system of regular expressions, unique keywords, and exclusion rules for high-confidence, precise license identification.
  - **Tier 2: Similarity-Based Fallback**: If heuristic matching is inconclusive, it falls back to Jaccard similarity analysis against a comprehensive database of license templates.
- **Broad License Support**: Detects a wide range of open-source licenses, including:
  - MIT
  - Apache-2.0
  - BSD (2-Clause, 3-Clause, 4-Clause)
  - ISC
  - GPL (v2, v3)
  - LGPL (v2.1, v3)
  - MPL-2.0
- **License Compliance Warnings**: Automatically displays prominent warnings when potentially problematic licenses (GPL, LGPL, AGPL) are detected, helping you avoid legal issues in commercial software.
- **Clean Dart File Generation**: Creates a well-structured `oss_licenses.dart` file with a list of `OssLicense` objects, containing:
    - `name`: Package name
    - `version`: Package version
    - `licenseText`: The full text of the license.
    - `licenseSummary`: A concise summary of the license type (e.g., "MIT", "Apache-2.0").
    - `repositoryUrl`: Link to the package's repository (if available).
    - `description`: The package's description from `pubspec.yaml`.

## Installation

To use the CLI, add `flutter_oss_manager` as a `dev_dependency` in your `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_oss_manager: ^1.0.0 # Replace with the latest version
```

Then, install it by running:

```bash
flutter pub get
```

## Usage

### Scanning Project Dependencies

The primary command is `scan`. Navigate to your project's root directory and run:

```bash
dart run flutter_oss_manager scan
```

This command will:
1. Scan your `pubspec.lock` file.
2. Find the license for each dependency.
3. Generate a summary and the full license text.
4. Create the `lib/oss_licenses.dart` file in your project.

To specify a different output location, use the `--output` (or `-o`) option:

```bash
dart run flutter_oss_manager scan --output path/to/your/licenses.dart
```

### Generating a License for a Single File

The `generate` command is useful for creating a license object from a single license file (e.g., your own project's `LICENSE` file).

```bash
dart run flutter_oss_manager generate --license-file path/to/your/LICENSE --output lib/my_project_license.dart
```

## Integrating into Your Flutter App

After generating `oss_licenses.dart`, you can import and use it to create a license page in your app. Here is a simple example:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:your_project_name/oss_licenses.dart'; // Adjust the import path if needed

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open Source Licenses',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LicenseListPage(),
    );
  }
}

class LicenseListPage extends StatelessWidget {
  const LicenseListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Source Licenses'),
      ),
      body: ListView.builder(
        itemCount: ossLicenses.length,
        itemBuilder: (context, index) {
          final license = ossLicenses[index];
          return Card(
            margin: const EdgeInsets.all(8.0),
            child: ExpansionTile(
              title: Text('${license.name} v${license.version}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(license.licenseSummary),
                  if (license.description != null) Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(license.description!, style: Theme.of(context).textTheme.bodySmall),
                  ),
                  if (license.repositoryUrl != null) Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(license.repositoryUrl!, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(license.licenseText),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

## License Detection Accuracy

This package employs a sophisticated two-tier detection system to ensure high accuracy:

1.  **Heuristic Pattern Matching (Primary)**: Utilizes a combination of regular expressions and unique keywords tailored to each license type. This method provides high-confidence detection for standard, well-formed licenses.
2.  **Similarity-Based Matching (Fallback)**: If the heuristic approach does not yield a confident result, the tool falls back to a Jaccard similarity comparison. It tokenizes the license text and compares it against a database of known license templates.

This dual approach ensures both speed and accuracy, providing robust identification even for licenses with minor variations.

## Known Limitations

- **Native Dependencies**: This tool currently focuses on Dart/Flutter dependencies defined in `pubspec.yaml`. It does not scan licenses for native dependencies from Gradle (Android) or CocoaPods (iOS).
- **Custom License Formats**: While the detection system is robust, heavily modified or non-standard license files may not be identified correctly and might require manual verification.

## Contributing

Contributions are welcome! If you find a bug or have a feature request, please open an issue. If you want to contribute code, please feel free to submit a pull request.

## License

This package is licensed under the [MIT License](LICENSE).
