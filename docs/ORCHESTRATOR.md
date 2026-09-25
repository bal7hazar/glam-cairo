# Sub-agent strategy (orchestrator)

Instructions for the orchestrator session. This file is meant to be pasted verbatim into the
prompt of an orchestrator of another repository (nalgebra-cairo, rapier-cairo). Porter-side rules
live in `AGENTS.md`, design decisions in `docs/DESIGN.md`, sequencing in `docs/PLAN.md`.

Role of the main session: orchestrate, split, brief, review, merge. Never implement anything
large directly.

## Execution: local CLIs, not the Agent tool

- The Agent tool burns the orchestrator session's quota: use it only for short, read-only
  research.
- Every sub-task runs in its own git worktree + branch (`feat/<module>`), launched in the
  background with its output redirected to a log file.
- Two CLIs with **distinct roles** (owner's rule, 2026-09-25, programme decision
  `/home/claude/projects/pm/decisions/2026-09-25-codex-audits-only.md`):
  - every **implementation / tooling lot runs on the `claude` CLI** (Opus or Sonnet by
    difficulty, table below);
  - **`codex` is used sparingly, only for audits and second opinions**: a review of a merged lot,
    a cross-check of a numeric decision, an independent opinion on a design. Its quota is small
    and shared between the repositories; it must stay available for that.
  Commands:
  - `claude -p "$(cat brief.md)" --model <sonnet|opus|fable> --dangerously-skip-permissions --name <task>`;
    resume with context: `claude --continue -p "<follow-up>"` in the same worktree.
  - `codex exec -C <worktree> -m <model> -c model_reasoning_effort=<low|medium|high|xhigh> --dangerously-bypass-approvals-and-sandbox -o REPORT.md "$(cat brief.md)"`.
- Launch through `scripts/agent.sh <task> <claude|codex> <model> <new|resume> "<prompt>"
  [codex-session-id] [effort]`: it starts the CLI from the worktree `.claude/worktrees/cli-<task>`
  as a **transient systemd user unit** (`systemd-run --user`, needs `loginctl enable-linger`),
  logs to `.claude/worktrees/logs/<task>.log` and writes `<task>.unit`; `scripts/agent.sh status`
  lists the agents, `scripts/agent.sh wait <task>` blocks until one exits (run it as a background
  command to be notified). Why: the orchestrator session itself runs inside the cgroup of a
  system service, and a restart of that service kills the whole cgroup. Observed twice on
  2026-09-21: five agents lost at once, first as plain background children, then again as
  `setsid nohup` children (a new session does not leave the cgroup). Every agent was resumed
  with its context: `claude --continue` in the worktree, `codex exec resume <session-id>`, the
  codex session id being the UUID of `~/.codex/sessions/<date>/rollout-*.jsonl` whose `cwd` is
  the worktree. Uncommitted work survives in the worktree; a build that was running at the time
  of the kill reports a spurious failure.
- Sonnet agents end their turn on a background command (gate, `gh pr checks --watch`) despite
  the rule in the brief (twice on R1m): put "run everything in the foreground, never
  `run_in_background`, your turn ends when REPORT.md is written" in the launch prompt itself
  for Sonnet, and expect to resume once. Opus and codex followed the brief.
- Machine at full CPU / memory (other repositories' agents): expect OOM kills and transient API
  529s; `scripts/agent.sh status` first, then resume with the context, never relaunch from
  scratch. Merge with `gh pr merge --squash` without `--delete-branch` (the agent's untracked
  `REPORT.md` blocks the worktree removal): archive the report, `git worktree remove --force`,
  delete the branch by hand.
- Naming (owner's rule, 2026-09-25): every background task, monitor or agent-launch description
  starts with the model used, e.g. `[gpt-5.6-sol] Wait for D2`, `[Sonnet 5] F7 hyperbolic
  kernels`; the orchestrator's own model for its non-agent tasks.
- Machine budget (programme rule, 2026-09-25, `/home/claude/projects/pm/OPERATIONS.md` section 3):
  **at most 4 sub-agents running machine-wide**, all repositories together. Count the running
  units (`systemctl --user list-units 'glam-agent-*' 'rapier-*' 'nalgebra-*' --state=running`)
  before launching.
- Timing measurements (CI layout, compile time, test runtime) come from GitHub runners (a draft
  pull request and its job timings), not from the shared machine, whose runs are queued behind
  the machine-wide lock and a CPU quota (D2, 2026-09-25). Gas numbers are unaffected: snforge
  counts gas, not seconds.
- A shared machine needs a lock around the full gate: briefs say
  `flock /tmp/glam-cairo-gate.lock scripts/check.sh` (the `glam_tests` compile peaks at ~12 GB).
- The agent writes a `REPORT.md` (not committed) at the root of its worktree: the orchestrator
  reads that file and the log, not the transcript.

## Briefs live in the repository

Task briefs are committed under `docs/briefs/<TASK>.md` and share `docs/briefs/COMMON.md` (rules,
definition of done, report format). A porter is launched with a one-line prompt:
`"Read docs/briefs/<TASK>.md and docs/briefs/COMMON.md, then execute the task."` Session
scratchpads do not survive a reboot; committed briefs do, and they document what was asked.

## Model choice by difficulty

Implementation lots (`claude` CLI):

| difficulty | model | examples |
|---|---|---|
| mechanical, well framed | Sonnet (`--model sonnet`) | template-generated code, test compaction, spec alignment, benching variants already identified |
| standard port with numerics | Opus (`--model opus`) | a new module: kernels, tests, golden vectors, benches |
| genuinely complex | Fable 5.1 (`--model fable`) | novel numerics, hard debugging, cross-module design, API arbitration |

Audits and second opinions only (`codex` CLI): `gpt-5.6-*` (effort `high`) for a review of a
merged lot or a numeric cross-check, `gpt-6-astra` (effort `xhigh`) for an independent opinion on
a hard design. Never an implementation lot. (History: R1e, R1h, R1d, F5, S2 and D2 ran on codex
before this rule; D2 finishes there unless it hits the quota, then it resumes on `claude` from
its worktree.)

- The strong models are not the default, but do not rule them out when the problem warrants
  them.
- The smaller the model (or the lower the effort), the tighter the brief must be.
- The codex model tiering is inferred from the names (`gpt-6-astra` above `gpt-5.6-*`, which are
  above `gpt-5.5`); adjust it if the actual ranking is known. An audit brief asks for a report
  (findings with evidence), not for a pull request that changes the library.

## The brief (mandatory, in this order)

1. Files to read first (`AGENTS.md`, `docs/DESIGN.md`, style precedents on `main`).
2. Strict scope: a file allowlist; everything else is forbidden. Shared files (`lib.cairo`,
   `Scarb.toml`, CI, design docs, CHANGELOG, status) belong to the orchestrator: the agent lists
   its needs in an "Escalations" section of the report instead of editing them.
3. Expected API (exact names from the source being ported), numeric semantics, what is
   explicitly deferred (DEFER).
4. Efficiency rules and numeric targets (gas/steps); variants to bench when the formulation is
   not obvious (the winner in the library, the losers in `benches::alt` with their benches).
5. Tests: table-driven, compile budget (max file size, max number of fuzz tests), golden vectors
   from the reference oracle, panics with exact messages.
6. Definition of done: the full gate run in the **foreground** (never a background command
   followed by the end of the turn: in headless mode the session stops), gas snapshots
   regenerated, conventional commits with the trailer, push, PR via `gh pr create` following the
   template, `gh pr checks --watch` until green, **never merge**, `REPORT.md` in the imposed
   format (summary, API, gas table, deviations, deferred items, requested re-exports,
   escalations, PR URL).
7. "Work autonomously, do not ask questions, do not widen the scope."

## Conflict-free parallelism

- Pre-declare every stub (modules, tests, benches, golden files) in the shared files before
  launching a wave; one gas snapshot per module. Parallel PRs then never touch a common file.
- Waves follow the dependency graph; a wave starts when its dependencies are merged.
- After each merge, the orchestrator alone updates re-exports, status, changelog and design
  decisions, then pushes to `main`.

## Quality control and quota

- Merge only on green CI + a review of the report (API parity, deviations, gas table).
- An interrupted agent (rate limit, end of turn) is resumed with `claude --continue -p` rather
  than relaunched from scratch.
- Watch the compile budget of the test crates: it is the first cause of CI failure observed.
