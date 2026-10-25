# ci

## What it is
`.github/workflows/ci.yml`: format, analyze and test for the package and the example on a pinned Flutter; and the planned Dependabot configuration.

## Governing decisions
- [ADR-0001](../../adr/0001-generated-files-excluded-from-dart-format.md) — the format check covers `git ls-files '*.dart' ':!:*.g.dart'` only.

## Design model
From the workflow:
- Two jobs, `package` and `example`, on push to `main` and every PR.
- Flutter pinned in `env.FLUTTER_VERSION` "so CI does not drift with the runner's default Flutter".

## Code
- `.github/workflows/ci.yml`
- Dependabot: **None.** Planned in issue #8: root pub weekly, `increase-if-necessary`, one PR per dependency; `/example` monthly, grouped, Riverpod majors ignored; Actions monthly, grouped. A first slice is `.github/dependabot.yml`.

## Reference behaviour
**None.**

## Cross-cutting invariants
**None.**

## Blast radius
- [generated-files](generated-files.md) — dropping the `*.g.dart` exclusion would make a format pass invalidate the hashes the integrity test checks.
- [example-app](example-app.md) — the `example` job is its only build.

## Known holes / open
- Dependabot not built (Tracked: #8).
