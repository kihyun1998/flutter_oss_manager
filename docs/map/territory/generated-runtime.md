# generated-runtime

## What it is
The code that runs inside a consumer's app: the generated `OssLicense` class, the `OssLicenses` reference-counted lifecycle (`use`, `acquire`, `OssLicensesHandle.close`), and the platform decoders chosen by conditional import.

## Governing decisions
**None.** Designed in `v2_plan.md` (draft plan); the glossary's *GeneratedFiles* entry states the lifecycle.

## Design model
From the glossary and the template text in `generated_files.dart`:
- `use(body)` is the default: acquire, run, release in `finally` (CHANGELOG 2.3.0). `acquire()`/`close()` are for long-lived holders.
- First `acquire` decodes; later ones share the same `Future`. The last `close` drops the decoded list so it can be GC'd. A decode failure undoes its own ref-count.
- `close()` is idempotent per handle; over-releasing trips an `assert`.
- Decoders: `dart:io` gzip; web uses `DecompressionStream('gzip')` via `dart:js_interop`; the stub throws `UnsupportedError`. Import order is stub, `dart.library.io`, `dart.library.js_interop`.
- The static cache survives hot reload; regenerate → hot restart (header comment).
- `resetForTest` / `refCountForTest` are public test hooks in consumer code.

## Code
- `lib/src/generated_files.dart — _buildMainFileContent (OssLicense, OssLicensesHandle, OssLicenses), _buildIoContent, _buildWebContent, _buildStubContent`
- Compiled copy: `example/lib/oss_licenses.g.dart`; tests: `example/test/oss_licenses_use_test.dart`

## Reference behaviour
**None.**

## Cross-cutting invariants
- [payload-schema](../invariant/payload-schema.md) — `OssLicense._fromJson` is one of its sites.

## Blast radius
- [example-app](example-app.md) — its tests are the only ones that execute this code (CI comment on the `example` job).
- [generated-files](generated-files.md) — this code is a string template there; a syntax error is not caught by the package's own analyze.

## Known holes / open
- The web decoder needs `DecompressionStream`; no browser floor is stated in README.
