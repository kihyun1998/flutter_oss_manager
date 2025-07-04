/// Abstract base class for defining license templates.
///
/// Each concrete implementation of this class represents a specific open-source
/// license (e.g., MIT, Apache-2.0) and provides the necessary patterns and
/// keywords for its identification and summarization.
abstract class TemplateLicenseInfo {
  /// The unique identifier for the license (e.g., 'MIT', 'Apache-2.0', 'BSD-3-Clause').
  String get licenseId;

  /// The full template text of the license.
  String get licenseText;

  /// A list of regular expressions used to identify the license within a given text.
  List<RegExp> get patterns;

  /// The minimum number of patterns that must match for a heuristic identification.
  int get minMatches;

  /// A list of unique keywords that strongly indicate this license type.
  /// These keywords are given higher weight during heuristic matching.
  List<String> get uniqueKeywords => [];

  /// A list of keywords that, if present, suggest this is NOT this license type.
  /// These keywords apply a penalty during heuristic matching.
  List<String> get excludeKeywords => [];

  /// An optional maximum length for the license text. If the text exceeds this
  /// length, it might reduce the confidence score for this license type.
  int? get maxLength => null;

  /// The priority of this license during matching. Lower numbers indicate higher priority.
  /// Licenses with higher priority are checked first during heuristic matching.
  int get priority => 100;

  /// Calculates a score for how well the given [text] matches this license template.
  ///
  /// The score includes the number of matching patterns, a confidence percentage,
  /// and a list of matched patterns.
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

  /// Determines if the given [content] matches this license template based on heuristic rules.
  ///
  /// This method uses the [calculateScore] to determine if the content meets
  /// the minimum match requirements for this license.
  bool matchesHeuristic(String content) {
    final score = calculateScore(content);
    return score['matches'] >= minMatches;
  }
}
