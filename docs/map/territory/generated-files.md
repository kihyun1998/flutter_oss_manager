# generated-files

## What it is
The four files a scan emits — main plus stub/io/web decoder sidecars — produced as data by the pure `renderGeneratedFiles` and written by the caller (glossary: *GeneratedFiles*).

## Governing decisions
- [ADR-0001](../../adr/0001-generated-files-excluded-from-dart-format.md) — generated files are not `dart format`-clean; CI excludes `*.g.dart` from the format check.

## Design model
From the glossary, ADR-0001 and the source:
- The license list is JSON → deterministic gzip (mtime 0, OS 255) → base64, one string constant in the main file; byte-stable across runs.
- Each file's header has `content-hash: crc32:<hex>`, the CRC32 of the body with the placeholder zeroed. Nothing verifies it at runtime ([ADR-0001](../../adr/0001-generated-files-excluded-from-dart-format.md)); `test/generated_integrity_test.dart` checks it for the committed files.
- Header stamps `packageVersion`.
- Sidecar paths derive from `--output`: strip `.dart` then `.g`; sidecars are `<base>_decoder_{stub,io,web}<suffix>`.
- Overwrites silently.

## Code
- `lib/src/generated_files.dart — renderGeneratedFiles, _finalizeHeader, _buildMainFileContent, _buildStubContent, _buildIoContent, _buildWebContent`
- `lib/src/payload_codec.dart — encodePayload, gzipDeterministic, crc32, resolveSidecarPaths, decodePayloadForTesting`
- Tests: `test/generated_files_test.dart`, `test/payload_codec_test.dart`, `test/generated_integrity_test.dart`

## Reference behaviour
**None.**

## Cross-cutting invariants
- [payload-schema](../invariant/payload-schema.md) — `encodePayload` writes the keys the generated `_fromJson` reads.

## Blast radius
- [generated-runtime](generated-runtime.md) — the templates here *are* that code; a change ships into every consumer's app on their next scan.
- [example-app](example-app.md) — the only place the emitted code is compiled and run; its committed `.g.dart` files must be regenerated after a template change.
- [publishing](publishing.md) — the committed `lib/*.g.dart` must be regenerated too, and the header stamps the version.
- [ci](ci.md) — the format check's `*.g.dart` exclusion is what keeps the hash valid.

## Known holes / open
- If a `verify` command is ever added, ADR-0001 says to revisit (its Consequences).
- The integrity test checks a committed file's hash against its own body, not against the current renderer; a stale committed file passes.
