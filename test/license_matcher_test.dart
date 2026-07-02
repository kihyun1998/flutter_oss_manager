import 'package:flutter_oss_manager/src/license_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// A multi-paragraph MIT body the heuristic recognizes (same text the SPDX
/// pipeline test uses, kept independent here as a known-good input).
const _mitText = '''
MIT License

Copyright (c) 2020 Foo

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

void main() {
  test('recognizes a real MIT license via the heuristic path', () {
    final r = matchLicense(_mitText);
    expect(r.spdx, 'MIT');
    expect(r.method, MatchMethod.heuristic);
    expect(r.confidence, greaterThan(0));
  });

  test('gibberish with no license signal → Unknown via none', () {
    final r = matchLicense('gibberish content with no license pattern abc xyz');
    expect(r.spdx, 'Unknown');
    expect(r.method, MatchMethod.none);
  });

  test('empty text → Unknown via none with zero confidence', () {
    final r = matchLicense('');
    expect(r.spdx, 'Unknown');
    expect(r.method, MatchMethod.none);
    expect(r.confidence, 0.0);
  });

  // NOTE: MatchMethod.similarity (the >0.5 Jaccard-fallback success path) has
  // no direct unit test here. Triggering it deterministically requires a text
  // that stays below every template's heuristic threshold yet is textually
  // similar to one — a brittle, near-tautological input to craft. The branch
  // is ported verbatim from the prior implementation and stays exercised
  // indirectly through resolve_spdx_test.dart.
}
