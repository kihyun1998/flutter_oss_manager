abstract class TemplateLicenseInfo {
  /// 라이선스 식별자 (예: 'MIT', 'Apache-2.0', 'BSD-3-Clause')
  String get licenseId;

  /// 라이선스 전체 텍스트 템플릿
  String get licenseText;

  /// 휴리스틱 매칭을 위한 키워드 리스트
  List<String> get heuristicKeywords;

  /// 라이선스별 특화된 휴리스틱 매칭 로직
  /// 기본 구현은 키워드 기반 매칭을 사용하며,
  /// 각 라이선스에서 필요시 오버라이드 가능
  bool matchesHeuristic(String content) {
    final lowerContent = content.toLowerCase();

    // 모든 키워드가 포함되어 있는지 확인
    return heuristicKeywords
        .every((keyword) => lowerContent.contains(keyword.toLowerCase()));
  }

  /// 라이선스 매칭 우선순위 (낮을수록 높은 우선순위)
  /// 더 구체적인 라이선스가 먼저 매칭되도록 함
  int get priority => 100;
}
