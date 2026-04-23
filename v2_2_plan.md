# flutter_oss_manager 2.2.0 — 설계안: 런타임 전용 의존성 스캔

> 상태: 초안 (리뷰/승인 대기)
> 대상 버전: 2.2.0 (minor, non-breaking — 옵트인 플래그)
> 작성 범위: `scan` 커맨드에 dev_dependencies 및 그 transitive 를 제외하는 모드 추가
> 선행 버전: 2.1.0 (pub.dev SPDX + 캐시)

---

## 0. 배경

현재 `LicenseGenerator.scanPackages` (license_generator.dart:531) 는 `pubspec.lock` 의
`packages:` 맵을 그대로 순회한다. lock 파일은 `direct main` / `direct dev` / `transitive`
세 종류 엔트리를 모두 담고 있어서, 수집된 라이선스 리스트에는 런타임에 **앱 번들로 포함되지
않는** 개발 도구 패키지가 섞여 있다.

실제 예 (example 프로젝트):

- 포함되어야 함: `http`, `provider`, `shared_preferences` 등 런타임 의존
- 포함되면 안 됨: `build_runner`, `flutter_lints`, `test`, `mockito`, `analyzer`,
  `_fe_analyzer_shared`, … (dev 전용 및 그 transitive)

라이선스 고지 의무는 **배포물에 포함된 저작물** 에 대해서만 발생한다 (예: Apache-2.0 §4,
MIT, BSD 계열의 "in the Software" / "in copies" 표현). dev 전용 툴체인은 최종 사용자에게
전달되지 않으므로 고지 대상이 아니고, 현재 동작은 다음 문제를 유발한다:

1. **고지 리스트 과다**: 수십 개의 불필요한 엔트리가 라이선스 화면을 점유.
2. **오탐 경고**: `_problematicLicenses` (GPL/LGPL/AGPL) 가 dev 툴체인에 섞여 있어도
   경고가 뜸 → 배포물에는 영향이 없는데 사용자가 오해.
3. **빌드 시간**: pub.dev 조회 + 파일 IO 가 불필요한 패키지에도 소모 (캐시가 있어도 초회는
   비용 발생).

이 기획은 스캔 범위를 **런타임 의존성 그래프** 로 좁히는 **옵트인** 모드를 추가한다. 기본
동작은 변경하지 않는다.

---

## 1. 목표

1. **정확한 의존성 그래프 계산**: 루트 `pubspec.yaml` 의 `dependencies:` 에서 시작해 transitive
   를 따라가되, dev 경로로만 도달 가능한 패키지는 배제.
2. **옵트인**: `--runtime-only` 플래그로 활성화. 기본값은 기존 동작 (전체 수집).
3. **후진 호환**: 공개 API, 생성물 포맷, 기존 플래그 시맨틱 모두 그대로. 버전 **2.2.0 (minor)**.
4. **의존성 추가 금지**: 2.1.0 범위 그대로 (`args`, `path`, `yaml`). 새 외부 패키지 없음.
5. **관찰 가능성**: 필터링된 패키지는 로그에 이유 태그와 함께 출력 (투명성 확보 + 디버깅).

---

## 2. 핵심 아이디어

**`pubspec.lock` 단독으로는 판별 불가**. lock 의 `dependency:` 필드는 세 값 중 하나지만,
dev 패키지의 transitive 의존은 `transitive` 로 뭉뚱그려져 있어서 main 경로의 transitive
와 구분되지 않는다.

```
# pubspec.lock (발췌, 예시)
analyzer:
  dependency: transitive     # build_runner 가 끌고 옴 (dev-only)
async:
  dependency: transitive     # http 가 끌고 옴 (runtime)
collection:
  dependency: transitive     # 양쪽 경로 모두에서 도달 가능 (runtime, 포함해야 함)
```

정확한 판별을 위해 **런타임 루트로부터의 그래프 도달 가능성 (reachability)** 을 계산한다.

```
runtime_roots = root pubspec.yaml 의 dependencies 키 이름 집합   # dev_dependencies 제외
visited       = {}
queue         = runtime_roots 로 초기화

while queue:
    name = queue.popLeft()
    if name in visited: continue
    visited.add(name)

    pubspec = resolvePackagePubspec(name)   # pubspec.lock 의 source/version 정보 활용
    if pubspec is None: continue            # 없으면 더 파고들지 않음 (보수적 포함)

    for dep_name in pubspec.dependencies:   # pubspec 의 dependencies: 만. dev_dependencies: 는 제외
        if dep_name not in visited:
            queue.add(dep_name)

runtime_package_names = visited
```

**핵심 규칙**: 각 패키지의 pubspec 을 읽을 때도 **`dev_dependencies:` 는 항상 제외**.
루트에서만 제외하면 `http` 의 dev_dependencies (예: `test`) 가 한 단계 더 들어간 뒤 그
transitive 가 줄줄이 포함되어버림.

**공유 패키지 처리**: `collection` 처럼 main 경로와 dev 경로 양쪽에서 도달 가능한 패키지는
main 경로로 먼저 도달하는 순간 `visited` 에 들어가므로 자동으로 포함됨. 정답.

---

## 3. 모듈 구성

### 3.1 신규 파일

```
lib/src/
  dependency_graph.dart        # 런타임 그래프 계산 로직
```

### 3.2 `dependency_graph.dart`

```dart
/// pubspec.yaml 한 개의 내용을 추상화. 테스트에서 in-memory 맵을 주입하기 위한
/// 경계(seam). 파일시스템을 직접 뚫지 않도록 그래프 워커는 이 인터페이스만 씀.
abstract class PubspecReader {
  /// pubspec.lock 의 source/version/description 정보를 받아 해당 패키지의
  /// pubspec.yaml 내용을 YamlMap 으로 반환. 없거나 읽기 실패면 null.
  Future<YamlMap?> read({
    required String packageName,
    required YamlMap lockEntry,   // pubspec.lock packages[name] 통째로
  });
}

/// 실제 디스크에서 읽는 기본 구현. §3.2.1 의 source 분기 로직을 담음.
class FilePubspecReader implements PubspecReader {
  FilePubspecReader({
    required String pubCachePath,
    required String? flutterSdkPath,
    required String projectRoot,     // path 소스의 상대경로 resolve 용
  });
  // ...
}

/// Computes the set of package names reachable from the root project's
/// runtime dependencies, excluding dev_dependencies at every graph level.
class RuntimeDependencyGraph {
  RuntimeDependencyGraph({
    required String projectRoot,
    required YamlMap pubspecLockPackages,   // pubspec.lock 의 'packages' 맵
    required PubspecReader reader,          // 테스트 주입 가능
  });

  /// BFS 수행. 반환값은 런타임 그래프에 속한 패키지 이름 집합.
  /// 루트 프로젝트 자신은 포함하지 않음 (자기 자신의 LICENSE 는 별개 메인 앱).
  Future<Set<String>> compute();
}
```

**주입 설계 이유**: 그래프 워커를 순수 로직 + `PubspecReader` 인터페이스로 분리하면 단위
테스트가 픽스처 파일 트리를 구성할 필요 없이 `Map<String, YamlMap>` 한 개로 끝남. §7.1 의
8개 시나리오를 플랫폼 독립적으로 커버 가능.

### 3.2.1 `FilePubspecReader` 의 source 분기

- **루트 pubspec 파싱**: `<projectRoot>/pubspec.yaml` → `dependencies:` 키 이름 수집.
  `flutter: { sdk: flutter }` 같은 SDK 참조도 이름 기준으로 그대로 큐에 투입.
- **각 노드의 pubspec 해석**: `lockEntry.source` 로 분기.
  - `hosted`: `<pubCache>/hosted/pub.dev/<name>-<version>/pubspec.yaml`
  - `sdk`: 후보 경로 2개 순차 시도
    1. `<flutterSdkPath>/packages/<name>/pubspec.yaml` (대부분의 SDK 패키지)
    2. `<flutterSdkPath>/bin/cache/pkg/<name>/pubspec.yaml` (**`sky_engine` 예외 경로**)
    둘 다 없으면 leaf 로 조용히 처리 (경고 없음 — `sky_engine` 은 dependencies 가 없는
    leaf 라 결과에 영향 없고, 매 스캔마다 경고가 찍히면 노이즈).
  - `path`: `lockEntry.description.path` 의 `pubspec.yaml`. 상대 경로면 `projectRoot`
    기준 resolve.
  - `git`: `<pubCache>/git/<name>-<commit>/<description.path>/pubspec.yaml`.
- **dependencies 만 읽음**: 각 pubspec 에서 `dependencies:` 만 읽고 `dev_dependencies:` /
  `dependency_overrides:` 는 무시 (dependency_overrides 의 처리는 §6.1 참고).
- **pubspec 누락 내성**: hosted/path/git 소스에서 파일이 없거나 파싱 실패 시 해당 노드를
  leaf 로 취급 + 경고 로그 1회 (sdk 소스는 위 화이트리스트 경로 실패 시 조용히 leaf). 스캔
  은 중단하지 않음 — 결과가 빠지는 것보다 한두 개 더 포함되는 편이 안전.

### 3.3 `license_generator.dart` 변경

`scanPackages` 시그니처 확장:

```dart
Future<void> scanPackages({
  String? outputFilePath,
  bool runtimeOnly = false,   // 신규
}) async {
  // ... 기존 pubspec.lock 로드 ...

  final packages = pubspecLockMap['packages'] as YamlMap?;
  var entries = packages?.entries.toList() ?? const [];

  Set<String>? runtimeNames;
  if (runtimeOnly) {
    final reader = FilePubspecReader(
      pubCachePath: _getPubCacheDir(),
      flutterSdkPath: await _getFlutterSdkPath(),
      projectRoot: Directory.current.path,
    );
    final graph = RuntimeDependencyGraph(
      projectRoot: Directory.current.path,
      pubspecLockPackages: packages ?? YamlMap(),
      reader: reader,
    );
    runtimeNames = await graph.compute();
    final before = entries.length;
    entries = entries
        .where((e) => runtimeNames!.contains(e.key.toString()))
        .toList();
    final skipped = before - entries.length;
    print('Runtime-only mode: keeping ${entries.length} packages, skipping $skipped dev/dev-transitive packages.');
  }

  // ... 이하 기존 배치 스캔 루프 (변경 없음) ...
}
```

`_findAndSummarizeHostedLicense`, `_findAndSummarizeSdkLicense` 등 하위 로직은 **한 줄도
안 건드림**.

### 3.4 CLI 플래그 (`bin/flutter_oss_manager.dart`)

```dart
final scanParser = buildCommandParser()
  ..addFlag('offline', ...)
  ..addFlag('refresh-cache', ...)
  ..addFlag('no-cache', ...)
  ..addFlag('runtime-only',
      help:
          'Skip dev_dependencies and their transitive dependencies. '
          'Only packages reachable from the root pubspec.yaml dependencies: '
          'section are scanned.',
      defaultsTo: false,
      negatable: false);
```

메인 분기:

```dart
final runtimeOnly = command['runtime-only'] as bool;
// ... 기존 캐시 세팅 ...
final generator = LicenseGenerator(cache: cache, offline: offline);
await generator.scanPackages(
  outputFilePath: outputFilePath,
  runtimeOnly: runtimeOnly,
);
```

**플래그 이름 결정 이유**: `--runtime-only` 는 의미가 긍정 서술 (무엇을 포함할지) 이라 읽기
쉬움. `--exclude-dev` 도 후보였지만 "dev 의 transitive 도 함께 제외한다" 는 뉘앙스가 약함.

### 3.5 다른 플래그와의 조합

| 조합 | 동작 |
|---|---|
| `--runtime-only` 단독 | 런타임 그래프 계산 → 필터 → 기존 pub.dev+캐시 파이프라인 |
| `--runtime-only --offline` | 그래프 계산은 로컬 파일만 씀 (pub cache + SDK). 네트워크 불필요 → 정상 동작 |
| `--runtime-only --refresh-cache` | 그래프 필터 후 캐시 클리어 + 재조회. 조합 의미 있음 |
| `--runtime-only --no-cache` | 문제 없음 |

---

## 4. 로깅

기본 모드 (기존과 동일):

```
Scanning packages for licenses...
- args (2.4.2) [hosted] → BSD-3-Clause [cache]
- build_runner (2.4.15) [hosted] → BSD-3-Clause [cache]
...
```

`--runtime-only` 모드:

```
Scanning packages for licenses...
Runtime-only mode: keeping 23 packages, skipping 47 dev/dev-transitive packages.
- args (2.4.2) [hosted] → BSD-3-Clause [cache]
- http (1.2.0) [hosted] → BSD-3-Clause [cache]
...
```

`--verbose` 추가 시 스킵된 패키지 이름 목록 전체를 출력:

```
[verbose] Skipped (dev or dev-transitive):
  - analyzer (6.4.1)
  - _fe_analyzer_shared (67.0.0)
  - build_runner (2.4.15)
  - flutter_lints (5.0.0)
  ...
```

기본 모드에서 `_problematicLicenses` 경고가 출력될 때는 꼬리에 힌트 한 줄 추가:

```
⚠️  Found packages with potentially problematic licenses:
  - some_dev_tool (1.0.0): GPL-3.0
Tip: if these are dev-only dependencies, re-run with --runtime-only to filter
     them out before evaluating compliance risk.
```

— dev 툴체인이 오탐 유발할 때 사용자를 바른 플래그로 안내. `_printLicenseWarnings`
(license_generator.dart) 에 한 줄 추가.

---

## 5. 버전 / 호환성

### 5.1 pubspec

- `version: 2.1.0 → 2.2.0` (minor, non-breaking)
- SDK floor / 의존성 변경 없음.

### 5.2 Breaking 여부

**없음.** 근거:

- 공개 API (`OssLicenses.acquire()`, `OssLicense`, 생성된 `.g.dart`) 완전 동일.
- `scanPackages` 의 신규 파라미터는 선택적이고 기본값이 기존 동작.
- CLI 는 플래그 1개 추가일 뿐, 기존 플래그·커맨드 동작 동일.
- 생성물 `.g.dart` 포맷 2.0.0/2.1.0 과 동일. `--runtime-only` 사용 시 리스트만 짧아짐.

### 5.3 동작 변화 (사용자 체감)

| 항목 | 2.1.0 | 2.2.0 (기본) | 2.2.0 (`--runtime-only`) |
|---|---|---|---|
| 기본 동작 | 전체 수집 | 전체 수집 (동일) | 런타임만 수집 |
| 스캔 대상 수 | 70+ | 70+ | 20~30 (프로젝트별) |
| 실행 시간 (캐시 히트) | ~1초 | ~1초 | <1초 |
| 고지 리스트 엔트리 | 70+ | 70+ | 20~30 |
| dev 툴체인 경고 오탐 | 발생 | 발생 | 없음 |

---

## 6. 엣지 케이스

### 6.1 `dependency_overrides:`

루트 pubspec 의 `dependency_overrides:` 는 **이미 선언된** 의존성의 버전·소스를 바꾸는
역할. 그래프 도달 가능성에는 영향 없음 (이름 집합 동일). pub 이 lock 파일 생성 시 이미
해석해둔 값을 쓰므로, 그래프 워커는 lock 의 source/version 을 따르면 자동 일치.

**주의**: `dependency_overrides:` 가 루트에만 지정 가능하지 않다 — 하위 패키지의
`dependency_overrides:` 는 pub 이 무시하므로 우리가 신경 쓸 필요 없음.

### 6.2 `path` / `git` 소스

- `path`: `lock.packages[name].description.path` 에 절대/상대 경로. 상대면 `projectRoot`
  기준으로 resolve.
- `git`: pub cache 에 `git/<name>-<commit>/<description.path>` 형태로 체크아웃돼 있음.
  `description.path` 가 repo 루트인 경우 `.` (빈 문자열로 처리).

둘 다 pubspec.yaml 이 체크아웃 안에 존재 → 파싱 가능.

### 6.3 SDK 패키지 (`flutter`, `flutter_test`, `sky_engine`)

- `flutter` 의 pubspec 은 `$FLUTTER_ROOT/packages/flutter/pubspec.yaml`. 여기의 `dependencies:`
  에 `sky_engine`, `meta`, `collection`, `vector_math` 등이 선언돼 있어 그래프 워커가
  따라갈 수 있음.
- `flutter_test` 는 `dev_dependencies` 경로로만 도달되는 경우가 많으므로 `--runtime-only`
  에서 자동 배제됨 — 의도한 동작.
- `$FLUTTER_ROOT` 가 없거나 (CI 의 dart-only 환경 등) 경로 접근 실패 시 해당 노드를 leaf
  로 취급 + 경고 로그.

### 6.4 그래프 순환

Dart pubspec 에서는 이론상 순환 의존이 불가능하지만 (pub 이 거부), 방어적으로 `visited`
체크로 무한 루프 차단.

### 6.5 루트 pubspec 자기 자신

그래프에 루트 프로젝트 이름은 넣지 않는다. `pubspec.lock` 의 `packages:` 맵에도 루트는
없으므로 필터링 결과에 영향 없음.

### 6.6 Flutter 플러그인의 플랫폼별 의존

`flutter: { plugin: { platforms: { android: { ... } } } }` 블록은 네이티브 코드 연결용
메타데이터. 우리 그래프 워커는 `dependencies:` 만 읽으므로 자연히 무시됨. OK.

### 6.7 pubspec 파일에 `dependencies:` 가 아예 없는 패키지

`dependencies:` 키 자체가 없거나 null → 빈 맵으로 처리. 문제 없음.

---

## 7. 테스트 전략

### 7.1 단위 테스트 (`dependency_graph.dart`)

픽스처: 메모리상 `pubspec.lock` YAML + 가상 파일 시스템에 각 패키지의 `pubspec.yaml`
배치.

시나리오:

1. **기본 케이스**: 루트 `dependencies: [A, B]`, A 의존 `[C]`, B 의존 `[D]` → 결과 `{A, B,
   C, D}`.
2. **dev 전용 배제**: 루트 `dev_dependencies: [X]`, X 의존 `[Y]` → 결과에서 X, Y 둘 다
   제외.
3. **공유 패키지 포함**: 루트 `dependencies: [A]`, `dev_dependencies: [B]`. A 와 B 가 모두
   `[S]` 의존 → S 포함 (main 경로 존재).
4. **하위 패키지의 dev_dependencies 무시**: 루트 `dependencies: [A]`, A 의 pubspec 에
   `dev_dependencies: [Z]` → Z 제외 확인.
5. **`dependency_overrides:` 무시**: 루트의 overrides 가 그래프 이름 집합에 영향 없음.
6. **pubspec 누락**: 한 패키지의 pubspec 을 일부러 제거 → 해당 노드 leaf, 경고 로그, 상위
   노드는 정상 포함.
7. **순환 방어**: A→B→A 구성 (인위적) → 무한 루프 없음.
8. **SDK leaf fallback**: `flutterSdkPath: null` 일 때 `flutter` 가 leaf 로 처리.

### 7.2 통합 테스트 (`scanPackages`)

Fake pubspec.lock + fake pub cache + `FakePubLicenseClient` + `runtimeOnly: true` →
생성된 `.g.dart` 에 런타임 패키지만 포함, dev 패키지는 부재.

### 7.3 수동 검증 (릴리즈 전)

`example/` 프로젝트에서:

```bash
# baseline
dart run flutter_oss_manager scan -o lib/oss_licenses.g.dart
# diff 용
mv lib/oss_licenses.g.dart lib/oss_licenses.all.g.dart
dart run flutter_oss_manager scan --runtime-only -o lib/oss_licenses.g.dart
diff <(grep 'name:' lib/oss_licenses.all.g.dart) <(grep 'name:' lib/oss_licenses.g.dart)
```

확인 항목:

- 기대한 dev 패키지 (`build_runner`, `flutter_lints`, `test`, `analyzer`, ...) 가 런타임
  모드에서 빠져 있는지.
- 공유 패키지 (`collection`, `meta`, `async`) 는 런타임 모드에서도 유지되는지.
- `flutter_lints` 같은 dev 전용 SDK 인접 패키지가 빠지는지.

---

## 8. 문서 업데이트

### 8.1 README

**Runtime-only scanning** 섹션 신설:

```md
### Excluding dev dependencies

By default, `scan` walks every entry in `pubspec.lock`, which includes
`dev_dependencies` and their transitive packages (e.g. `build_runner`,
`flutter_lints`, `test`). These tools are not bundled with your released app
and usually do not need to appear in user-facing license notices.

To limit the scan to packages reachable from your root `pubspec.yaml`
`dependencies:` section:

```bash
dart run flutter_oss_manager scan --runtime-only -o lib/oss_licenses.g.dart
```

This performs a graph walk starting from your runtime dependencies, excluding
`dev_dependencies` at every level. Shared packages (a package depended on by
both a runtime and a dev package) are still included — if it's reachable from
a runtime root, it ships with your app.
```

### 8.2 CHANGELOG

```md
## 2.2.0

* **feature**: `scan` gains a `--runtime-only` flag that restricts license
  collection to packages reachable from the root `pubspec.yaml` `dependencies:`
  section. `dev_dependencies` and their transitive packages (e.g.
  `build_runner`, `flutter_lints`, `test`) are excluded via a proper dependency
  graph walk — shared packages reachable from both runtime and dev paths are
  still included.
* **logging**: Runtime-only mode prints a summary of kept vs. skipped package
  counts. Use `--verbose` to list skipped package names.
* **compat**: No breaking changes. Default behavior (scan all packages) is
  unchanged. The generated `.g.dart` format is identical to 2.1.0.
```

---

## 9. 작업 순서 (승인 후)

각 phase 끝에 커밋 지점을 두어 리뷰/롤백 단위를 분리. Phase 1 에서 알고리즘의 정답성을
먼저 증명한 뒤 디스크·CLI 배선을 붙이는 순서.

### Phase 1 — 코어 로직 (파일시스템 독립)

**목표**: BFS 알고리즘이 dev-only 서브트리를 정확히 배제하는지 증명. 디스크 읽기 없음.

1. `lib/src/dependency_graph.dart` 신설:
   - `PubspecReader` 추상 인터페이스.
   - `RuntimeDependencyGraph` 클래스 — 루트 pubspec 파싱 + BFS + dev_dependencies 제외
     규칙. `PubspecReader` 에만 의존.
2. `test/dependency_graph_test.dart` — §7.1 의 8개 시나리오를 `FakePubspecReader`
   (in-memory `Map<String, YamlMap>`) 로 커버.

**완료 조건**: 단위 테스트 전부 통과. 실제 파일 IO 없이 그래프 정답성 확정.
**커밋**: `feat(graph): add RuntimeDependencyGraph with pubspec reader abstraction`

### Phase 2 — 파일시스템 연결

**목표**: 실제 pub cache / Flutter SDK / path·git source 에서 pubspec 을 읽어올 수 있게.

3. `lib/src/dependency_graph.dart` 에 `FilePubspecReader` 추가 — §3.2.1 의 source 4종
   분기 (hosted / sdk + sky_engine fallback / path / git).
4. `example/` 에서 수동 스모크: `FilePubspecReader` 가 각 source 타입을 실제로 읽는지
   일회성 확인용 스크립트로 검증.

**완료 조건**: `example/` 의 pubspec.lock 에 있는 모든 패키지의 pubspec 을 에러 없이
읽음. sky_engine 에서 경고 노이즈 없음 확인.
**커밋**: `feat(graph): implement FilePubspecReader for all lock source types`

### Phase 3 — 통합 배선

**목표**: `scan --runtime-only` 가 end-to-end 로 동작.

5. `lib/src/license_generator.dart`:
   - `scanPackages` 에 `runtimeOnly` 파라미터 + 필터링 분기.
   - `_printLicenseWarnings` 에 `--runtime-only` 힌트 꼬리 한 줄.
6. `bin/flutter_oss_manager.dart` — `--runtime-only` 플래그 추가 + 분기.
7. `test/license_generator_test.dart` — 통합 시나리오 (`runtimeOnly: true`) 추가.

**완료 조건**: 통합 테스트 통과. 기존 테스트 회귀 없음.
**커밋**: `feat(cli): add --runtime-only flag to scan command`

### Phase 4 — 검증

**목표**: 실 프로젝트에서 결과 확인.

8. `example/` 에서 전/후 diff 캡처:
   ```bash
   dart run flutter_oss_manager scan -o /tmp/all.g.dart
   dart run flutter_oss_manager scan --runtime-only -o /tmp/runtime.g.dart
   diff <(grep 'name:' /tmp/all.g.dart) <(grep 'name:' /tmp/runtime.g.dart)
   ```
9. 예상 배제 패키지 (`build_runner`, `flutter_lints`, `test`, `analyzer`, ...) 가 실제
   빠지고, 공유 패키지 (`collection`, `meta`, `async`) 는 유지되는지 육안 검증.
10. `flutter_test` 가 기대대로 배제되는지 확인 (§10-3 의 관찰 항목).

**완료 조건**: diff 결과가 기대와 일치. 예상치 못한 누락·포함 없음.
**블로커 시**: Phase 1~3 로 돌아가 수정. 퍼블리시 금지.

### Phase 5 — 릴리즈

**목표**: 문서화 + 버전 공개.

11. `README.md` — §8.1 의 "Excluding dev dependencies" 섹션 추가.
12. `CHANGELOG.md` — §8.2 의 2.2.0 엔트리 추가.
13. `pubspec.yaml` 버전 `2.1.0 → 2.2.0`.
14. 태깅 (`v2.2.0`) + `dart pub publish`.

**커밋**: `chore: release 2.2.0`

---

diff 예상 규모: 신규 ~300 LoC (그래프 본체 ~120 + `PubspecReader` 구현 ~60 + 테스트 ~120),
기존 수정 ~30 LoC. 기존 로직은 **한 줄도 안 지움**.

---

## 10. 오픈 이슈 (결정 필요)

1. **플래그 이름**: `--runtime-only` vs `--exclude-dev` vs `--production`. 현재 초안은
   `--runtime-only` 로 작성 — 승인 또는 대안 선택 필요.
2. **기본값 변경 여부**: 장기적으로 "런타임만 수집" 을 기본으로 바꿀지 (3.0.0 breaking
   후보). 현재 기획은 2.2.0 에서 무조건 옵트인 유지. 3.0.0 에서 기본값 전환을 고려할지
   결정해두면 README 에 deprecation 노트를 미리 넣을 수 있음.
3. **`flutter_test` 처리**: 대부분 프로젝트에서 `dev_dependencies` 인데, 일부 테스트
   지원 패키지가 런타임 경로로 유입되는 엣지 케이스가 있을 수 있음. 실 프로젝트 검증
   (§7.3) 에서 관찰 필요.

---

## 11. 알려진 제한 (이번 버전에서 해결 안 함)

- **pub workspaces 미지원**: Dart 3.6+ 의 pub workspaces 기능을 사용하는 사용자 프로젝트
  (루트에 `workspace:` 리스트가 있거나 `resolution: workspace` 로 상위에 귀속된 멤버) 는
  단일 `projectRoot/pubspec.yaml` 가정이 성립하지 않음. 현재 구현은 `Directory.current`
  의 pubspec 한 개만 읽음. workspace 지원은 수요 발생 시 후속 버전에서 검토. Flutter SDK
  내부가 workspace 를 쓰는 건 무관 — 우리는 SDK 의 `flutter/pubspec.yaml` 만 직접 읽음.
- **`PUB_CACHE` 환경변수 미반영**: 기존 `_getPubCacheDir()` (license_generator.dart:724)
  가 `LOCALAPPDATA`/`HOME` 만 보고 `PUB_CACHE` env override 를 무시하는 기존 동작. 그래프
  워커도 동일 헬퍼를 재사용하므로 동일 제한을 상속. 별도 PR 에서 수정 예정 (이번 범위
  밖).
