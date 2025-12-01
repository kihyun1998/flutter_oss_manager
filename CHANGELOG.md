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