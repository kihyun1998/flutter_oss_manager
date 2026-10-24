# pub-dev-lookup

## What it is
`HttpPubLicenseClient`: asks pub.dev for a package's SPDX id from its score tags.

## Governing decisions
**None.**

## Design model
From the source and README "License Detection":
- `GET <baseUri>/api/packages/<name>/score`; the first `license:*` tag that is not `license:fsf-libre` / `license:osi-approved` is the id. The `version` argument is not sent — the score is for the latest version, cached under the scanned version's key.
- Lowercase tags are mapped to SPDX casing by `_spdxCanonical`; an unlisted tag passes through lowercase ("a signal to expand this table", comment on `_spdxCanonical`).
- Every failure — timeout (5 s per stage), socket, TLS, HTTP, non-200, parse, no tag — is `null`.
- One `HttpClient` is reused for the whole scan and recreated after `close()`.
- User-Agent carries `packageVersion`.
- Input from outside: the response body is read whole with no size bound (`join()`), bounded only by the timeout.

## Code
- `lib/src/pub_license_client.dart — PubLicenseClient, HttpPubLicenseClient.fetchSpdxId, extractSpdxFromTags, _spdxCanonical, _licenseClassifierTags`
- Tests: `test/pub_license_client_test.dart`

## Reference behaviour
- [pub.dev API](../../agents/thegraph.md) — binding, but reached through published docs (summarized): the tag format and the `score` endpoint need confirming against real responses.

## Cross-cutting invariants
- [spdx-identifier-spelling](../invariant/spdx-identifier-spelling.md) — `_spdxCanonical` is one of its sites.

## Blast radius
- [spdx-resolution](spdx-resolution.md) — a non-null answer is cached as authoritative and wins over the matcher.
- [publishing](publishing.md) — the User-Agent stamps the package version.

## Known holes / open
- The score is for the latest version, not the scanned one; a package that changed license between versions is reported with the latest license. Tracked: #11
- Whether pana emits `license:gpl-3.0` or the current SPDX `license:gpl-3.0-only` form is not confirmed; `_spdxCanonical` only knows the former. Tracked: #19
