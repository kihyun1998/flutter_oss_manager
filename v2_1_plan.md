# flutter_oss_manager 2.1.0 — 설계안: pub.dev API 기반 SPDX 식별

> 상태: 초안 (리뷰/승인 대기)
> 대상 버전: 2.1.0 (minor, non-breaking)
> 작성 범위: 라이선스 식별 로직을 heuristic-only → pub.dev API 우선 + 캐시 + heuristic 폴백으로 개선
> 선행 버전: 2.0.0 (refcounted handle API, web support, 4파일 산출물)

---

## 0. 배경

현재 `LicenseGenerator._summarizeLicense` (license_generator.dart:72) 는 LICENSE 파일 본문을 읽어
템플릿과 Jaccard 유사도 / heuristic 매칭으로 SPDX ID 를 **추정**한다. 동작은 하지만:

- 커스텀 헤더 / 드문 포맷의 LICENSE 파일에서 오탐·미탐.
- 새 라이선스가 등장할 때마다 `all_licenses.dart` 템플릿을 수동 추가해야 함.
- 정답지가 이미 pub.dev 에 있는데 본문을 재추론하는 건 구시대적.

반면 pub.dev 는 각 패키지에 대해 pana 분석 결과를 API 로 노출하고, 거기엔 SPDX 식별자가
권위 있게 들어 있음. 이걸 **1순위 소스**로 쓰고, heuristic 은 **폴백** 으로 강등한다.

---

## 1. 목표

1. **정확도**: hosted 패키지의 SPDX 판정은 pub.dev 가 주는 값을 신뢰 (사람·pana 검증 결과).
2. **빌드 재현성**: 동일 `pubspec.lock` 에 대해 빌드마다 같은 결과. 네트워크 flap 으로 결과가
   바뀌면 안 됨 → 캐시 필수.
3. **오프라인/CI 친화**: 캐시 히트 시 네트워크 불필요. 명시적 `--offline` 플래그 제공.
4. **후진 호환**: 사용자의 공개 API (`OssLicenses.acquire()` 등) 는 건드리지 않음. 2.0 산출
   물과 완전 호환. 버전은 **2.1.0 (minor)**.
5. **의존성 추가 금지**: 현재 `args` / `path` / `yaml` 외에 추가 없음. `dart:io HttpClient`
   로 충분 (이 도구는 CLI 전용, 웹 런타임 의존 없음).

---

## 2. 핵심 아이디어

판정 파이프라인을 3단 폴백으로 재구성:

```
패키지 (name, version, licenseText)
   │
   ├─ [1] 캐시 조회  (.dart_tool/flutter_oss_manager/pub_license_cache.json)
   │     hit  → 리턴 (source: cache)
   │     miss → 다음 단계
   │
   ├─ [2] pub.dev API 조회  (GET /api/packages/<name>/score)
   │     200 + spdxIdentifier 추출 성공 → 캐시 기록 후 리턴 (source: pub-api)
   │     네트워크 실패 / 404 / 필드 없음 → 다음 단계
   │
   ├─ [3] Heuristic (기존 _summarizeLicense 로직 그대로)
   │     매칭 성공 → 캐시 기록 후 리턴 (source: heuristic)
   │     실패 → 다음 단계
   │
   └─ [4] 'Unknown'  (캐시에 negative 로 기록해서 같은 빌드 재호출 방지)
```

**핵심 원칙**:
- 캐시 키는 `name@version`. pubspec.lock 의 버전이 올라가면 자동 invalidation — 수동
  캐시 삭제 필요 없음.
- heuristic 결과도 캐시에 저장. 네트워크 재시도로 같은 실패를 반복하지 않음.
- SDK 패키지 (`flutter`, `flutter_test`, `sky_engine`) 는 pub.dev 범위 밖 → heuristic-only
  유지 (기존 `_findAndSummarizeSdkLicense` 건드리지 않음).
- 라이선스 **본문 (`licenseText`)** 은 계속 pub-cache 의 LICENSE 파일에서 읽음. pub.dev 는
  SPDX 식별자만 제공, 전문은 내려주지 않음.

---

## 3. 모듈 구성

### 3.1 신규 파일

```
lib/src/
  pub_license_client.dart     # pub.dev /api/packages/<name>/score 호출
  license_cache.dart          # .dart_tool/... JSON 캐시 파일 입출력
```

### 3.2 `pub_license_client.dart`

```dart
abstract class PubLicenseClient {
  Future<String?> fetchSpdxId(String name, String version);
}

class HttpPubLicenseClient implements PubLicenseClient {
  HttpPubLicenseClient({Duration timeout = const Duration(seconds: 5)});

  /// GET https://pub.dev/api/packages/<name>/score
  /// Response (관심 필드만):
  ///   {
  ///     "grantedPoints": ..., "maxPoints": ...,
  ///     "tags": [
  ///       "license:bsd-3-clause",   // ← 실제 SPDX ID (소문자)
  ///       "license:fsf-libre",      // classifier, 무시
  ///       "license:osi-approved",   // classifier, 무시
  ///       ...
  ///     ]
  ///   }
  ///
  /// SPDX 추출 규칙:
  ///   tags 중 'license:' 접두사 + 'license:fsf-libre'/'license:osi-approved' 제외
  ///   → 남은 하나의 값을 SPDX canonical casing 으로 정규화 (§3.2.1).
  ///
  /// Returns null on:
  ///   - network error / timeout
  ///   - non-200 (404 포함 — 패키지 미존재)
  ///   - JSON parse failure
  ///   - license 태그 없음 (unlicensed/legacy 패키지)
  @override
  Future<String?> fetchSpdxId(String name, String version);
}
```

구현 포인트:
- `dart:io HttpClient` 사용 (외부 의존성 X).
- `User-Agent: flutter_oss_manager/<version> (+https://github.com/kihyun1998/flutter_oss_manager)`
  — pub.dev 는 식별 가능한 UA 요구.
- 타임아웃 기본 5초. try/catch 로 모든 실패를 null 로 변환 (호출자는 폴백).
- **version 은 현재 엔드포인트 응답에선 사용 안 함** (최신 분석 결과만 반환됨). 시그니처에
  유지하는 이유: 추후 `/api/packages/<name>/versions/<version>/score` 사용으로 확장 가능.
- 실측 확인 (2026-04-22): `/score` 응답에 `licenses[]` 필드는 존재하지 않음. SPDX 는
  `tags[]` 에 `license:<spdx-lower>` 형태로 박혀 있음. 404 는 정상 응답.

### 3.2.1 SPDX 정규화 테이블

pub.dev 는 소문자 SPDX ID 를 주지만 기존 heuristic / `_problematicLicenses` 는 canonical
casing 을 사용함. 일관성을 위해 소규모 매핑 테이블로 변환:

```dart
const _spdxCanonical = {
  'mit':          'MIT',
  'bsd-3-clause': 'BSD-3-Clause',
  'bsd-2-clause': 'BSD-2-Clause',
  'apache-2.0':   'Apache-2.0',
  'gpl-2.0':      'GPL-2.0',
  'gpl-3.0':      'GPL-3.0',
  'lgpl-2.1':     'LGPL-2.1',
  'lgpl-3.0':     'LGPL-3.0',
  'agpl-3.0':     'AGPL-3.0',
  'mpl-2.0':      'MPL-2.0',
  'isc':          'ISC',
  'unlicense':    'Unlicense',
  'cc0-1.0':      'CC0-1.0',
};
// 미매핑 ID 는 원본 소문자 그대로 보존 + 경고 로그 (매핑 테이블 보강 필요 신호).
```

**추상화 이유**: 테스트에서 `FakePubLicenseClient` 주입 → 네트워크 없이 검증.

### 3.3 `license_cache.dart`

```dart
class LicenseCache {
  LicenseCache({required String projectRoot});

  /// .dart_tool/flutter_oss_manager/pub_license_cache.json
  File get cacheFile;

  /// Load from disk. Missing file → empty cache (no error).
  Future<void> load();

  /// Cache 조회. 없으면 null.
  CachedLicense? get(String name, String version);

  /// Cache 기록. 메모리만 갱신; 디스크 flush 는 save() 명시 호출.
  void put(String name, String version, CachedLicense entry);

  /// 메모리 상태를 디스크에 저장.
  Future<void> save();

  /// Strip all entries. --refresh-cache 플래그 구현용.
  void clear();
}

class CachedLicense {
  final String spdx;        // 'MIT', 'Unknown', ...
  final String source;      // 'pub-api' | 'heuristic' | 'negative'
  final DateTime fetchedAt;
}
```

캐시 파일 포맷 (JSON):

```json
{
  "schemaVersion": 1,
  "entries": {
    "args@2.4.2":  { "spdx": "BSD-3-Clause", "source": "pub-api",   "fetchedAt": "2026-04-22T10:15:00Z" },
    "path@1.9.0":  { "spdx": "BSD-3-Clause", "source": "pub-api",   "fetchedAt": "2026-04-22T10:15:01Z" },
    "foo@1.0.0":   { "spdx": "MIT",          "source": "heuristic", "fetchedAt": "2026-04-22T10:15:02Z" },
    "bar@0.1.0":   { "spdx": "Unknown",      "source": "negative",  "fetchedAt": "2026-04-22T10:15:03Z" }
  }
}
```

캐시 정책:
- 위치: `<projectRoot>/.dart_tool/flutter_oss_manager/pub_license_cache.json`.
  `.dart_tool/` 은 `flutter create` 가 자동 gitignore 대상으로 추가 → 캐시 커밋 안 됨.
- TTL 없음 — `name@version` 키로 자연 invalidation. `--refresh-cache` 로 명시 재조회.
- `schemaVersion` 필드로 향후 포맷 변경 시 구캐시 자동 무시 (load 시 mismatch 면 빈 캐시로
  취급).
- **Negative 캐시** (`source: negative`): API 실패 + heuristic 실패로 'Unknown' 판정된 케이스.
  같은 빌드에서 반복 조회 낭비 방지. `--refresh-cache` 로 초기화 가능.

### 3.4 `license_generator.dart` 변경

생성자에 선택 주입:

```dart
class LicenseGenerator {
  LicenseGenerator({
    PubLicenseClient? pubClient,
    LicenseCache? cache,
    bool offline = false,
  }) : _pubClient = pubClient ?? HttpPubLicenseClient(),
       _cache = cache,
       _offline = offline;

  final PubLicenseClient _pubClient;
  LicenseCache? _cache;
  final bool _offline;
  // ...
}
```

신규 메서드:

```dart
/// 3단 폴백 파이프라인. hosted 패키지 전용.
/// SDK 패키지는 기존 경로 (heuristic-only) 유지.
Future<_ResolvedSpdx> _resolveSpdx({
  required String packageName,
  required String version,
  required String licenseText,
}) async {
  // [1] cache
  final cached = _cache?.get(packageName, version);
  if (cached != null) return _ResolvedSpdx(cached.spdx, 'cache');

  // [2] pub.dev
  if (!_offline) {
    final spdx = await _pubClient.fetchSpdxId(packageName, version);
    if (spdx != null) {
      _cache?.put(packageName, version,
          CachedLicense(spdx: spdx, source: 'pub-api', fetchedAt: DateTime.now().toUtc()));
      return _ResolvedSpdx(spdx, 'pub-api');
    }
  }

  // [3] heuristic
  final heuristic = _summarizeLicense(licenseText);  // 기존 메서드 그대로
  final source = heuristic == 'Unknown' ? 'negative' : 'heuristic';
  _cache?.put(packageName, version,
      CachedLicense(spdx: heuristic, source: source, fetchedAt: DateTime.now().toUtc()));
  return _ResolvedSpdx(heuristic, source);
}

class _ResolvedSpdx {
  final String spdx;
  final String source;  // 로그 출력용
  const _ResolvedSpdx(this.spdx, this.source);
}
```

`_summarizeLicense` 자체는 **건드리지 않음** (sync, 기존 로직 그대로). heuristic 경로에서
재사용.

`_findAndSummarizeHostedLicense` (line 507) 수정점:

```dart
// Before
final licenseSummary = _summarizeLicense(licenseContent);

// After
final resolved = await _resolveSpdx(
  packageName: packageName,
  version: packageVersion,
  licenseText: licenseContent,
);
print('  → ${resolved.spdx} [${resolved.source}]');
final licenseSummary = resolved.spdx;
```

`scanPackages` 수정점:
- 함수 상단에서 `_cache ??= LicenseCache(projectRoot: Directory.current.path)` 초기화 및
  `await _cache!.load()`.
- 루프 종료 후 `await _cache!.save()` (한 번만 flush — 개별 put 마다 디스크 IO 하지 않음).
- 동시성: 현재 `for` 루프가 직렬. pub.dev 호출이 들어오면 30+ 패키지 × 200ms RTT = 체감
  지연 크다. 간단히 **세마포어 8** 로 묶어 동시 실행.

### 3.5 CLI 플래그 (`bin/flutter_oss_manager.dart`)

`scan` 커맨드에 3개 플래그 추가:

```dart
parser.addCommand('scan',
    buildCommandParser()
      ..addFlag('offline',
          help: 'Skip pub.dev API; use cache + heuristic only.',
          defaultsTo: false)
      ..addFlag('refresh-cache',
          help: 'Ignore existing cache and re-fetch all entries.',
          defaultsTo: false)
      ..addFlag('no-cache',
          help: 'Do not read or write the cache file.',
          defaultsTo: false));
```

메인 분기:

```dart
final offline = command['offline'] as bool;
final refresh = command['refresh-cache'] as bool;
final noCache = command['no-cache'] as bool;

LicenseCache? cache;
if (!noCache) {
  cache = LicenseCache(projectRoot: Directory.current.path);
  await cache.load();
  if (refresh) cache.clear();
}

final generator = LicenseGenerator(cache: cache, offline: offline);
await generator.scanPackages(outputFilePath: command['output']);
```

조합 시맨틱:
- `--offline` + `--refresh-cache`: 캐시 클리어 후 네트워크 금지 → 전부 heuristic. (의미 있음:
  예전 캐시 완전 리셋 + 네트워크 OFF 시나리오.)
- `--no-cache`: 캐시 파일 자체 무시. 테스트 / 원샷 용도.

---

## 4. 로깅

각 패키지마다 **출처 태그**를 찍어 틀렸을 때 원인 추적 가능:

```
Scanning packages for licenses...
- args (2.4.2) [hosted] → BSD-3-Clause [cache]
- path (1.9.0) [hosted] → BSD-3-Clause [pub-api]
- foo_internal (1.0.0) [hosted] → MIT [heuristic, 87.3% confidence]
- bar (2.1.0) [hosted] → Unknown [negative]
- flutter [sdk] → BSD-3-Clause [heuristic]
```

`--verbose` 시 HTTP 요청 URL, 응답 바이트 크기, 캐시 hit/miss 건수 합계 등 추가 출력.

---

## 5. pub.dev API 검증

**엔드포인트**: `GET https://pub.dev/api/packages/<name>/score`

검증해야 할 사항 (구현 착수 전 수동 curl 로 확인):
1. 응답 스키마에 `licenses[].spdxIdentifier` 가 존재하는지.
2. 존재하지 않는 패키지 요청 시 404 응답인지, 아니면 200 + 빈 객체인지.
3. rate-limit 임계치 (대략 초당 몇 건까지 OK인지, 429 응답 포맷).
4. UA 미설정 시 거부 여부.

**리스크**: 이 엔드포인트는 공식적으로 문서화되지 않음 (unofficial). pub.dev 가 응답 구조를
바꾸면 조회가 조용히 실패할 수 있음. 완화책:
- `fetchSpdxId` 는 모든 예외를 null 로 삼킴 → heuristic 폴백이 자동 동작.
- 파싱 실패 통계를 `--verbose` 에서 노출 (`N/M pub.dev requests succeeded`).
- README 에 "SPDX 판정은 pub.dev API 우선, 실패 시 heuristic 폴백" 명시.

대안으로 공식 API 만 사용한다면:
- `GET /api/packages/<name>` — SPDX 식별자 없음. 라이선스는 pana 분석 결과에만 존재.
- 즉 `/score` 외에 대안 없음. 리스크 감수.

---

## 6. 버전 / 호환성

### 6.1 pubspec

- `version: 2.0.0 → 2.1.0` (minor, non-breaking)
- SDK floor / 의존성 변경 없음.
- `dart:io HttpClient` 사용 → 기존 SDK 범위에서 동작.

### 6.2 Breaking 여부

**없음.** 근거:
- 공개 API (`OssLicenses.acquire()`, `OssLicense`, 생성된 `.g.dart`) 완전 동일.
- `LicenseGenerator` 는 internal (lib/src/). `lib/flutter_oss_manager.dart` 는 공개 export
  하지 않음 → 외부에서 직접 인스턴스화 불가 (최소한 지원 대상 아님).
- CLI 명령어 시그니처 변경 없음. 기존 `scan` / `generate` 동작 동일, 플래그만 추가 (선택).
- 생성되는 `.g.dart` 4파일 포맷 동일. 재실행 시 내용은 SPDX 가 더 정확해질 수 있음 (의도된
  개선).

### 6.3 동작 변화 (사용자 체감)

| 항목 | 2.0.0 | 2.1.0 |
|---|---|---|
| `scan` 첫 실행 (50 패키지) | ~1초 (파일 IO + heuristic) | ~3–5초 (pub.dev 호출 8 동시, 캐시 빌드) |
| `scan` 재실행 (캐시 히트) | ~1초 | ~1초 (캐시 히트, 네트워크 0) |
| 오프라인 `scan` | 동작 | 동작 (`--offline` 또는 캐시에서) |
| SPDX 정확도 | heuristic 의존 | pub.dev + heuristic 폴백 |
| 네트워크 필요성 | 없음 | 캐시 미스 + 온라인 모드에서만 |

---

## 7. 테스트 전략

### 7.1 단위 테스트

- **`LicenseCache` roundtrip**: put → save → load → get 으로 원본 일치.
- **schema version mismatch**: `schemaVersion: 999` 파일 로드 시 빈 캐시로 처리, 에러 안 남.
- **`_resolveSpdx` 파이프라인**:
  - 캐시 히트 시 pub client 호출 안 함 (Fake 로 호출 카운트 검증).
  - 캐시 미스 + pub client 성공 → spdx 리턴, 캐시 기록.
  - 캐시 미스 + pub client null → heuristic 폴백.
  - `offline: true` 면 pub client 호출 스킵.
  - heuristic 도 'Unknown' 이면 negative 캐싱.
- **동시성**: 같은 배치에서 동일 `name@version` 중복 요청 시 pub.dev 중복 호출 방지 (in-
  flight 디듀프 여부 결정 필요 — §10.3 오픈 이슈).

### 7.2 통합 테스트

- Fake pubspec.lock + fake pub cache (LICENSE 파일 포함) + `FakePubLicenseClient` 주입 →
  `scanPackages` 실행 → 기대 산출물 검증.
- `--offline` / `--refresh-cache` / `--no-cache` 플래그 각각 상호작용 확인.

### 7.3 수동 검증 (릴리즈 전)

- 실제 프로젝트 (`example/`) 에서 `dart run flutter_oss_manager scan` 최초 실행:
  - 캐시 파일 생성 여부.
  - pub.dev 응답 기반 SPDX 가 현재 heuristic 결과와 다른 케이스가 있는지 (있으면 pub.dev
    가 맞을 가능성 높음).
- 2회차 실행: 네트워크 차단 상태에서도 성공, 모든 태그 `[cache]` 확인.
- `--refresh-cache` 실행: 캐시 파일 타임스탬프 갱신, 네트워크 재호출.

### 7.4 네트워크 실패 시뮬레이션

- `FakePubLicenseClient` 로 timeout / 500 / malformed JSON 시나리오 주입 → 모든 경우 heuristic
  폴백 동작 + 경고 로그 출력.

---

## 8. 문서 업데이트

### 8.1 README

- **License Detection** (신설 섹션): 3단 폴백 설명 + 캐시 위치 + 플래그 안내.
- **Privacy note**: "첫 실행 시 `pubspec.lock` 의 패키지 이름이 pub.dev 로 전송됨. 모두 이미
  공개된 정보지만, 네트워크 아웃바운드를 막고 싶다면 `--offline`."
- **CI 권장 설정**: 캐시 파일을 CI 캐시 (GitHub Actions `actions/cache` 등) 에 포함하면 빌드
  가속.

### 8.2 CHANGELOG

```md
## 2.1.0

* **feature**: SPDX license identification now queries pub.dev's analysis API
  first, falling back to the existing heuristic matcher. Results are cached
  under `.dart_tool/flutter_oss_manager/pub_license_cache.json` keyed by
  `name@version`, so repeated scans of the same `pubspec.lock` require zero
  network traffic.
* **cli**: `scan` gains three flags — `--offline` (skip pub.dev, cache+heuristic
  only), `--refresh-cache` (ignore existing cache), `--no-cache` (do not read
  or write the cache file).
* **logging**: Each package now prints the source of its SPDX decision
  (`[cache]`, `[pub-api]`, `[heuristic]`, `[negative]`) for easier debugging.
* **compat**: No breaking changes. The generated `.g.dart` format is identical
  to 2.0.0. SDK packages (flutter, flutter_test, sky_engine) continue to use
  heuristic matching.
* **privacy**: On first run (or after `--refresh-cache`), package names from
  `pubspec.lock` are sent to pub.dev to look up license metadata. Use
  `--offline` to opt out.
```

---

## 9. 작업 순서 (승인 후)

1. `lib/src/pub_license_client.dart` — 추상 인터페이스 + `HttpPubLicenseClient` 구현 + Fake.
2. `lib/src/license_cache.dart` — JSON 입출력, schema versioning.
3. `lib/src/license_generator.dart` — `_resolveSpdx` 추가, `_findAndSummarizeHostedLicense`
   수정, `scanPackages` 에 캐시 라이프사이클 + 동시성 (세마포어 8) 배선.
4. `bin/flutter_oss_manager.dart` — 3개 플래그 추가 + 분기.
5. `test/` — 캐시 roundtrip, `_resolveSpdx` 파이프라인, 통합 시나리오.
6. `example/` 에서 수동 검증 (온라인 / 오프라인 / refresh).
7. `README.md` + `CHANGELOG.md` 업데이트.
8. `pubspec.yaml` 버전 `2.0.0 → 2.1.0`.
9. 태깅·퍼블리시.

diff 예상 규모: 신규 ~400 LoC + 기존 수정 ~50 LoC. 기존 heuristic 로직은 **한 줄도 안 지움**.

---

## 10. 결정된 항목 (2026-04-22)

모두 그린라이트. 착수 확정.

1. **API 엔드포인트**: `/api/packages/<name>/score`. 실측 완료 — SPDX 는 `tags[]` 에
   `license:<spdx-lower>` 로 존재. `licenses[]` 배열 아님. 404 정상 응답.
2. **캐시 파일 위치**: `.dart_tool/flutter_oss_manager/pub_license_cache.json` 으로 확정
   (gitignore 자동).
3. **In-flight 디듀프**: 생략. pubspec.lock 은 유일 엔트리 보장.
4. **negative 캐시 TTL**: 없음. `--refresh-cache` 수동 갱신에만 의존.
5. **동시성 세마포어 크기**: 기본 8. 추후 rate-limit 이슈 시 조정.
6. **SDK floor**: 2.0.0 의 `>=3.4.0 <4.0.0` 그대로.
