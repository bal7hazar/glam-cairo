# CI-paths: run each CI job only when files that concern it changed

Owner's rule, 2026-10-02: "CI tests must absolutely run only if files related to the tests were modified, so docs
should skip all tests." One thread per repository (fixed-cairo, glam-cairo, glamx-cairo), one pull request each. The
thread's task names its repository: `<repo>` below.

## The file you change

`.github/workflows/ci.yml` of `<repo>`, and nothing else in `.github/`. Edit it with the file-editing tool only, never
by a script that rewrites it. Also allowed: a script under `scripts/` that the workflow calls to compute its plan
(glam-cairo: `scripts/affected.py`), with its unit tests under `scripts/tests/`, and one line in `AGENTS.md` saying
how the CI chooses its jobs. Nothing else.

## Rules

1. **Path-gating on pull requests only.** Each job runs on a pull request only when a path in its row of the table
   below changed. The workflow computes this itself from the changed paths, never from a label. Use
   `dorny/paths-filter` pinned by commit sha, as nalgebra-cairo does:
   `dorny/paths-filter@ceb8a2b8f2d89434be7ff52d3de7ec3738c5cc9d # v4.0.3`, in one `changes` job whose outputs
   the other jobs read in their `if:` (these repositories are public; a private one would need
   `permissions: pull-requests: read` on that job). glam-cairo already has a `plan` job (`scripts/affected.py`): keep it for
   the test matrix and the bench modules, and use it or the filter for the other jobs, your choice, said in the PR.
2. **Pushes to `main` and `workflow_dispatch` run everything**, as now (release gates need a full result at every
   main commit, and a regression must stay traceable to its merge).
3. **The toolchain row triggers every job:** `.tool-versions`, `Scarb.toml`, `Scarb.lock`,
   `.github/workflows/**`. A path that matches no row also triggers every job (safe default). Build that catch-all
   filter from negated patterns with `predicate-quantifier: 'every'` (with the default `some`, a list of
   `!pattern` entries matches almost every path), or, in glam-cairo, reuse `affected.py`, which already selects
   everything for an unknown path.
4. **Prose `.md` triggers nothing.** But a `.md` that a job checks is not prose: it triggers the job that checks it.
   In these repositories: `docs/API_PARITY.md` (glam: `api_parity.py --check`), `docs/PACKAGES.md` (the
   consumer-cost job, if it compares the table), the generated regions of `README.md` and `packages/*/README.md`
   (`gas_tables.py --check`), and any other file a script regenerates and compares. `docs/PORTING_STATUS.md` is
   read by no script; `docs/PACKAGES.md` is only written as an artefact by the consumer-cost job, not compared:
   both are prose for this rule unless your reading of the scripts shows otherwise. Find each checked file by
   reading the scripts the workflow runs; list them in the PR.
5. **The final job always runs** (`all-checks`, `if: always()`, `needs:` every other job). It passes only when every
   needed job either succeeded or was skipped by the paths rule; it fails when any job that ran failed or was
   cancelled, and when a job was skipped for any other reason (for example because its own dependency failed).
   `gh pr checks` must always report it: the standard's merge command depends on it. A path skip and a skip for
   another reason both report `skipped`, so do not rely on `contains(needs.*.result, ...)` alone: for each gated
   job, compare its result with the flag that gates it (the `changes` job's output): flag true and result not
   `success` fails; flag false and result not `skipped` fails. This flag-versus-result comparison applies to pull
   requests only: on a push to `main` and on `workflow_dispatch` every job runs (rule 2), so the final job passes
   only when every needed job succeeded, whatever the flags say. A misspelt output name must fail this check,
   never pass in silence; the `changes` job itself must have succeeded.
6. **Concurrency:** a new push to a pull request cancels its superseded run, and every main commit keeps its own
   full run. GitHub keeps at most one pending run per group and cancels an older pending one whatever
   `cancel-in-progress` says, so a push to main must get a group of its own commit:
   `group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}` and
   `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`.
7. **No tool-download retries in this lot:** they need `continue-on-error`, which stays refused; they are a
   separate task. glamx-cairo's existing retry steps stay as they are; this lot adds none. Also refused and never used here: `continue-on-error`, `if: false`, a narrowed test command, a
   deleted job.
8. Change nothing else in the workflow: no step, flag or check is weakened or removed.

## The table: job → paths that trigger it (on a pull request)

Fill in and correct the table for your repository from its workflow and scripts, and put the final table in the PR
body. The toolchain row (rule 3) is implied for every job.

| Job | fixed-cairo | glam-cairo | glamx-cairo |
|---|---|---|---|
| Format, lint, build (`scarb fmt/lint/build`) | `packages/**` (except prose `.md`) | `packages/**` (except prose `.md`), `tools/codegen/**` | `packages/**` (except prose `.md`) |
| Freshness checks in the same job (`gas_tables`, `panic_coverage`, `api_parity`, generators `--check`, `affected.py --check`, script unit tests) | `scripts/**`, `gas/**`, `packages/**`, the READMEs | the same, plus `docs/API_PARITY.md`, `tools/codegen/**` | the same, plus `scripts/gen_eigen3.py` |
| Tests (`snforge test`) | `packages/fixed/**` | the `plan` job's selection (`affected.py`): `packages/glam*/**` and what imports them | `packages/glamx/**`, `packages/facade_check/**` |
| Benches, gas snapshots, bytecode size | `packages/**`, `gas/**`, `scripts/bench.py`, `scripts/bytecode_size.py` | the `plan` job's bench selection, plus `gas/**`, `scripts/bench.py`, `scripts/bytecode_size.py` | `packages/**`, `gas/**`, `scripts/bench.py`, `scripts/bytecode_size.py` |
| Golden vectors (`tools/refgen` test and check) | `tools/refgen/**`, the golden test files | the same | the same |
| Docs build (`scarb doc`) | `packages/*/src/**`, `packages/*/Scarb.toml` | the same | the same |
| Consumer cost | the published packages' `src/**` and `Scarb.toml`, `consumer_cost.toml`, `scripts/consumer_cost.py`, `scripts/packages_table.py` | the same | the same |
| All checks passed (final) | always | always | always |

A step that can run cheaply without a build (the Python freshness checks) may run whenever its own paths change,
even if the Cairo steps of the same job are skipped; split a job into two jobs only if that is simpler, and keep
every check.

## Verification

- Read the workflow with `actionlint` if it is installed (say so if not).
- On the PR itself (which changes `.github/workflows/**`, so everything runs): every job runs and passes, and
  `All checks passed` passes.
- Show the gating works: describe, for three changed-path sets (a prose `.md` only; one file of the main package's
  `src/`; `docs/PACKAGES.md` only), which jobs run and which are skipped, by reading your conditions; the first
  real docs-only PR after the merge is the live check.
- `gh pr checks` reports `All checks passed`.

Done: conventional commit (`ci: run each job only for the paths that concern it`), push through the pre-push hook
(never `--no-verify`), PR with the table, CI green, report with `Ready to merge at <sha>`. Batch every fix of one
review into one push. Never merge unless prompted with a `Merge the PR` line. Never launch a review or any agent.
Poll CI at most once per 5 minutes; when only waiting for CI, write the report and end the turn.
