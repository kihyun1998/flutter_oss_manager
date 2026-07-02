import 'models/all_licenses.dart';

/// How [matchLicense] arrived at its result.
enum MatchMethod {
  /// Matched by the pattern/keyword heuristic against a license template.
  heuristic,

  /// Matched by Jaccard paragraph similarity to a template (fallback).
  similarity,

  /// No confident match — [MatchResult.spdx] is `'Unknown'`.
  none,
}

/// The outcome of matching a raw license text to an SPDX identifier.
///
/// A decision record, not a diagnostic log: [confidence] is a single 0..100
/// value whose meaning is set by [method] — for [MatchMethod.heuristic] it is
/// the winning template's confidence score; for [MatchMethod.similarity] and
/// [MatchMethod.none] it is the best paragraph-similarity percentage reached.
class MatchResult {
  const MatchResult({
    required this.spdx,
    required this.method,
    required this.confidence,
  });

  final String spdx;
  final MatchMethod method;
  final double confidence;
}

/// Identifies the SPDX license of [licenseContent].
///
/// Tries the pattern/keyword heuristic first (highest-priority templates
/// first), then falls back to Jaccard paragraph similarity, then gives up with
/// `'Unknown'`. Pure and side-effect-free — callers decide what, if anything,
/// to print from the returned [MatchResult].
MatchResult matchLicense(String licenseContent) {
  // Step 1: heuristic matching (in priority order).
  final licensesByPriority = getLicensesByPriority();

  final List<Map<String, dynamic>> heuristicResults = [];
  for (final licenseInfo in licensesByPriority) {
    final score = licenseInfo.calculateScore(licenseContent);
    if (score['matches'] >= licenseInfo.minMatches) {
      heuristicResults.add({
        'licenseId': licenseInfo.licenseId,
        'confidence': score['confidence'],
      });
    }
  }

  heuristicResults.sort((a, b) => b['confidence'].compareTo(a['confidence']));

  if (heuristicResults.isNotEmpty) {
    final best = heuristicResults.first;
    return MatchResult(
      spdx: best['licenseId'] as String,
      method: MatchMethod.heuristic,
      confidence: (best['confidence'] as num).toDouble(),
    );
  }

  // Step 2: similarity fallback.
  final scannedParagraphs = _normalizeText(licenseContent)
      .split(RegExp(r'\n\s*\n'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (scannedParagraphs.isEmpty) {
    return const MatchResult(
      spdx: 'Unknown',
      method: MatchMethod.none,
      confidence: 0.0,
    );
  }

  String bestMatch = 'Unknown';
  double highestAverageSimilarity = 0.0;

  for (final licenseEntry in allLicenses.entries) {
    final templateParagraphs = _normalizeText(licenseEntry.value.licenseText)
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (templateParagraphs.isEmpty) {
      continue;
    }

    final templateParagraphTokens = templateParagraphs.map(_tokenize).toList();
    double totalSimilarity = 0;

    for (final scannedParagraph in scannedParagraphs) {
      final scannedTokens = _tokenize(scannedParagraph);
      double maxSimilarityForParagraph = 0;

      for (final templateTokens in templateParagraphTokens) {
        final similarity =
            _calculateJaccardSimilarity(scannedTokens, templateTokens);
        if (similarity > maxSimilarityForParagraph) {
          maxSimilarityForParagraph = similarity;
        }
      }
      totalSimilarity += maxSimilarityForParagraph;
    }

    final averageSimilarity = totalSimilarity / scannedParagraphs.length;
    if (averageSimilarity > highestAverageSimilarity) {
      highestAverageSimilarity = averageSimilarity;
      bestMatch = licenseEntry.key;
    }
  }

  // Step 3: final decision.
  if (highestAverageSimilarity > 0.5) {
    return MatchResult(
      spdx: bestMatch,
      method: MatchMethod.similarity,
      confidence: highestAverageSimilarity * 100,
    );
  }

  return MatchResult(
    spdx: 'Unknown',
    method: MatchMethod.none,
    confidence: highestAverageSimilarity * 100,
  );
}

Set<String> _tokenize(String text) {
  return text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((s) => s.isNotEmpty)
      .toSet();
}

double _calculateJaccardSimilarity(Set<String> set1, Set<String> set2) {
  if (set1.isEmpty && set2.isEmpty) return 1.0;
  if (set1.isEmpty || set2.isEmpty) return 0.0;

  final intersection = set1.intersection(set2).length;
  final union = set1.union(set2).length;

  return intersection / union;
}

String _normalizeText(String text) {
  // Remove copyright lines and email addresses.
  text = text.replaceAll(
      RegExp(r'copyright \(c\) .+', caseSensitive: false, multiLine: true), '');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  // Standardize whitespace.
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}
