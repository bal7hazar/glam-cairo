# Orchestrator handoff

For a new orchestrator session, possibly on another machine. Everything needed to continue is in
this repository; nothing depends on a previous session's scratchpad, worktrees or local memory.

## Read first, in this order

1. `AGENTS.md` (rules for every agent), `docs/ORCHESTRATOR.md` (how the orchestrator spawns and
   briefs sub-agents: local `claude -p` / `codex exec` CLIs, model choice, brief format).
2. `docs/DESIGN.md` (decisions; changing one is the orchestrator's call and is recorded there).
3. `docs/PLAN.md` (waves) and `docs/PORTING_STATUS.md` (live status, one row per task).
4. `docs/briefs/` (every brief ever given to a porter: `COMMON.md` + one file per task; reuse
   them as templates), `docs/API_PARITY.md` (generated parity table against glam-rs 0.33.8),
   `CHANGELOG.md`.
5. `docs/research/00-synthesis.md` then reports 01-06 when evidence is needed.

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
brief here (`docs/briefs/`, pushed to `glam-cairo` `main`), create the worktree in that
repository's checkout (`git -C /home/claude/projects/fixed-cairo worktree add
.claude/worktrees/cli-<task> -b <branch> origin/main`), launch with that repository's own
`scripts/agent.sh` (same interface), and tell the agent to read the brief and `COMMON.md` /
`R1-common.md` from the `glam-cairo` checkout (absolute path, read-only). A MINOR bump of `fixed`
means a pull request in each consuming repository (`glam-cairo`, `glamx-cairo`, the siblings).

## Machine setup

- asdf with `scarb` and `starknet-foundry` at the versions of `.tool-versions`; Rust (`cargo`)
  for `tools/refgen`; Python 3; `gh` authenticated with push rights on this repository.
- `scripts/check.sh` is the full gate (fmt, lint, build, tests, gas snapshots, golden vectors,
  API parity, docs). It takes 10-30 minutes depending on the machine load.
- Sub-agent CLIs: `claude` (check `claude auth status`: the account used for sub-agents is
  separate from the orchestrator's) for **every implementation lot**: `opus` for ports with
  numerics, `sonnet` for mechanical / tooling tasks, `fable` for genuinely hard numerics.
  `codex` (`codex login status`) **only for audits and second opinions** (owner's rule,
  2026-09-25: its quota is small and shared): a review of a merged lot, a numeric cross-check,
  an independent design opinion (`gpt-5.6-sol`, effort `high`). See `docs/ORCHESTRATOR.md`.
- Reference sources are re-cloned on demand into `/tmp` (the briefs say how): glam-rs 0.33.8,
  dimforge/glamx 0.3.1, parry, rapier.

## Operating loop

1. `git fetch && gh pr list`: a green pull request left by a porter is reviewed (scope = the
   brief's allowlist, report in the PR body, gas table) and squash-merged; then the orchestrator
   alone updates re-exports (`packages/*/src/lib.cairo`), `docs/PORTING_STATUS.md`,
   `CHANGELOG.md`, and `docs/DESIGN.md` when a decision was taken, and pushes to `main`.
2. After merging a pull request that touched shared generated files (`docs/API_PARITY.md`,
   `tools/refgen/src/**`, the READMEs' gas tables), re-run the matching `--check` on `main`
   (`python3 scripts/api_parity.py --check`, `python3 scripts/gas_tables.py --check`, `cargo run
   --manifest-path tools/refgen/Cargo.toml -- check`, `cargo test --manifest-path tools/refgen/Cargo.toml`) and regenerate if stale.
3. New work: write `docs/briefs/<TASK>.md`, pre-declare any new stub in the shared `lib.cairo`
   files, push, create a worktree + branch from `origin/main`, launch the porter with a one-line
   prompt pointing at the brief and `docs/briefs/COMMON.md`.
4. Lessons already paid for: a headless agent that ends its turn while a command runs in the
   background dies (briefs say "foreground"); test crates that are too large get the CI runner
   killed (table-driven tests, line caps, 6 fuzz properties max); parallel pull requests must
   not share a file (pre-declared stubs, one gas snapshot per module); estimates written in a
   brief can be wrong, the agent's measurement wins (`Mat3::from_quat`, trig gas targets).

## What remains (see `docs/PORTING_STATUS.md` for the live state)

- Released: `fixed`, `glam`, `glamx` 0.3.0 on scarbs.xyz (tags `v0.1.0`..`v0.3.0` of this
  repository). **The owner or the programme session gives a go per release** (delegation
  confirmed by the owner in this orchestrator's session on 2026-09-25; conditions in
  `/home/claude/projects/pm/decisions/2026-09-25-release-go-delegated-to-pm.md`: green CI on
  `main` at the release commit, release checklist followed, version policy, dependency order,
  publication from the package's own repository). The go is written (cross-session message +
  a line in `pm/decisions/` or `pm/STATUS.md`); the orchestrator then tags and publishes
  (`SCARB_REGISTRY_AUTH_TOKEN` is in the owner's `~/.claude/settings.json`; never handled).
  From now on each package is released from its own repository.
- Next task: **D2** (`docs/briefs/D2-test-runtime.md`): split the `glam` test crate (CI `Test
  glam` is 22 min, ~19 of them running 1 684 tests in one crate) and run only what a change
  affects on pull requests (`scripts/affected.py`), full run on `main`. Until it lands, the
  interim rule holds: agents run targeted checks, the pull request CI is the full gate.
- Debt: D1 (in `fixed-cairo`: `gen_trig.py` / `gen_exp.py` need numpy / mpmath and their fits
  depend on the numpy version); Dependabot is active on the two new repositories; the golden
  files of `fixed-cairo` still say "glam-rs 0.33.8 (f64)" in their header (kept byte-identical
  on purpose).
- Programme management (since 2026-09-25): a project-manager session ("Angry Birds Cairo
  orchestration", documents in `/home/claude/projects/pm/`, messages to this orchestrator in
  `pm/messages/to-glam/`) coordinates the repositories for the target game (a 2D Angry Birds-like
  game on rapier-cairo, local proving, on-chain verification). Escalations and cross-repository
  questions go through it, not directly to the siblings. Pending from it: F7 (hyperbolic kernels
  in `fixed-cairo`, after D2) and P2 (`glamx::Pose2` kernels, only if the parry split is approved).
- Sibling coordination: `nalgebra-cairo` pins `fixed` 0.3.0 and delegates `Real::div` / `recip`
  to `/` / `recip`; it splits its `simba` crate into `simba-cairo`; `rapier-cairo` decides
  whether a `parry-cairo` is split out. Their orchestrators own those tasks.
- Operational lessons (all in `docs/ORCHESTRATOR.md`): agents run as systemd user units
  (`scripts/agent.sh`), never as children of the session; Sonnet agents end their turn on
  background commands unless the launch prompt says "foreground only"; resume interrupted
  agents with their context (`claude --continue`, `codex exec resume <id>`); merge with
  `gh pr merge --squash` without `--delete-branch`, archive `REPORT.md`, remove the worktree.
