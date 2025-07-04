import '../template_license_info.dart';

class MITLicenseInfo extends TemplateLicenseInfo {
  @override
  String get licenseId => 'MIT';

  @override
  List<RegExp> get patterns => [
        RegExp(r'MIT License', caseSensitive: false),
        RegExp(r'Permission is hereby granted, free of charge',
            caseSensitive: false),
        RegExp(r'THE SOFTWARE IS PROVIDED "AS IS"', caseSensitive: false),
        RegExp(r'WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED',
            caseSensitive: false),
      ];

  @override
  int get minMatches => 2;

  @override
  List<String> get uniqueKeywords =>
      ["Permission is hereby granted, free of charge"];

  @override
  List<String> get excludeKeywords => ["BSD", "ISC"];

  @override
  int get priority => 10; // 높은 우선순위

  @override
  String get licenseText => r'''
MIT License

Copyright (c) [year] [fullname]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';
}
