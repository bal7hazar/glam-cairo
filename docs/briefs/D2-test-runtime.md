# D2 - test runtime: split the test crate, run what a change affects

Branch `chore/test-runtime`. Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`,
`scripts/check.sh`, `scripts/bench.py` (its `check_targets` guard), `packages/benches/Scarb.toml`
(one `[[test]]` target per bench file since #33) and `.github/workflows/ci.yml`. This brief asks
for measurements: run the full gate locally when you need a before / after number (under
`flock /tmp/glam-cairo-gate.lock`), otherwise follow the interim rule.

Files you may edit: `packages/glam/Scarb.toml`, `packages/glam/tests/**` (moving code between
test files, helper modules; no test may be weakened or dropped), `packages/benches/Scarb.toml`,
`scripts/**`, `.github/workflows/ci.yml`, `AGENTS.md` (commands table), `docs/briefs/COMMON.md`
and `docs/briefs/R1-common.md` (replace the interim rule by the new one once it works).

## Facts

CI on `main`: `Test glam` 22 min 25 s = 3 min compiling one `glam_tests` crate (43 files,
1 684 tests) + ~19 min running them; every other job < 4 min. Locally the full gate is ~27 min.
Cause measured on the benches (#33): snforge's cost per test grows with the size of the compiled
test program (58 tests: 28 s inside the big crate, 1.3 s alone); one crate per bench file made the
bench run 12x faster (990 s -> 82 s), at the price of a longer cold compile (27 s -> 200 s: each
crate recompiles the library).

## Prior art in the sibling repositories (measured on their `main`, 2026-09-25)

- `nalgebra-cairo` (`.github/workflows/ci.yml`, read it with `gh api
  repos/bal7hazar/nalgebra-cairo/contents/.github/workflows/ci.yml -q .content | base64 -d`):
  tests spread over ~20 small test packages and a **24-job matrix**, each job running
  `snforge test -p <package> <filter>` for its shard and checking the benches it ran against the
  snapshot (`--partial`), then a final job checking every bench against the full snapshot;
  longest job ~6 min, whole run ~8 min.
- `rapier-cairo`: a 4-group test matrix, longest job ~4.5 min, whole run ~5 min.
Neither selects tests by diff yet: part 2 below is a pilot. Reuse what fits; `glam-cairo` keeps
`all-checks` as the single required status.

## 1. Split the glam test crate

Explicit `[[test]]` targets (`test-type = "integration"`) instead of the auto-detected
`tests/lib.cairo`. Measure at least: one crate per test file; a handful of groups (by module
family: vectors, matrices, quat / affine / euler, camera, integer vectors, swizzles); and the
groups spread over a CI matrix (each job compiles only its groups, so compile time is
parallelised too). Pick the layout that minimises the wall time of `all-checks` in CI and of the
local test step; report the table (compile / run / wall / peak RSS). Shared test helpers: a
helper module per crate, or a small unpublished `glam_testing` package; no duplication of large
code. A guard (like `bench.py check_targets`) fails if a test file is not in any target.

## 2. Run only what a change affects

`scripts/affected.py <base>`: from `git diff --name-only <base>...HEAD`, the set of test targets
and bench modules to run:
- `packages/glam/src/<m>.cairo`: `<m>` and every module that imports it, transitively (parse the
  `use crate::...` / `use glam::...` lines of `packages/glam/src`), their test files, goldens and
  benches;
- a test / golden / bench file: itself;
- `tools/codegen/<gen>.py` or its templates: every module it generates; `tools/refgen/specs/<m>`
  or `oracles/<m>`: `<m>`'s goldens;
- anything else that can change every result (`Scarb.toml`, `Scarb.lock`, `.tool-versions`,
  `packages/*/Scarb.toml`, `scripts/**`, `.github/**`, an unknown path): everything;
- docs only (`*.md`, `docs/**`): no test, the doc checks only.
`scripts/check.sh --affected <base>` runs fmt, lint, build, the affected test targets, `bench.py
check` on the affected modules and every script `--check`. CI: `pull_request` runs the affected
set, `push` to `main` runs everything (and a release is only cut from a `main` commit whose full
run is green); `all-checks` stays the single required status. Unit-test `affected.py` on a
table of example diffs.

## Done

The new layout green in CI (full run on your branch: trigger it with `workflow_dispatch` or a
temporary full-run flag, then the affected run on the pull request), before / after timings in
the pull request body, `docs/briefs/*` rule updated, `REPORT.md`. Commit scope `chore(ci)` /
`chore(tests)`. Do not merge.
