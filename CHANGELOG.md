# CHANGELOG

## 1.0.0 - 2025-07-02

- Added `description` field to `OssLicense` and included it in generated `oss_licenses.dart`.
- Updated example application to display package version, repository URL, and description.
- Improved license scanning to extract package version and repository URL from `pubspec.lock` and package `pubspec.yaml`.
- Implemented dynamic Flutter SDK path detection for SDK dependencies.
- Added more known license templates (GPL-3.0, LGPL-3.0, MPL-2.0, BSD-2-Clause, ISC) for improved license summarization.

## 0.0.1 - 2025-07-02

- Initial release of `flutter_oss_manager`.
- CLI tool for generating `oss_licenses.dart` from a single license file.
- Basic package scanning and license summarization using Jaccard similarity.
- Support for MIT, Apache-2.0, and BSD-3-Clause license summarization.