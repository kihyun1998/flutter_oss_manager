import '../template_license_info.dart';

class MITLicenseInfo extends TemplateLicenseInfo {
  @override
  String get licenseId => 'MIT';

  @override
  List<String> get heuristicKeywords => [
        'permission is hereby granted',
        'the software is provided "as is"',
        'without warranty of any kind',
      ];

  @override
  int get priority => 10; // 높은 우선순위

  @override
  bool matchesHeuristic(String content) {
    final lowerContent = content.toLowerCase();

    // MIT 특화 로직: 핵심 문구들이 모두 포함되어야 함
    return lowerContent.contains('permission is hereby granted') &&
        lowerContent.contains('the software is provided "as is"') &&
        lowerContent.contains('without warranty of any kind') &&
        !lowerContent.contains('copyleft'); // copyleft 라이선스가 아님을 확인
  }

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
