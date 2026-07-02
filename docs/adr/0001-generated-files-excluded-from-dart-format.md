# 1. Generated `.g.dart` files are excluded from `dart format`

Date: 2026-07-02

## Status

Accepted

## Context

The tool emits four `.g.dart` files (main + stub/io/web decoders). Each file's
header carries a crc32 **content-hash computed over the file's exact bytes**
(`_finalizeHeader` in the generated-files renderer).

We considered making the emitted code `dart format`-clean so that a consumer
running `dart format .` in their project would be a no-op and not disturb the
hash. Investigation showed this is **not achievable**:

- **`dart format`'s style is language-version-dependent.** This package's
  `pubspec.yaml` floors the SDK at `>=3.4.0`, so `dart format` here formats in
  the pre-3.7 ("short") style. A consumer on a newer language version gets the
   "tall" style, which wants the *opposite* indentation. No single emitted
  output is format-clean across language versions, so we cannot win this by
  matching one formatter.
- **Reformatting would invalidate the content-hash**, because the hash is
  computed over the exact pre-format bytes. Running `dart format` on a generated
  file rewrites bytes after the hash was embedded.
- **The content-hash is not verified at runtime.** Nothing reads it — the
  decoder uses the payload directly and there is no `verify` command. So a
  consumer's `dart format` "breaking" the hash has no functional consequence.
- The files are already marked `// GENERATED CODE - DO NOT MODIFY BY HAND`;
  excluding generated code from formatting/linting is the standard convention.

## Decision

Do **not** attempt to make the generated output `dart format`-clean. Instead,
**exclude `*.g.dart` from the format check** (CI formats
`git ls-files '*.dart' ':!:*.g.dart'`), and leave the emitted formatting as the
renderer produces it. Consumers who format their projects should likewise
exclude generated files (the DO-NOT-MODIFY header signals this).

## Consequences

- CI's format gate covers hand-written sources only; the generated files are
  deterministic (byte-stability + content-hash tests still guard them).
- No dependency on `dart_style` and no format-before-hash machinery.
- If a future change makes the tool *verify* the content-hash (e.g. a `verify`
  command), reconsider: at that point emitting format-stable output — or
  formatting-then-hashing at generation time — would matter, and this decision
  should be revisited.
