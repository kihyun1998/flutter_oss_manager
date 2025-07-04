abstract class TemplateLicenseInfo {
  /// 라이선스 식별자 (예: 'MIT', 'Apache-2.0', 'BSD-3-Clause')
  String get licenseId;

  /// 라이선스 전체 텍스트 템플릿
  String get licenseText;

  /// 정규식 패턴들
  List<RegExp> get patterns;

  /// 최소 매치해야 하는 패턴 수
  int get minMatches;

  /// 고유 키워드들 (높은 가중치)
  List<String> get uniqueKeywords => [];

  /// 제외 키워드들 (패널티)
  List<String> get excludeKeywords => [];

  /// 최대 길이 제약
  int? get maxLength => null;

  /// 라이선스 매칭 우선순위 (낮을수록 높은 우선순위)
  int get priority => 100;

  /// 신뢰도 계산
  Map<String, dynamic> calculateScore(String text) {
    int matches = 0;
    double confidence = 0.0;
    List<String> matchedPatterns = [];

    // Check basic patterns
    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) {
        matches++;
        matchedPatterns.add(pattern.pattern);
        confidence += 20;
      }
    }

    // Check unique keywords (higher weight)
    for (final keyword in uniqueKeywords) {
      if (text.toLowerCase().contains(keyword.toLowerCase())) {
        confidence += 40;
        matchedPatterns.add('UNIQUE: $keyword');
      }
    }

    // Check exclude keywords (penalty)
    for (final keyword in excludeKeywords) {
      if (text.toLowerCase().contains(keyword.toLowerCase())) {
        confidence -= 30;
      }
    }

    // Length constraint
    if (maxLength != null && text.length > maxLength!) {
      confidence -= 20;
    }

    // Normalize confidence
    confidence = confidence.clamp(0.0, 100.0);

    return {
      'matches': matches,
      'confidence': confidence,
      'matchedPatterns': matchedPatterns,
    };
  }

  /// 휴리스틱 매칭 (새로운 방식)
  bool matchesHeuristic(String content) {
    final score = calculateScore(content);
    return score['matches'] >= minMatches;
  }
}
