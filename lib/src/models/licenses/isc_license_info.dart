import '../template_license_info.dart';

/// Represents the ISC License template information for license detection.
class ISCLicenseInfo extends TemplateLicenseInfo {
  @override
  String get licenseId => 'ISC';

  @override
  List<RegExp> get patterns => [
        RegExp(r'ISC License', caseSensitive: false),
        RegExp(r'Permission to use, copy, modify, and/or distribute',
            caseSensitive: false),
        RegExp(r'THE SOFTWARE IS PROVIDED "AS IS"', caseSensitive: false),
        RegExp(r'THE AUTHOR DISCLAIMS ALL WARRANTIES', caseSensitive: false),
      ];

  @override
  int get minMatches => 2;

  @override
  List<String> get uniqueKeywords =>
      ["Permission to use, copy, modify, and/or distribute"];

  @override
  int? get maxLength => 1000; // ISC is very short

  @override
  int get priority => 10; // 높은 우선순위

  @override
  String get licenseText => r'''
ISC License

Copyright (c) [year] [fullname]

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
''';
}
