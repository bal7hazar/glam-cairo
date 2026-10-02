# PP: a pre-push check in fixed-cairo, glam-cairo and glamx-cairo

Owner's request of 2026-10-02 ("stop pushing red CI"; text:
`/home/claude/.herdr-projects/organisation/scratch/prepush-task.md`). Since 2026-10-01, about 15 of 22 red CI runs
across the programme would have been stopped by a local check of seconds to minutes (formatting, generated artefacts
not regenerated, unit tests of the Python scripts, compile errors); 6 were HTTP errors while downloading scarb or
snforge. One thread per repository, one pull request each. The thread's task names its repository: `<repo>` below.

## Read first

`AGENTS.md`, `scripts/check.sh` (the full gate: it stays the full gate, run by CI), `.github/workflows/ci.yml`,
`/home/claude/projects/slingfall/OPERATIONS.md` §3 (shared VPS: crate-scoped work, the heavy-build lock, never
`snforge test --workspace`). glam-cairo only: `scripts/affected.py` (maps changed paths to checks; reuse it).

## Allowlist

`scripts/prepush.sh` (new), `.githooks/pre-push` (new), `AGENTS.md` (one short section),
`.github/workflows/ci.yml` (only the tool-download retries below), unit tests for any new Python helper under
`scripts/tests/`. glam-cairo also: `docs/briefs/COMMON.md` (one line in its definition of done:
`scripts/prepush.sh` before every push). Nothing else.

## 1. `scripts/prepush.sh`

Bash, `set -euo pipefail`, runnable from any directory of the clone (cd to the repository root). Base: the merge
base with `origin/main` (overridable by a first argument). Prints each step and its duration, exits non-zero on the
first failure. Aim: under 2 minutes on this VPS for a typical change; measure, do not estimate.

Always:
- `scarb fmt --check --workspace`;
- the unit tests of the Python scripts, if the repository has any (`python3 -m unittest discover -s scripts/tests -p
  'test_*.py'`), and the cheap `--check` modes of the scripts that check documents against committed sources (for
  example `gas_tables.py --check`, `panic_coverage.py --check`, `api_parity.py --check`, `affected.py --check` where
  they exist and take seconds).

Only when their inputs changed since the base (decide from `git diff --name-only <base>...HEAD` plus uncommitted
changes):
- the compile of the touched packages: `scarb build -p <package>` for each package whose files changed (`scarb
  check -p` instead if Scarb 2.20.1 has it and it catches the same errors faster: measure both, say which you kept);
  a change to `Scarb.toml`, `Scarb.lock` or `.tool-versions` compiles the workspace;
- `scarb lint` on the touched packages (`--deny-warnings`, as CI);
- the generated artefacts whose inputs changed: code generators' `--check` (glam-cairo `tools/codegen/*.py`,
  glamx-cairo `gen_eigen3.py emit --check`), `bytecode_size.py check` when library sources or the toolchain changed.
  Gas snapshots (`bench.py check`) and the snforge test suites stay with CI (too long for a pre-push): say so in a
  comment at the top of the script, with the list of what is left to CI.

## 2. The hook

`.githooks/pre-push` (executable) runs `scripts/prepush.sh` and blocks the push on failure; a push that only deletes a
ref runs nothing. Set `git config core.hooksPath .githooks` in this repository's clone on the VPS
(`/home/claude/projects/<repo>`: the setting is shared by every worktree of the clone). The Mac clones are set later
by the orchestrator. Never bypass the hook (`--no-verify` is forbidden): your own push of this branch is its first
test.

## 3. AGENTS.md

A short section "Before every push": run `scripts/prepush.sh` (the hook does it); never push red; the full gate is
CI (`scripts/check.sh`), and what the pre-push leaves to CI.

## 4. Retries on the tool downloads, in `.github/workflows/ci.yml`

Every `software-mansion/setup-scarb` and `foundry-rs/setup-snfoundry` step gets up to two retries, without a new
third-party action: the first attempt gets an `id` and `continue-on-error: true`; a second identical step runs
`if: steps.<id>.outcome == 'failure'` (with its own `id` and `continue-on-error: true`), and a third runs if both
failed (no `continue-on-error`, so a third failure fails the job). Keep the pinned action SHAs. Change nothing else
in the workflow.

## Measures and report

Run on this VPS and paste the real output of `time scripts/prepush.sh`: (a) on the branch with no Cairo change (only
your scripts and docs); (b) after a throw-away local change of one Cairo source file of the main package (revert it,
never commit it). Name the machine. Show the hook blocking a push: with a throw-away formatting error, run the hook
directly (`.githooks/pre-push origin <url> </dev/null`, or what it needs) and paste its failing output; never push
the error. The CI of the PR must be green (the retry steps run and pass on their first attempt).

Done: conventional commits (`chore(ci): pre-push check and tool-download retries`), push (through the hook), PR,
checks green, report with the measures and `Ready to merge at <sha>`. Never merge unless prompted with a `Merge the
PR` line. Everything in the foreground.
