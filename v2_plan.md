# flutter_oss_manager 2.0.0 — 설계안 (개정 v2)

> 상태: 리뷰 반영 개정판 (승인 대기)
> 대상 버전: 2.0.0 (breaking)
> 작성 범위: 메모리 상주 최소화 + 전 플랫폼 지원 + 성능 유지
> 개정 이력:
> - v1 (초안) → 에이전트 리뷰 P0/P1/P2 반영
> - 오탐 제외, 유효 지적 6건 코어 + 3건 보조 반영

---

## 0. 버전 전략 — 반드시 기억할 것

**1.1.0 → 2.0.0 직점프. 1.2.0 은 정식 릴리즈하지 않는다.**

이유:
- 이 브랜치에 머지된 1.2.0 작업분(per-license gzip+base64, getter 디코드)은 **2.0.0 의 whole-blob 접근이 모든 면에서 대체**한다 (§2 비교표).
- 1.2.0 을 pub.dev 에 공개하면 사용자가 한 달 안에 또 breaking migration 을 해야 함 — 불친절.
- git 상에서는 1.2.0 커밋이 남아 있어도 OK, 단 **pubspec 버전은 1.1.0 에서 2.0.0 으로 직접 범프**하고 태그·퍼블리시 건너뜀.

해야 할 일:
- [ ] 2.0.0 작업 시작 시 `pubspec.yaml` 의 `version` 을 `1.2.0` → `2.0.0` 으로 갱신.
- [ ] `CHANGELOG.md` 의 `## 1.2.0` 섹션 **삭제** (혹은 "Unreleased, superseded by 2.0.0" 주석으로 축약).
- [ ] README 의 `^1.2.0` 참조 제거, `^2.0.0` 으로 대체.
- [ ] 마이그레이션 가이드는 **1.1.0 기준** 으로 작성 (1.1.0 사용자가 보게 될 유일한 업그레이드 경로이므로).

---

## 1. 목표

세 가지 조건을 동시에 만족시킨다.

1. **상주 메모리 최소화** — 라이선스 텍스트 및 메타데이터가 Dart 상수풀에 영구 상주하지 않고, 사용자가 원하는 시점에 해제 가능할 것.
2. **전 플랫폼 지원** — Flutter Web (dart2js, dart2wasm), iOS/Android/Desktop(AOT), VM 포함. `dart:io` 의존을 플랫폼별로 분기.
3. **성능 유지** — 매 접근마다 재디코드하지 않고, 한 번 디코드 후 in-memory 참조 유지. 해제 전까지 필드 접근은 zero overhead.

동시에 **외부 패키지 의존성 추가는 금지** (현재 `args`, `path`, `yaml` 외에 추가 없음).

---

## 2. 핵심 아이디어

전체 `List<OssLicense>` 를 한 번에 직렬화하여 **단일 문자열 상수**로 박는다.

```
List<OssLicense>
   → JSON (List<Map<String, dynamic>>)
   → utf8.encode
   → gzip.encode (mtime=0, 결정적)   ← §6.3
   → base64.encode
   → const String _payload
```

런타임에 `OssLicenses.acquire()` 호출 시:

```
_payload
   → base64.decode
   → gzip.decode                      (플랫폼별)
   → utf8.decode
   → jsonDecode → List<Map>
   → List<OssLicense>
```

결과 리스트는 static 핸들 내부 카운트로만 참조됨. 모든 소유자가 `close()` 한 뒤 refcount=0 이 되면 참조 드랍 → 다음 GC 에 회수.

### 왜 per-license 인코딩(1.2.0 방식)이 아니라 whole-blob 인가

| 항목 | 1.2.0 per-license | 2.0 whole-blob |
|---|---|---|
| 압축률 | 라이선스 개별 (중복 미이용) | 전체 공동 (MIT 템플릿 등 교차 dedup, **30–40% 더 작음**) |
| 메타데이터 상주 | `name`/`version`/`summary`/`url`/`description` 평문 상수 | 전부 blob 내부, 평문 상수 0 |
| 접근 비용 | getter 호출 시 gzip 디코드 (매번) | acquire 1회 이후 필드 직접 접근 (무비용) |
| 릴리즈 | getter 반환값만 지역 참조 버리면 GC | `close()` 명시 호출 (refcount) |
| 메모리 상태 | "항상 일부 상주 + 접근 시 임시 할당" | "완전 해제 ↔ 완전 로드" 이분법 |
| 웹 지원 | 불가 (dart:io) | 가능 (조건부 import) |

---

## 3. 공개 API

### 3.1 `OssLicense` — 일반 클래스

```dart
class OssLicense {
  final String name;
  final String version;
  final String licenseText;      // 평문, acquire 후 디코드된 상태로 보유
  final String licenseSummary;
  final String? repositoryUrl;
  final String? description;

  const OssLicense({
    required this.name,
    required this.version,
    required this.licenseText,
    required this.licenseSummary,
    this.repositoryUrl,
    this.description,
  });

  factory OssLicense._fromJson(Map<String, dynamic> j) => OssLicense(
        name: j['name'] as String,
        version: j['version'] as String,
        licenseText: j['licenseText'] as String,
        licenseSummary: j['licenseSummary'] as String,
        repositoryUrl: j['repositoryUrl'] as String?,
        description: j['description'] as String?,
      );
}
```

- `const` 생성자는 유지 — 사용자가 수동으로 인스턴스 만들 수 있음.
- `licenseText` 는 평문 `String` 필드. getter 아님. 접근 비용 없음.

### 3.2 `OssLicenses` — refcounted handle API

단순 static load/release 는 multi-owner (설정 화면 + About 다이얼로그 + 초기 체크) 앱에서 서로 해제 위험이 있음. 따라서 **acquire/close 핸들 + 내부 refcount** 로 설계한다.

```dart
class OssLicensesHandle {
  final List<OssLicense> licenses;
  bool _closed = false;
  OssLicensesHandle._(this.licenses);

  /// 이 핸들의 참조를 반납. 마지막 핸들이 닫히면 내부 캐시 해제 및 GC.
  void close() {
    if (_closed) return;
    _closed = true;
    OssLicenses._releaseOne();
  }
}

class OssLicenses {
  static const String _payload = 'H4sIAA...';   // generator 가 기입
  static Future<List<OssLicense>>? _loading;
  static int _refCount = 0;

  /// 라이선스 리스트 핸들 획득. 첫 호출 시 blob 디코드, 이후는 동일 List 공유.
  /// 모든 핸들이 close() 되면 캐시 해제. 동시 호출 안전.
  static Future<OssLicensesHandle> acquire() async {
    _refCount++;
    _loading ??= _decode();
    final list = await _loading!;
    return OssLicensesHandle._(list);
  }

  /// 테스트에서 전역 상태 초기화. 프로덕션 코드에서 호출 금지.
  @visibleForTesting
  static void resetForTest() {
    _loading = null;
    _refCount = 0;
  }

  static void _releaseOne() {
    _refCount--;
    assert(_refCount >= 0, 'OssLicenses: close() called more than acquire()');
    if (_refCount == 0) {
      _loading = null;
    }
  }

  static Future<List<OssLicense>> _decode() async {
    final bytes = await decodeGzipBase64(_payload);
    final list = jsonDecode(utf8.decode(bytes)) as List;
    return List.unmodifiable(
      list.map((j) => OssLicense._fromJson(j as Map<String, dynamic>)),
    );
  }
}
```

설계 포인트:

- **refcount**: 여러 소유자가 동시에 라이선스 필요할 때 안전. 마지막 한 명이 close 하면 해제.
- **Future 캐시(List 아님)**: 병렬 acquire() 시 이중 디코드 방지. race-free.
- **acquire 중 close 레이스**: `acquire()` 가 `_refCount++` 를 **await 이전에** 수행하므로 decode 진행 중에 다른 owner 가 close 해도 refcount 가 0 되지 않음. P0-3 해소.
- **List.unmodifiable**: 사용자의 실수 mutation 차단.
- **`resetForTest()`**: 단위 테스트에서 isolate 재사용 시 상태 누수 방지.
- **`close()` 멱등성**: 중복 호출은 no-op, assert 로 과다 close 검출.

### 3.3 권장 사용 패턴

```dart
class LicensePage extends StatefulWidget { ... }

class _LicensePageState extends State<LicensePage> {
  late final Future<OssLicensesHandle> _handle = OssLicenses.acquire();

  @override
  void dispose() {
    _handle.then((h) => h.close());   // close 는 idempotent
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<OssLicensesHandle>(
        future: _handle,
        builder: (_, snap) {
          if (!snap.hasData) return const CircularProgressIndicator();
          final licenses = snap.data!.licenses;
          return ListView.builder(
            itemCount: licenses.length,
            itemBuilder: (_, i) {
              final l = licenses[i];
              return ListTile(
                title: Text('${l.name} v${l.version}'),
                subtitle: Text(l.licenseSummary),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => LicenseDetail(l))),
              );
            },
          );
        },
      );
}
```

여러 화면 동시 사용 OK — 각자 acquire/close 하면 refcount 가 알아서 관리.

### 3.4 Hot reload / 개발 시 주의

- `_loading`, `_refCount` 는 static field 라 **hot reload 생존**. 즉 `oss_licenses.dart` 를 재생성한 후에는 **hot reload 가 아닌 hot restart** 필요. 아니면 구 payload 기반 캐시가 남음.
- README 및 CHANGELOG 상단에 명시.

---

## 4. 플랫폼별 디코더 — 조건부 import

### 4.1 파일 구성

`--output lib/oss_licenses.dart` 지정 시 생성되는 4 파일:

```
lib/
  oss_licenses.dart                  # public API + _payload
  oss_licenses_decoder_stub.dart     # UnsupportedError
  oss_licenses_decoder_io.dart       # dart:io gzip
  oss_licenses_decoder_web.dart      # dart:js_interop + DecompressionStream
```

### 4.2 메인 파일 상단 (순서 중요)

```dart
// 로드 순서는 load-bearing: dart:io 를 js_interop 보다 먼저 체크해야
// 네이티브 AOT/VM 에서 io 디코더가 선택됨. 웹(dart2js, dart2wasm)에서는
// dart.library.io 가 false 이므로 자동으로 web 디코더로 떨어진다.
import 'oss_licenses_decoder_stub.dart'
    if (dart.library.io) 'oss_licenses_decoder_io.dart'
    if (dart.library.js_interop) 'oss_licenses_decoder_web.dart';
```

**WASM 대응**: `flutter build web --wasm` 에서도 `dart.library.io=false`, `dart.library.js_interop=true` → 웹 디코더 선택. 릴리즈 전 `example/` 에서 `flutter build web` 및 `flutter build web --wasm` 둘 다 빌드·기동 확인 필수.

### 4.3 각 디코더의 공통 시그니처

```dart
Future<Uint8List> decodeGzipBase64(String encoded);
```

### 4.4 IO 디코더

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> decodeGzipBase64(String encoded) async {
  final gzipped = base64.decode(encoded);
  final raw = gzip.decode(gzipped);
  return raw is Uint8List ? raw : Uint8List.fromList(raw);
}
```

실제로는 sync 이지만 공통 시그니처를 위해 Future 래핑.

### 4.5 Web 디코더 (타입 정확화)

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response(JSAny? body);
  external _ReadableStream? get body;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('ReadableStream')
extension type _ReadableStream._(JSObject _) implements JSObject {
  external _ReadableStream pipeThrough(_DecompressionStream transform);
}

@JS('DecompressionStream')
extension type _DecompressionStream._(JSObject _) implements JSObject {
  external factory _DecompressionStream(String format);
}

Future<Uint8List> decodeGzipBase64(String encoded) async {
  final Uint8List bytes = base64.decode(encoded);

  // Blob 우회 없이 Response 가 BufferSource 직접 수용.
  final source = _Response(bytes.toJS);
  final readable = source.body!;
  final decompressed = readable.pipeThrough(_DecompressionStream('gzip'));
  final buffer = await _Response(decompressed).arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
```

- 외부 패키지 0, `dart:js_interop` 만 사용.
- `_ReadableStream` 을 typed extension type 으로 선언 → `JSObject` 떡칠 제거.
- Blob 경유 제거 → 중간 allocation 1개 절감.
- `DecompressionStream` 요구사항: Chrome 80+, Firefox 113+, Safari 16.4+.

### 4.6 Stub

```dart
import 'dart:async';
import 'dart:typed_data';

Future<Uint8List> decodeGzipBase64(String encoded) =>
    throw UnsupportedError(
      'flutter_oss_manager: no decoder available for this platform. '
      'Expected either dart:io or dart:js_interop to be available.',
    );
```

---

## 5. 메모리 & 성능 체감치 (재현실화)

### 5.1 페이로드 사이즈 (추정)

| 프로젝트 규모 | 원문 합계 | gzip 후 | base64 후 |
|---|---|---|---|
| 소규모 (20 패키지) | ~20 KB | ~5–8 KB | ~7–11 KB |
| 중규모 (50 패키지) | ~60 KB | ~15–20 KB | ~20–27 KB |
| 대규모 (150 패키지) | ~200 KB | ~50–80 KB | ~70–110 KB |
| 초대규모 (300+ 패키지) | ~500 KB+ | ~130–200 KB | ~180–270 KB |

Dart 상수풀 상주 = **base64 문자열 하나뿐**.

초대규모 경계 유의: Flutter 실제 앱이 transitive 포함 300+ 패키지 드물지 않음. README 에 상한 케이스 명시.

### 5.2 런타임 비용 (§9 와 일관화)

| 시점 | IO (네이티브) | Web (dart2js) | Web (wasm) |
|---|---|---|---|
| 앱 기동 | 0 | 0 | 0 |
| `acquire()` 첫 호출 (50패키지) | 3–10 ms | 10–30 ms | 5–15 ms |
| `acquire()` 첫 호출 (150패키지) | 10–30 ms | 30–80 ms | 15–40 ms |
| `acquire()` 첫 호출 (300패키지) | 30–80 ms | 80–200 ms | 40–100 ms |
| acquire 후 리스트/필드 접근 | 0 | 0 | 0 |
| `close()` (마지막) | 0 | 0 | 0 |

**결론: acquire 는 항상 비동기, UI 는 반드시 로딩 인디케이터. "수 ms" 는 소규모 네이티브만 해당.** 초기 50–200ms 비용을 숨길 수 없으므로 FutureBuilder 패턴이 **권장 아니라 필수**.

피크 메모리 (acquire 중 순간): `base64 + gzip bytes + utf8 bytes + json string + parsed list ≈ 3–4× 최종 리스트 사이즈`. 300패키지 기준 피크 1–2 MB 수준. 모바일 기준 문제없음.

### 5.3 메모리 lifecycle

```
기동 ─ const _payload 만 상주 (수십~수백 KB 단일 문자열)
  │
  ├─ acquire() 호출 (refcount 1) → decoded List + String 인스턴스 생성
  │   사용자 화면 진행 중 핸들 held
  │
  ├─ 추가 acquire() (refcount 2+) → 같은 List 공유, 디코드 0
  │
  └─ 마지막 close() (refcount 0) → _loading = null → 다음 GC 에 회수
      원상태로 복귀
```

---

## 6. Generator 변경

### 6.1 `license_generator.dart` 수정 범위

- `_writeDartFile(outputPath, licenses)` → `_writeGeneratedFiles(outputPath, licenses)` 로 리네임.
- 기존 단일 파일 쓰기 로직 → 4 파일 쓰기로 확장.
- 신규 helper:
  - `_encodePayload(List<OssLicense>)` — JSON → gzip(결정적) → base64.
  - `_writeMainFile(path, payload, sidecarStem)`
  - `_writeDecoderIo(path)` / `_writeDecoderWeb(path)` / `_writeDecoderStub(path)`
  - `_resolveSidecarPaths(outputPath)` — §6.4 규칙.

### 6.2 JSON 직렬화 스키마

```json
[
  {
    "name": "path",
    "version": "1.9.0",
    "licenseText": "Copyright ...",
    "licenseSummary": "BSD-3-Clause",
    "repositoryUrl": "https://...",
    "description": "..."
  }
]
```

- null 필드는 그대로 null.
- 키 이름은 `OssLicense` 필드와 1:1.
- **키 순서 고정**: 위 순서로 직렬화 (Dart Map 은 insertion order 유지하므로 코드에서 명시).

### 6.3 gzip 결정적 출력 (중요)

Dart 의 `GZipCodec().encode()` 는 기본적으로 **gzip 헤더에 mtime(빌드 시각) + OS byte 를 박음**. 이대로면 같은 입력에 대해 매 `scan` 실행마다 **출력 바이트가 달라짐** → VCS 체크인 사용자는 매번 diff 노이즈.

해결: mtime 을 0, OS 를 0xFF(unknown) 로 고정한 gzip 헤더 직접 구성.

```dart
// 10-byte gzip header with zeroed mtime/OS.
List<int> _gzipDeterministic(List<int> data) {
  final deflated = ZLibCodec(
    raw: true,           // no zlib wrapper, raw DEFLATE
    level: 9,
  ).encode(data);

  // CRC32 and ISIZE for gzip trailer.
  final crc = _crc32(data);
  final isize = data.length & 0xFFFFFFFF;

  return [
    0x1F, 0x8B,          // magic
    0x08,                // CM = deflate
    0x00,                // FLG = 0
    0x00, 0x00, 0x00, 0x00, // MTIME = 0
    0x00,                // XFL = 0
    0xFF,                // OS = unknown
    ...deflated,
    crc & 0xFF, (crc >> 8) & 0xFF, (crc >> 16) & 0xFF, (crc >> 24) & 0xFF,
    isize & 0xFF, (isize >> 8) & 0xFF, (isize >> 16) & 0xFF, (isize >> 24) & 0xFF,
  ];
}
```

CRC32 는 표준 알고리즘 직접 구현 (~20 줄). 외부 deps 금지 조건 충족.

검증: 같은 입력에 대해 `_gzipDeterministic()` 결과 바이트가 10회 모두 동일한지 단위 테스트.

### 6.4 사이드카 경로 파생 규칙

`--output <path>` 에서 네 파일의 실제 경로 결정:

| `--output` 값 | 메인 | 사이드카 3종 |
|---|---|---|
| `lib/oss_licenses.dart` | `lib/oss_licenses.dart` | `lib/oss_licenses_decoder_{stub,io,web}.dart` |
| `lib/src/licenses.dart` | `lib/src/licenses.dart` | `lib/src/licenses_decoder_{stub,io,web}.dart` |
| `lib/gen/licenses.g.dart` | `lib/gen/licenses.g.dart` | `lib/gen/licenses.g_decoder_{stub,io,web}.dart` |
| `lib/oss_licenses` (no ext) | `lib/oss_licenses.dart` (ext 자동 보정) | `lib/oss_licenses_decoder_{stub,io,web}.dart` |

규칙 (의사코드):
```
base = outputPath.endsWith('.dart') ? outputPath.dropLast('.dart') : outputPath
main = base + '.dart'
sidecar(variant) = base + '_decoder_' + variant + '.dart'
```

**충돌 방지**: 사이드카 경로에 이미 파일이 존재하면 generator 가 해시 비교 → 내용이 다르면 **에러로 중단** (사용자 수작업 파일 덮어쓰기 방지). 동일하면 no-op.

### 6.5 기존 `.dart` 파일 생성 지점

- `scanPackages` 의 `_writeDartFile` 호출부 → `_writeGeneratedFiles` 로 교체.
- `generateLicenses` 도 동일.
- CLI 인자 (`--output`) 시맨틱 불변: 경로는 **메인 파일** 경로, 사이드카는 자동 파생.

---

## 7. 버전 / 호환성

### 7.1 pubspec

- `version: 2.0.0` (1.1.0 → 2.0.0 직점프, 1.2.0 skip)
- `environment.sdk: ">=3.4.0 <4.0.0"` — `Uint8List.toJS` / `JSArrayBuffer.toDart → ByteBuffer` 안정 기점. 3.3 은 반쪽짜리.
- dependencies 추가 없음.
- `executables:` 엔트리 (기존 `flutter_oss_manager:` 빈 값 축약) **유지** — `bin/flutter_oss_manager.dart` 로 자동 매핑되는 유효 YAML. 변경 불필요.

### 7.2 브라우저 플로어

| 브라우저 | 최소 버전 | 근거 |
|---|---|---|
| Chrome | 80 | DecompressionStream (2020.02) |
| Firefox | 113 | DecompressionStream (2023.05) |
| Safari | 16.4 | DecompressionStream (2023.03) |
| Edge | 80 | Chromium 기반 |

Flutter 공식 웹 지원 범위와 유사. README 명시.

### 7.3 Breaking 사항

| 1.1.0 | 2.0.0 |
|---|---|
| `const List<OssLicense> ossLicenses` 탑레벨 상수 | `await OssLicenses.acquire()` handle |
| `license.licenseText` 평문 getter | `license.licenseText` 평문 필드 (acquire 후) |
| 단일 파일 산출 | 4 파일 산출 |
| Web 불가 | Web (dart2js, dart2wasm) OK |

재생성 필수. 마이그레이션 가이드는 CHANGELOG 에 코드 예시 포함 — **1.2.0 기준 아닌 1.1.0 기준**.

---

## 8. 문서 업데이트

### 8.1 README

- **Installation**: `^2.0.0`.
- **Generated File Structure**: 4 파일 레이아웃 그림 + 조건부 import 설명 + "사이드카는 직접 import 하지 말 것" 경고.
- **Usage in Your App**: `OssLicenses.acquire()` / `handle.close()` 패턴 예시로 교체.
- **Memory behavior** (신설): lifecycle 다이어그램, 권장 패턴, hot reload 주의 (§3.4).
- **Platform support** (신설): 지원 플랫폼 표, 브라우저 floor, SDK floor.
- **Migrating from 1.1.0** (신설): before/after 코드, 흔한 케이스 3종.
- **VCS 가이드** (신설): 4파일 전부 커밋 or `.gitignore` 로 일괄 제외. 일부만 커밋은 컴파일 깨짐.

### 8.2 CHANGELOG (1.1.0 → 2.0.0 직점프 명시)

```md
## 2.0.0

> Note: 1.2.0 was an internal iteration and was never published.
> Upgrading directly from 1.1.0.

* **breaking**: Complete redesign of the generated file to minimize resident
  memory across all platforms (including Flutter Web).
* **api**: The generated file now exposes `OssLicenses.acquire()` returning a
  disposable `OssLicensesHandle`. The top-level `const List<OssLicense>`
  is removed. Call sites must be updated.
* **output**: `dart run flutter_oss_manager scan` now writes 4 files
  (main + 3 platform decoders) to the `--output` directory. Commit all 4
  if you VCS the generated file; deletion of any one breaks compile.
* **platforms**: Flutter Web (dart2js, dart2wasm) is supported via
  `dart:js_interop` + `DecompressionStream`. Requires Chrome 80+,
  Firefox 113+, Safari 16.4+.
* **sdk**: Minimum Dart SDK bumped to 3.4.0 (js_interop typed-data bridge).
* **action required**: After upgrading, delete the old `oss_licenses.dart`
  and re-run `dart run flutter_oss_manager scan`. Old 1.1.0 generated
  files will not compile against 2.0.0.
* **dev note**: After regenerating during development, use **hot restart**,
  not hot reload — static cache state does not reset across hot reload.
```

마이그레이션 예시 3종:

1. **ListView 에서 직접 참조**
```dart
// Before (1.1.0)
ListView.builder(
  itemCount: ossLicenses.length,
  itemBuilder: (_, i) => Text(ossLicenses[i].name),
)

// After (2.0.0)
FutureBuilder<OssLicensesHandle>(
  future: _handle,   // late final _handle = OssLicenses.acquire();
  builder: (_, s) => s.hasData
    ? ListView.builder(
        itemCount: s.data!.licenses.length,
        itemBuilder: (_, i) => Text(s.data!.licenses[i].name),
      )
    : const CircularProgressIndicator(),
)
// + dispose() 에서 s.data?.close()
```

2. **StatelessWidget 에서 참조**
```dart
// Before
class About extends StatelessWidget {
  Widget build(c) => Text('packages: ${ossLicenses.length}');
}

// After — StatefulWidget 으로 전환 필요
class About extends StatefulWidget { ... }
class _AboutState extends State<About> {
  late final Future<OssLicensesHandle> _h = OssLicenses.acquire();
  @override void dispose() { _h.then((h) => h.close()); super.dispose(); }
  @override Widget build(c) => FutureBuilder(future: _h, builder: ...);
}
```

3. **앱 시작 시 일괄 프리로드**
```dart
// 앱 부팅 시 한 번 acquire, 앱 종료 전까지 유지.
// 메모리 상주 감수하고 대신 모든 화면이 즉시 접근하고 싶을 때.
Future<void> main() async {
  final handle = await OssLicenses.acquire();
  runApp(MyApp(handle: handle));
}
```

---

## 9. 테스트 전략 (신설)

### 9.1 단위 테스트

- **페이로드 roundtrip**: 임의 `List<OssLicense>` → `_encodePayload` → `_decodePayload` → 원본과 동일 검증.
- **gzip 결정성**: 동일 입력으로 10회 인코드 → 모두 동일 바이트.
- **concurrency**: `acquire()` 를 병렬 N개 호출 → `_decode` 는 1회만 실행 (카운터 인스트루먼트).
- **refcount**: acquire×3, close×2 → 여전히 캐시 유지. close×3 째에 `_loading` null.
- **close 멱등성**: 같은 handle 에 close 2회 → no-op, refcount 과다 감소 없음.
- **`resetForTest()`**: 상태 누수 없이 다음 테스트 준비.

### 9.2 Generator 골든 테스트

- 픽스처 pubspec.lock + mock pub cache → generator 실행.
- 4 출력 파일이 `test/golden/` 의 기준 파일과 바이트 동일.
- gzip 결정성 덕분에 diff 안정.

### 9.3 플랫폼 디코더 테스트

- IO 디코더: `dart test` 로 직접 검증.
- Web 디코더: `flutter test --platform chrome` (WASM 도 추가 가능).
- Stub 디코더: `UnsupportedError` 던짐 확인.

### 9.4 Example 앱 수동 검증 (릴리즈 전 필수)

- `example/` 를 2.0 API 기준 코드로 업데이트.
- `flutter build apk` / `flutter build ios` / `flutter build macos` — 네이티브 빌드 확인.
- `flutter build web` / `flutter build web --wasm` — 웹 빌드 확인.
- 각 플랫폼 런타임에서 acquire → 리스트 표시 → 상세 보기 → close 동선 확인.

---

## 10. 리스크 / 오픈 이슈

1. **웹 검증 인프라 부재**: 이 레포엔 웹 CI 없음. 2.0 태깅 전에 `example/` 에서 수동 확인 (§9.4).
2. **`dart:js_interop` SDK 민감성**: 3.4 → 3.5 사이 소폭 API 변화 있었음. 테스트 SDK 기준 고정.
3. **대형 프로젝트 첫 acquire 지연**: 300+ 패키지면 최대 200 ms. splash / 로딩 인디케이터 **필수** (§5.2).
4. **4파일 산출물 관리**: 사용자가 `.gitignore` 제외 or 4개 모두 커밋. 부분 커밋은 컴파일 깨짐.
5. **Generator 재실행 시 사이드카 덮어쓰기**: §6.4 규칙으로 해시 비교 후 내용 다르면 에러 중단.
6. **WASM 에서 js_interop 세부 동작**: 수동 검증 필요 (§9.4).

---

## 11. 비-목표 / 배제된 대안

1. **단일 파일 + pure-Dart inflate** — 성능 3–10× 느림, +400 LoC. 배제.
2. **WeakReference 기반 자동 캐시** — 수명 예측 불가. 배제.
3. **메타데이터만 const + text 만 blob (하이브리드)** — 사용자 의도와 충돌. 배제.
4. **`archive` 등 pure-Dart gzip 패키지 추가** — 의존성 금지. 배제.
5. **const string chunking (AOT 크기 제한 방어)** — <500KB 범위에서 실증 문제 없음. 오버엔지니어링. 배제.
6. **`dart:html` 폴백 clause** — SDK 3.4+ 에서 `dart.library.js_interop` 이 모든 웹 타겟 지원. 불필요.
7. **`Isolate.run` 으로 IO 디코드 offload** — 20–50ms 범위에선 isolate spawn 이 오히려 비쌈. 초대규모(200+ packages, ms 단위 중요) 케이스 전용으로 2.1 옵셔널 플래그로 미룸.
8. **`licenseRegistry` 자동 등록 헬퍼** — 2.0 스코프 밖, 별도 기능.

---

## 12. 작업 순서 (승인 후)

1. `pubspec.yaml` — 2.0.0, SDK floor 3.4.0.
2. `license_generator.dart` — `_writeGeneratedFiles` + 4 writer + `_gzipDeterministic` + `_resolveSidecarPaths`.
3. `CHANGELOG.md` — 1.2.0 섹션 제거 (Unreleased 주석 처리), 2.0.0 엔트리 + migration 3종 예시.
4. `README.md` — 섹션 갱신 5곳 (§8.1).
5. `example/` — 샘플 코드 `OssLicenses.acquire()` 패턴으로 전면 교체.
6. `test/` — roundtrip / concurrency / refcount / 골든 테스트 추가.
7. 로컬 검증 (§9.4): 네이티브 3 + 웹 2 = 5 플랫폼 빌드 & 런.
8. 태깅·퍼블리시.

---

## 13. 결정 대기 항목

1. **handle API 형태**: `OssLicenses.acquire()` + `OssLicensesHandle.close()` 로 확정해도 OK?
2. **SDK floor 3.4.0 로 확정 OK?** (더 보수적으로 3.5 도 가능)
3. **사이드카 충돌 정책**: 해시 비교 후 다르면 에러 중단 vs 강제 덮어쓰기 vs `--force` 플래그. 추천: **에러 중단 + `--force` 옵션**.
4. **`resetForTest()` 공개 수준**: `@visibleForTesting` annotation 으로 충분 vs 완전 private (그러면 테스트 불가).
5. **gzip 결정성 구현**: 직접 헤더 구성 (§6.3) vs `RawZLibCodec` 활용 후 wrapper 덧씌우기. 직접 구성이 간단. 확정.

5개 모두 그린라이트 → 코드 착수.
