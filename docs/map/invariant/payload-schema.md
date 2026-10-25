# payload-schema

## The fact
The JSON keys `encodePayload` writes for each license — `name`, `version`, `licenseText`, `licenseSummary`, `repositoryUrl`, `description` — are exactly the keys the generated `OssLicense._fromJson` reads, with the same nullability.

## Why it is cross-cutting
The writer is Dart code run by the generator; the reader is a string template emitted into the consumer's app and compiled there. They never call each other and share no constant. `decodePayloadForTesting` is a third, hand-written copy of the reader, so a package test can pass against a key the shipped reader does not know.

## Territories it holds in
- [generated-files](../territory/generated-files.md) — `payload_codec.dart — encodePayload`, `decodePayloadForTesting`
- [generated-runtime](../territory/generated-runtime.md) — `generated_files.dart — _buildMainFileContent`, `OssLicense._fromJson` in the template

## What a violation looks like
A renamed or added key: the package's tests pass, and the consumer's app throws a cast error (`null as String`) on first `acquire()`. Only `example/test/` would catch it, after regenerating `example/lib/*.g.dart`.

## Discovery history
- Found by reading, 2026-10-24: the three key lists sit in two files with no shared definition.

## Where it will recur
Any change to `OssLicense`'s fields (`lib/src/models/oss_license.dart`): if a function serializes or deserializes the payload, it is subject to this.
