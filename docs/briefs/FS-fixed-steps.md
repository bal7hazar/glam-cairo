# FS - `fixed-cairo`: fewer Cairo steps on the hot kernels, results bit-identical

Repository **`bal7hazar/fixed-cairo`**. Read `AGENTS.md` (section "Before every push"), `docs/DESIGN.md` (section 2),
`packages/fixed/src/internal/bounded.cairo` (`narrow32`, `narrow64`, `mul`, the bounded-int helpers),
`packages/fixed/src/internal/acc.cairo` (the `W1`..`W15` accumulators and their `narrow`), `packages/fixed/src/wide.cairo`,
`packages/fixed/src/fixed.cairo` (`FixedMul`, `FixedSub`, `FixedPartialOrd`), `packages/benches` and `scripts/bench.py`.

## Why

The programme now optimises the Cairo primitives, measured in Cairo steps. rapier's hot-path profile (HP: rapier-cairo
`docs/research/impact-tick.md` §9, measured with cairo-profiler on 36 probes, 54.3M steps) puts fixed + glam_core at
29.6 % of all steps, and `narrow32`, the Q64.64 → Q32.32 rescale, alone at 16.0 %. Its top fixed entries
(calls × steps per call = share of all steps):

| # | Item | Calls | Steps/call | Share |
|---|---|---:|---:|---:|
| 1 | `fixed::wide::mul_add` | 201 841 | 15.2 | 5.65 % |
| 2 | `FixedMul::mul` | 106 849 | 13.8 | 2.71 % |
| 3 | `wide::dot2_add` | 73 560 | 17.8 | 2.42 % |
| 4 | `wide::mul_sub` | 50 016 | 15.6 | 1.44 % |
| 5 | `wide::dot2` | 45 451 | 15.3 | 1.28 % |
| 6 | `FixedPartialOrd::gt` | n/a | n/a | 1.16 % |
| 7 | `W3Narrow::narrow` | 40 520 | 14.5 | 1.08 % |
| 8 | `FixedSub::sub` | 86 405 | 6.5 | 1.03 % |

Every item from 1 to 5 and 7 ends in `narrow32` (or a sibling rescale). One step saved there is saved on every call.

## Scope, in this order

1. `narrow32` (and `narrow64`, `narrow64_round` if the same idea applies).
2. The fused kernels that call it: `wide::mul_add`, `dot2_add`, `mul_sub`, `dot2`, the `W*::narrow` of the
   accumulators (`W3` first), and `FixedMul::mul` (`bounded::mul`).
3. Only then, and only if cheap: `FixedPartialOrd::gt` and `FixedSub::sub`.

## Rules

- **Results bit-identical**: every existing test, golden and snapshot result passes unchanged, for every input,
  including every panic: the same panic message, raised for exactly the same inputs (the overflow boundaries of
  `narrow32` and of each kernel are part of the result). Prove the boundaries with tests at `limit - 1`, `limit`,
  `limit + 1` on both sides. A change of any result stops the task (escalation).
- **Measure, do not estimate.** For each candidate, the steps of the existing benches (`scripts/bench.py`,
  `X__base` / `X__op`, several inputs for branching code) before and after, on this VPS. The winner goes in the
  library, the losers in `benches::alt::{wide,fixed}` with their bench rows. Add a bench row for `narrow32` itself
  if none exists.
- Candidate ideas to measure (not a prescription): fewer range checks in the felt252 → u128 conversion; a different
  split than `div_rem` by `2^64`; folding the `+2^95` bias into the caller's constant; an unbiased path when the
  caller already bounds the sign; `#[inline]` choices (steps per call at the call site are what counts).
- Keep each kernel's documented error and rounding (floor, or round-to-nearest where documented).

## Report (PR body and your report)

For each win: steps per call before → after (VPS, `gas/*.snap`), and the share it moves on rapier's probes,
computed from the HP table above (`calls × steps saved / 54.3M`). That is an estimate from HP's counts; say so. For
the losers: one line each with the measure. The gas columns too, per function.

## Files you may edit (in fixed-cairo)

`packages/fixed/src/internal/bounded.cairo`, `packages/fixed/src/internal/acc.cairo`, `packages/fixed/src/wide.cairo`,
`packages/fixed/src/fixed.cairo` (implementations only: no public signature, name or doc contract changes),
`packages/fixed/tests/test_fixed.cairo`, `packages/fixed/tests/test_wide.cairo`,
`packages/benches/tests/bench_{fixed,wide}.cairo`, `packages/benches/src/alt/{fixed,wide}.cairo`,
`gas/{fixed,wide}.snap`, `gas/bytecode.size` if the fixture changes, the README gas tables
(`scripts/gas_tables.py`), `CHANGELOG.md` ("Unreleased" only). Not `exp.cairo`, `trig.cairo` or their tests and
benches (F8 may still be open on them), not the version.

## Done

Small conventional commits (`perf(wide): ...`), push through the pre-push hook (never `--no-verify`), pull request
with the table, CI green, report with `Ready to merge at <sha>`. Batch all the fixes of one review into one push.
Never merge unless prompted with a `Merge the PR` line. Never launch a review or any agent. Run everything in the
foreground.
