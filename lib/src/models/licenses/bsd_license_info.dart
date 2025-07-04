import '../template_license_info.dart';

/// Represents the BSD 4-Clause License template information for license detection.
class BSD4ClauseLicenseInfo extends TemplateLicenseInfo {
  @override
  String get licenseId => 'BSD-4-Clause';

  @override
  List<RegExp> get patterns => [
        RegExp(r'BSD 4-Clause License', caseSensitive: false),
        RegExp(r'All advertising materials mentioning features',
            caseSensitive: false),
        RegExp(r'This product includes software developed by',
            caseSensitive: false),
        RegExp(r'Neither the name of the copyright holder',
            caseSensitive: false),
      ];

  @override
  int get minMatches => 2;

  @override
  List<String> get uniqueKeywords =>
      ["All advertising materials mentioning features"];

  @override
  int get priority => 10;

  @override
  String get licenseText => r'''
BSD 4-Clause License

Copyright (c) [year], [fullname]
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. All advertising materials mentioning features or use of this software must
   display the following acknowledgement:
     This product includes software developed by [project].

4. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY COPYRIGHT HOLDER "AS IS" AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
EVENT SHALL COPYRIGHT HOLDER BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
''';
}

/// Represents the BSD 3-Clause License template information for license detection.
class BSD3ClauseLicenseInfo extends TemplateLicenseInfo {
  @override
  String get licenseId => 'BSD-3-Clause';

  @override
  List<RegExp> get patterns => [
        RegExp(r'Neither the name of.*nor the names of its contributors',
            caseSensitive: false),
        RegExp(r'Redistribution and use in source and binary forms',
            caseSensitive: false),
        RegExp(r'without specific prior written permission',
            caseSensitive: false), // 3번째 조항의 끝부분
      ];

  @override
  int get minMatches => 2;

  @override
  List<String> get uniqueKeywords => [
        "Neither the name of",
        "nor the names of its contributors",
        "without specific prior written permission"
      ];

  @override
  List<String> get excludeKeywords => ["All advertising materials"];

  @override
  int get priority => 15;

  @override
  String get licenseText => r'''
BSD 3-Clause License

Copyright (c) [year], [fullname]

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
''';
}

/// Represents the BSD 2-Clause License template information for license detection.
class BSD2ClauseLicenseInfo extends TemplateLicenseInfo {
  @override
  String get licenseId => 'BSD-2-Clause';

  @override
  List<RegExp> get patterns => [
        RegExp(r'BSD 2-Clause License', caseSensitive: false),
        RegExp(r'Redistribution and use in source and binary forms',
            caseSensitive: false),
        RegExp(r'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS',
            caseSensitive: false),
      ];

  @override
  int get minMatches => 2;

  @override
  List<String> get excludeKeywords => [
        "Neither the name of", // 더 짧게 해서 확실히 감지
        "All advertising materials"
      ];

  @override
  int get priority => 20; // BSD-3보다 낮은 우선순위

  @override
  String get licenseText => r'''
BSD 2-Clause License

Copyright (c) [year], [fullname]

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
''';
}
