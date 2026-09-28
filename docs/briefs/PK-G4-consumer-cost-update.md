# PK-G4 - shared `consumer_cost.py` update; glamx dependency measurement

Small lot (Sonnet). Read `docs/briefs/R1-common.md` and `docs/briefs/COMMON.md` (foreground only;
crate-scoped local checks; CI is the full gate; cold builds under
`flock ~/orchestrator/heavy-build.lock`; timings from GitHub runners).

## 1. Update the shared script in the three repositories (one pull request each)

Copy `scripts/consumer_cost.py` **unchanged** from nalgebra-cairo `7177cf3` (its PR #63):
`gh api "repos/bal7hazar/nalgebra-cairo/contents/scripts/consumer_cost.py?ref=7177cf3" -q .content | base64 -d`
(read its docstring and nalgebra's `consumer_cost.toml` at the same ref for the new keys). New:
`marginal_*` figures (consumer of the crate minus consumer of its direct dependencies together),
closures with registry crates (`[closures]`), `facades = [...]` (a facade is judged on gate 3
only), `--manifest-path` before the subcommand, `--dry-run`, `--self-test`, `--repeat 3`.
In `fixed-cairo`, `glam-cairo`, `glamx-cairo`: update `consumer_cost.toml` so that gate 2 uses the
marginal figures; in glam-cairo declare `facades = ["glam"]`; in glamx-cairo a closure with the
registry crates (e.g. `glamx` with `glam@0.4.1` and `fixed@0.4.0`); CI invocation adapted
(`--repeat 3` if the job time allows it), `--self-test` run once in CI. No release.

## 2. glamx: depend on the `glam` facade or on the sub-crates?

`glamx` depends on the `glam` facade today. Check which sub-crates it really uses (grep its
`use glam::...`: `Vec2/3`, `Mat2/3`, `Quat`, `BVec*` are in `glam_core`; swizzles or integer
vectors would add `glam_swizzles` / `glam_int`). Measure, on a scratch branch of glamx-cairo (never
merged), the closure of an empty consumer of `glamx` both ways: (a) `glam = "0.4.1"` (today), (b)
`glam_core = "0.4.1"` (+ the other sub-crates only if used), with `--repeat 3` on a GitHub runner:
lines, added time, added memory, and whether glamx's gas snapshots stay identical in (b). Report
the figures; the dependency change itself would ship in glamx's next release, on the programme
session's go: do not merge it in this lot.

Worktrees prepared by the orchestrator (branch `chore/consumer-cost-7177cf3`): glam-cairo, fixed-cairo
and glamx-cairo, each at `.claude/worktrees/cli-pkg4`. Pull requests: one per repository for
part 1; part 2 reported in `REPORT.md` (in the glam-cairo worktree) with the scratch branch name.
