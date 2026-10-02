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

Bash, `set -euo pipefail`, runnable from any directory of the clone (cd to the repository root). Arguments:
`[<sha> [<base>]]`: the commit to check (default `HEAD`; the hook passes the pushed sha) and the base (default the
merge base of that sha with `origin/main`). Prints each step and its duration, exits non-zero on the first failure.
Run the unlocked steps (fmt, Python) first, so they fail fast. Aim: under 2 minutes on this VPS for a typical change;
measure, do not estimate.

On the VPS, `scarb build|lint|check` (and `bytecode_size.py check`, which builds) go through the shim
`~/.local/bin/scarb`, which waits on the shared `~/orchestrator/heavy-build.lock` with no timeout; `scarb fmt` and
the Python checks are not locked. Print the lock wait apart from the step time when you can (or take the measures
with the lock free and say so).

The checks run on the working tree, but a push sends commits: the script refuses (exit 1, with a clear message) when
tracked files differ from the commit being checked or untracked files exist (`git status --porcelain` is not empty,
or HEAD is not `<sha>`), so that an uncommitted `scarb fmt` result, a new file never added, or unrelated edits never
make the hook lie. The message names the checked sha and HEAD, and says to commit or stash: never `--no-verify`.

Always:
- `scarb fmt --check --workspace`;
- the unit tests of the Python scripts: `python3 scripts/consumer_cost.py --self-test` and `python3
  scripts/packages_table.py --self-test` (all three repositories, as CI's `consumer-cost` job), plus `python3 -m
  unittest discover -s scripts/tests -p 'test_*.py'` where `scripts/tests/` exists; and the cheap `--check` modes of the scripts that check documents against committed sources (for
  example `gas_tables.py --check`, `panic_coverage.py --check`, `api_parity.py --check`, `affected.py --check` where
  they exist and take seconds).

Only when their inputs changed since the base (decide from `git diff --name-only <base>...<sha>`):
- the compile of the touched packages **and of the workspace packages that depend on them** (a change in `fixed`
  also builds `benches` and `consumer`; in glam-cairo a change to any library crate also builds the facade `glam`
  and `benches` and `consumer`, and `affected.py` has the import graph; in glamx-cairo `glamx` also builds
  `benches`, `facade_check` and `consumer`; in general every workspace package whose `Scarb.toml` depends on a
  touched package, transitively): `scarb build -p <package>` each (`scarb check -p` instead if Scarb 2.20.1 has it
  and it catches the same errors faster: measure both, say which you kept); a change to `Scarb.toml`, `Scarb.lock`
  or `.tool-versions` compiles the workspace;
- the lint of the same packages, with CI's flags: `scarb lint -p <package> --test --deny-warnings` (`--test` also
  compiles and lints the test targets, which `scarb build` does not);
- the generated artefacts whose inputs changed: code generators' `--check` (glam-cairo `tools/codegen/*.py`,
  glamx-cairo `gen_eigen3.py emit --check`), `bytecode_size.py check` when library sources or the toolchain changed; the golden vectors, `cargo run --quiet
  --locked --manifest-path tools/refgen/Cargo.toml -- check`, when `tools/refgen/**` or a golden file changed and
  `cargo` is present (as `check.sh` does).
  Gas snapshots (`bench.py check`) and the snforge test suites stay with CI (too long for a pre-push): say so in a
  comment at the top of the script, with the list of what is left to CI.

## 2. The hook

`.githooks/pre-push` (executable) reads the `<local ref> <local sha> <remote ref> <remote sha>` lines git gives it on
stdin and runs `scripts/prepush.sh <local sha>` for each line that pushes a commit; it blocks the push on failure; a
line that only deletes a ref (local sha all zeros) runs nothing. Read all the lines first, then run the script for
each with `</dev/null`, so that no child process consumes the remaining lines.
Set `git config core.hooksPath .githooks` in this repository's clone on the VPS
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
failed (no `continue-on-error`, so a third failure fails the job). Before attempts 2 and 3, a `run: sleep 20` step
under the same `if`, so a short HTTP error has time to clear. Keep the pinned action SHAs. Change nothing else
in the workflow.

## Measures and report

Run on this VPS and paste the real output of `time scripts/prepush.sh`: (a) on the branch with no Cairo change (only
your scripts and docs); (b) with one throw-away change to a Cairo source file of the main package, committed on a throw-away local branch
(run the script there, then delete the branch; never push it). Name the machine. Show the hook blocking a push: with a throw-away formatting error, run the hook
directly with a real line on stdin, `printf 'refs/heads/<b> %s refs/heads/<b> %s\n' "$(git rev-parse HEAD)"
0000000000000000000000000000000000000000 | .githooks/pre-push origin <url>` (commit the error on a throw-away
local branch first, then delete that branch), and paste its failing output; never push the error. The CI of the PR
must be green: each tool download shows attempt 1 succeeded and attempts 2 and 3 skipped.

Done: conventional commits (`chore(ci): pre-push check and tool-download retries`), push (through the hook), PR,
checks green, report with the measures and `Ready to merge at <sha>`. Never merge unless prompted with a `Merge the
PR` line. Everything in the foreground.
