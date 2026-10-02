# Orchestrator handoff

For a new coordinator of the herdr project `slingfall-glam`, possibly on another machine.
Everything needed to continue is in this repository and the project folder; nothing depends on a
previous session's scratchpad, worktrees or local memory.

## Read first, in this order

1. `hp context slingfall-glam` (state, inbox, open threads; `hp` is the command prefix your skill
   gives you), the rules file and `standard/transition.md` of the project folder, then
   `/home/claude/projects/slingfall/OPERATIONS.md` (programme operating document).
2. `AGENTS.md` (rules for every agent), `docs/ORCHESTRATOR.md` (how this track briefs and
   delegates: threads, profiles, review threads, merge line).
3. `docs/DESIGN.md` (decisions; changing one is the orchestrator's call and is recorded there).
4. `docs/PLAN.md` (latest status first) and `docs/PORTING_STATUS.md` (live status, one row per
   task).
5. `docs/briefs/` (every brief ever given to a porter: `COMMON.md` + one file per task; reuse
   them as templates), `docs/API_PARITY.md` (generated parity table against glam-rs 0.33.8),
   `docs/PACKAGES.md`, `CHANGELOG.md`.
6. `docs/research/00-synthesis.md` then reports 01-06 when evidence is needed.

## Repositories and local layout (since 2026-09-25, `docs/SPLIT.md`)

This orchestrator owns three repositories; `glam-cairo` is its home (orchestration documents,
briefs, research, audits):

| repository | package | local checkout |
|---|---|---|
| `bal7hazar/fixed-cairo` | `fixed` | `/home/claude/projects/fixed-cairo` |
| `bal7hazar/glam-cairo` | `glam` (depends on the published `fixed`) | `/home/claude/projects/glam-cairo` |
| `bal7hazar/glamx-cairo` | `glamx` (depends on the published `fixed`, `glam`) | `/home/claude/projects/glamx-cairo` |

The siblings `nalgebra-cairo` and `rapier-cairo` have their own orchestrators; they escalate to
this one (scalar kernels go to `fixed-cairo`). A task on `fixed-cairo` / `glamx-cairo`: write the
brief here (`docs/briefs/`, merged to `glam-cairo` `main`), start a thread whose task names the
repository and tells it to read the brief and `COMMON.md` / `R1-common.md` from the `glam-cairo`
checkout (absolute path, read-only). A MINOR bump of `fixed`
means a pull request in each consuming repository (`glam-cairo`, `glamx-cairo`, the siblings).

## Machine setup

- asdf with `scarb` and `starknet-foundry` at the versions of `.tool-versions`; Rust (`cargo`)
  for `tools/refgen`; Python 3; `gh` authenticated with push rights on the repositories.
- `scripts/check.sh` is the full gate (fmt, lint, build, tests, gas snapshots, golden vectors,
  API parity, docs); the pull-request CI runs it. Locally, checks are crate-scoped.
- No sub-agent CLI login is needed: threads run through herdr on the pooled accounts. Read
  `machine-capacity` before placing a thread.
- Reference sources are re-cloned on demand into `/tmp` (the briefs say how): glam-rs 0.33.8,
  dimforge/glamx 0.3.1, parry, rapier.

## Operating loop

1. `hp context slingfall-glam`, `git fetch && gh pr list`. A pull request left by a thread is
   checked (scope = the brief's allowlist, report, gas table), then **reviewed by a review thread
   on another model: every pull request, documents included** (Overseer's rule, 2026-10-02).
   After a verdict that does not oppose it and green checks, merge:
   the coordinator runs
   `gh pr checks <n> -R <owner>/<repo> && gh pr comment <n> -R <owner>/<repo> --body "Review: <verdict>, highest finding <severity or none>, <model of the reviewer>, at <sha>" && gh pr merge <n> -R <owner>/<repo> --squash --match-head-commit <sha>`;
   or prompt the owning thread with `Merge the PR: review <verdict> at <sha>`, which then runs
   `gh pr checks <n> && gh pr merge <n> --squash --match-head-commit <sha>`. Then the shared-file updates
   (re-exports in `packages/*/src/lib.cairo`, `docs/PORTING_STATUS.md`, `CHANGELOG.md`, and
   `docs/DESIGN.md` when a decision was taken) go through a thread's pull request.
2. After merging a pull request that touched shared generated files (`docs/API_PARITY.md`,
   `tools/refgen/src/**`, the READMEs' gas tables), re-run the matching `--check` on `main`
   (`python3 scripts/api_parity.py --check`, `python3 scripts/gas_tables.py --check`, `cargo run
   --manifest-path tools/refgen/Cargo.toml -- check`, `cargo test --manifest-path tools/refgen/Cargo.toml`); if stale, start a thread to regenerate them.
3. New work: write `docs/briefs/<TASK>.md`, pre-declare any new stub in the shared `lib.cairo`
   files, merge, then start a thread (profile per `docs/ORCHESTRATOR.md`) whose task points at the
   brief and `docs/briefs/COMMON.md`.
4. Lessons already paid for: a headless thread that ends its turn while a command runs in the
   background dies (briefs say "foreground"); test crates that are too large get the CI runner
   killed (table-driven tests, line caps, 6 fuzz properties max); parallel pull requests must
   not share a file (pre-declared stubs, one gas snapshot per module); estimates written in a
   brief can be wrong, the thread's measurement wins (`Mat3::from_quat`, trig gas targets).

## Releases

- **The owner or the project manager gives a written go per release** (conditions in
  `/home/claude/projects/pm/decisions/2026-09-25-release-go-delegated-to-pm.md`: green CI on
  `main` at the release commit, release checklist followed, version policy, dependency order
  `fixed` -> `glam` -> `glamx`, publication from the package's own repository). The orchestrator
  then tags and publishes; `SCARB_REGISTRY_AUTH_TOKEN` is never handled or printed. Publishing is
  an act reserved for the owner unless a delegation says otherwise (the standard).
- A toolchain bump needs no release.

## What remains

The live state is the latest status section of `docs/PLAN.md` (currently "Status (2026-10-02)"),
then `docs/PORTING_STATUS.md`; it supersedes anything older. In short: the toolchain bump (D-180,
Scarb 2.20.1 / snforge 0.64.0, `fixed` -> `glam` -> `glamx`), then idle; F8, P2 and D1 only on
request through the project manager.

- Released as of the 2026-09-29 resume point: `fixed` 0.4.0, `glam` 0.4.1, `glamx` 0.4.1
  (`docs/PLAN.md`).
- Escalations and cross-repository questions go to the project manager
  (`hp coordinator prompt slingfall`, first line `[from slingfall-glam]`), not directly to the
  siblings `nalgebra-cairo` and `rapier-cairo`, which have their own coordinators (scalar kernels
  go to `fixed-cairo`).
