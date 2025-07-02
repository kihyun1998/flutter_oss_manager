# flutter_oss_manager

A Flutter package and command-line interface (CLI) for scanning and summarizing open-source licenses of your project's dependencies, and generating a Dart file containing this information.

This tool aims to simplify the process of complying with open-source license requirements by automatically identifying license types and providing a structured way to include them in your Flutter application.

## Features

- **CLI Tool**: A command-line interface to automate license scanning and Dart file generation.
- **Dependency Scanning**: Scans `pubspec.yaml` and `pubspec.lock` to identify all direct and transitive Dart/Flutter dependencies.
- **License File Discovery**: Automatically locates common license files (e.g., `LICENSE`, `LICENSE.txt`, `COPYING`) within package directories in the Pub cache.
- **SDK License Handling**: Identifies and includes license information for Flutter SDK dependencies (e.g., `flutter`, `flutter_test`).
- **License Summarization**: Uses Jaccard similarity to compare discovered license texts against a set of known license templates (MIT, Apache 2.0, BSD 2-Clause, BSD 3-Clause, ISC, GPL-3.0, LGPL-3.0, MPL-2.0) to provide a concise summary (e.g., "MIT", "Apache-2.0").
- **Dart File Generation**: Generates a `oss_licenses.dart` file containing a list of `OssLicense` objects, each including:
    - `name`: Package name
    - `version`: Package version
    - `licenseText`: Full license content
    - `licenseSummary`: Summarized license type
    - `repositoryUrl`: Package repository URL (if available)
    - `description`: Package description (if available)

## Installation

To use the `flutter_oss_manager` CLI, add it as a dev dependency in your `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_oss_manager:
    path: <path_to_flutter_oss_manager>
  # Or, if publishing to pub.dev:
  # flutter_oss_manager: ^1.0.0
```

Then, run `flutter pub get`:

```bash
flutter pub get
```

## Usage

### Generating `oss_licenses.dart`

#### 1. Scan Project Dependencies

Navigate to your Flutter project's root directory and run the `scan` command:

```bash
dart run flutter_oss_manager scan
```

This will scan your `pubspec.yaml` and `pubspec.lock` files, discover license information for your dependencies, and generate `lib/oss_licenses.dart` by default.

You can specify a custom output path using the `-o` or `--output` option:

```bash
dart run flutter_oss_manager scan -o path/to/your/licenses.dart
```

#### 2. Generate from a Single License File

If you have a specific license file you want to include (e.g., for your own project's license), you can use the `generate` command:

```bash
dart run flutter_oss_manager generate -l path/to/your/LICENSE.txt -o lib/my_project_license.dart
```

### Integrating into Your Flutter App

After generating `oss_licenses.dart`, you can import it into your Flutter application and display the license information. Here's a basic example:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:your_project_name/oss_licenses.dart'; // Adjust import path as needed

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
                  if (license.description != null) Text(license.description!),
                  if (license.repositoryUrl != null) Text(license.repositoryUrl!),
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

## Known Limitations and Future Work

- **Native Dependencies**: This tool currently focuses on Dart/Flutter package dependencies. Licenses for native Android (Gradle) or iOS (CocoaPods) libraries are not scanned.
- **Comprehensive License Templates**: While several common licenses are included, the accuracy of license summarization depends on the completeness of the known license templates. More templates can be added to improve detection.

## Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.

## License

This package is licensed under the [MIT License](LICENSE).