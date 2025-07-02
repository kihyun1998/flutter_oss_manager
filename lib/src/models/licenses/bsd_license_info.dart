import '../template_license_info.dart';

class Bsd3ClauseLicenseInfo extends TemplateLicenseInfo {
  @override
  String get licenseId => 'BSD-3-Clause';

  @override
  List<String> get heuristicKeywords => [
        'redistribution and use in source and binary forms',
        'neither the name of the copyright holder nor the names of its contributors may be used',
      ];

  @override
  int get priority => 15; // BSD-3 이 BSD-2 보다 더 구체적이므로 높은 우선순위

  @override
  bool matchesHeuristic(String content) {
    final lowerContent = content.toLowerCase();

    // BSD-3-Clause 특화 로직
    return lowerContent
            .contains('redistribution and use in source and binary forms') &&
        lowerContent.contains(
            'neither the name of the copyright holder nor the names of its contributors may be used');
  }

  @override
  String get licenseText => r'''BSD 3-Clause New or Revised License

Copyright (c) <year>, <owner>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
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
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.''';
}

class Bsd2ClauseLicenseInfo extends TemplateLicenseInfo {
  @override
  String get licenseId => 'BSD-2-Clause';

  @override
  List<String> get heuristicKeywords => [
        'redistribution and use in source and binary forms',
      ];

  @override
  int get priority => 20; // BSD-3 보다 낮은 우선순위

  @override
  bool matchesHeuristic(String content) {
    final lowerContent = content.toLowerCase();

    // BSD-2-Clause 특화 로직: BSD-3의 3번째 조항이 없어야 함
    return lowerContent
            .contains('redistribution and use in source and binary forms') &&
        !lowerContent.contains(
            'neither the name of the copyright holder nor the names of its contributors may be used');
  }

  @override
  String get licenseText => r'''BSD 2-Clause "Simplified" License

Copyright (c) <year>, <owner>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

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
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.''';
}
