import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Looks up the SPDX license identifier of a pub.dev package.
abstract class PubLicenseClient {
  Future<String?> fetchSpdxId(String name, String version);

  /// Releases any resources held for reuse across lookups (e.g. a pooled
  /// connection). Safe to call more than once; a later [fetchSpdxId] may
  /// transparently re-acquire what it needs.
  void close();
}

/// Maps the lowercase SPDX identifiers that pana emits to their canonical
/// SPDX casing. Keeping this aligned with [LicenseGenerator]'s heuristic
/// output lets cache entries be compared across sources.
///
/// Unknown identifiers fall through as-is (lowercase) — that's a signal to
/// expand this table.
const Map<String, String> _spdxCanonical = {
  'mit': 'MIT',
  'bsd-3-clause': 'BSD-3-Clause',
  'bsd-2-clause': 'BSD-2-Clause',
  'apache-2.0': 'Apache-2.0',
  'gpl-2.0': 'GPL-2.0',
  'gpl-3.0': 'GPL-3.0',
  'lgpl-2.1': 'LGPL-2.1',
  'lgpl-3.0': 'LGPL-3.0',
  'agpl-3.0': 'AGPL-3.0',
  'mpl-2.0': 'MPL-2.0',
  'isc': 'ISC',
  'unlicense': 'Unlicense',
  'cc0-1.0': 'CC0-1.0',
  'zlib': 'Zlib',
  'bsl-1.0': 'BSL-1.0',
  'epl-2.0': 'EPL-2.0',
  'wtfpl': 'WTFPL',
};

/// Tags that appear alongside the SPDX tag but are classifier-only; these
/// must be filtered out before picking the SPDX identifier.
const Set<String> _licenseClassifierTags = {
  'license:fsf-libre',
  'license:osi-approved',
};

/// Exposed for tests. Given the `tags` array from pub.dev's `/score`
/// response, return the canonical SPDX identifier (or `null` if none).
String? extractSpdxFromTags(List<dynamic> tags) {
  for (final tag in tags) {
    if (tag is! String) continue;
    if (!tag.startsWith('license:')) continue;
    if (_licenseClassifierTags.contains(tag)) continue;
    final lower = tag.substring('license:'.length);
    if (lower.isEmpty) continue;
    return _spdxCanonical[lower] ?? lower;
  }
  return null;
}

/// Production client: `dart:io HttpClient` against pub.dev. All failures
/// (network, non-200, parse, missing tag) collapse to `null` so callers can
/// fall back without special-casing.
class HttpPubLicenseClient implements PubLicenseClient {
  HttpPubLicenseClient({
    this.timeout = const Duration(seconds: 5),
    String? userAgent,
    Uri? baseUri,
  })  : userAgent = userAgent ??
            'flutter_oss_manager/2.2.0 '
                '(+https://github.com/kihyun1998/flutter_oss_manager)',
        baseUri = baseUri ?? Uri.parse('https://pub.dev');

  final Duration timeout;
  final String userAgent;

  /// Base URI for pub.dev. Overridable so tests can point at a local
  /// `HttpServer` without actually hitting pub.dev.
  final Uri baseUri;

  /// One reusable client for the whole batch, so connections to pub.dev are
  /// kept alive across lookups instead of being torn down per package.
  /// Recreated on demand after [close].
  HttpClient? _client;

  HttpClient get _http => _client ??= HttpClient();

  @override
  void close() {
    _client?.close(force: true);
    _client = null;
  }

  @override
  Future<String?> fetchSpdxId(String name, String version) async {
    final uri = baseUri.replace(path: '/api/packages/$name/score');
    final client = _http;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final tags = decoded['tags'];
      if (tags is! List) return null;
      return extractSpdxFromTags(tags);
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HandshakeException {
      return null;
    } on HttpException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
