# Orchestrating the glam track

For the coordinator of the herdr project `slingfall-glam` (repositories `fixed-cairo`,
`glam-cairo`, `glamx-cairo`). Porter-side rules live in `AGENTS.md`, design decisions in
`docs/DESIGN.md`, sequencing in `docs/PLAN.md`, the starting point of a new coordinator in
`docs/HANDOFF.md`.

Role of the coordinator: split, brief, delegate, review, merge. It never implements anything
large directly.

## Execution: herdr threads, under the standard

Since 2026-10-02 the track runs as a herdr project. How threads are started, prompted, reviewed
and merged is defined by the organisation's standard (the rules file of the project folder, and
`standard/transition.md` for what replaced each `nexus` command), and the programme rules (machine
budgets, domain rules, merge gates, releases) by `/home/claude/projects/slingfall/OPERATIONS.md`
(sections 3, 5, 6 and 7). They are not restated here.

What is specific to this track:

- One task = one thread (own worktree, branch, pull request, report). The task text names the brief
  `docs/briefs/<TASK>.md` and `docs/briefs/COMMON.md`.
- Profile by difficulty:

| difficulty | profile | examples |
|---|---|---|
| mechanical, well framed | `impl-sonnet` (default) | template-generated code, test compaction, spec alignment, benching variants already identified |
| standard port with numerics, hard or numeric work | `impl-opus` | a new module: kernels, tests, golden vectors, benches |
| exceptional | `impl-fable` | only when the owner asks for it by name, or after `impl-opus` has failed twice on the same task; never because a task looks hard |

- Reviews: **every pull request, documents included, gets a review thread on another model before
  merge** (Overseer's rule, 2026-10-02): `review` (Sonnet) for code written by Opus or Fable,
  `review-opus` for code written by Sonnet, with the standard's review text. An audit thread
  (`audit`) is the exception, not routine. Codex is not used.
- Merges (the standard, section "Close a task"), after a review that does not oppose it and green
  checks: the coordinator runs
  `gh pr checks <n> -R <owner>/<repo> && gh pr comment <n> -R <owner>/<repo> --body "Review: <verdict>, highest finding <severity or none>, <model of the reviewer>, at <sha>" && gh pr merge <n> -R <owner>/<repo> --squash --match-head-commit <sha>`;
  the owning thread runs `gh pr checks <n> && gh pr merge <n> --squash --match-head-commit <sha>` on the line
  `Merge the PR: review <verdict> at <sha>`. Never `--admin`; a
  refusal by the permission system is not worked around, its text goes up to the project manager.
- Capacity: read `machine-capacity` before placing a thread (the VPS is shared, one heavy suite at
  a time; the Mac with `--machine mac`). Under 20 % of pool quota, fewer threads.
- Legacy, kept until the owner decides: `scripts/agent.sh` (systemd-launched `claude -p` /
  `codex exec`), the `.claude/worktrees/` layout, `~/orchestrator/capacity.json`, the old "at most
  4 sub-agents" rule and the untracked `REPORT.md` in a worktree. Start nothing through them and
  remove nothing without asking; the report of a thread is the file its brief names.
- Timing measurements (CI layout, compile time, test runtime) come from GitHub runners (a draft
  pull request and its job timings), not from the shared machine. Gas numbers are unaffected:
  snforge counts gas, not seconds.
- Local checks are crate-scoped; the pull-request CI is the full gate. Where a brief asks for the
  full gate locally: `flock /tmp/glam-cairo-gate.lock scripts/check.sh` (the `glam_tests` compile
  peaks at ~12 GB).
- Numeric results are API (`docs/DESIGN.md`): a change in a result stops the task and goes up to
  the project manager.

## Briefs live in the repository

Task briefs are committed under `docs/briefs/<TASK>.md` and share `docs/briefs/COMMON.md` (rules,
definition of done, report format). A task for a thread names the brief and `COMMON.md`.
Committed briefs document what was asked and survive any session.

### The brief (in this order)

1. Files to read first (`AGENTS.md`, `docs/DESIGN.md`, style precedents on `main`).
2. Strict scope: a file allowlist; everything else is forbidden. Shared files (`lib.cairo`,
   `Scarb.toml`, CI, design docs, CHANGELOG, status) belong to the orchestrator: the thread lists
   its needs in an "Escalations" section of the report instead of editing them.
3. Expected API (exact names from the source being ported), numeric semantics, what is
   explicitly deferred (DEFER).
4. Efficiency rules and numeric targets (gas/steps); variants to bench when the formulation is
   not obvious (the winner in the library, the losers in `benches::alt` with their benches).
5. Tests: table-driven, compile budget (max file size, max number of fuzz tests), golden vectors
   from the reference oracle, panics with exact messages.
6. Definition of done: checks scoped to what was touched, gas snapshots regenerated, conventional
   commits, push, pull request following the template, CI green, never merge unless prompted,
   report in the format of the standard.
7. Work autonomously, do not widen the scope; an unanswered design question goes under
   Escalations.

## Conflict-free parallelism

- Pre-declare every stub (modules, tests, benches, golden files) in the shared files before
  launching a wave; one gas snapshot per module. Parallel PRs then never touch a common file.
- Waves follow the dependency graph; a wave starts when its dependencies are merged.
- After each merge, updates to re-exports, status, changelog and design decisions are shared-file
  changes: they go through a thread's pull request like any other change.

## Quality control

- Merge only on green CI and a review verdict that does not oppose (API parity, deviations, gas
  table).
- An interrupted thread is prompted to continue rather than relaunched from scratch.
- Watch the compile budget of the test crates: it is the first cause of CI failure observed.
