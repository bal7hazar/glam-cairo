# F8 - `fixed-cairo`: `sinh_cosh`, `asinh`, `acosh`, `atanh` (next MINOR, 0.5.0)

Repository **`bal7hazar/fixed-cairo`**. Read that repository's `AGENTS.md` (section "Before every push"),
`docs/DESIGN.md` (section 2, "Rounding" and 2.2 "Transcendentals"), `packages/fixed/src/exp.cairo`,
`scripts/gen_exp.py`; and, read-only from the glam-cairo checkout with the Read tool:
`/home/claude/projects/glam-cairo/docs/briefs/F7-hyperbolic.md` (the precedent: how `sinh`, `cosh`, `tanh`,
`sinhc`, `coshc` were built and measured).

## Why

The programme now focuses on the Cairo primitives: their optimisation, measured in Cairo steps, and their API
coverage. nalgebra's `Real` (simba's `ComplexField`) has `sinh_cosh` and the inverse hyperbolic functions. Today a
consumer pays two full exponentials for `sinh` + `cosh`: measured 57 540 gas at x = 1.5, against an estimated
29 890 for a joint call (nalgebra's escalation; an estimate, to be replaced by your measure).
The consumer is confirmed (2026-10-03): simba consumes all four in its lot SIMBA-F8 right after fixed 0.5.0 is
published (simba 0.3.0, `Transcendental::{sinh_cosh, asinh, acosh, atanh}` delegating), then nalgebra takes simba
0.3.0. So all four are public API of fixed 0.5.0, with names and meanings that simba can delegate to one for one.

## API (new methods of `ExpTrait`, full doc template as the other methods)

- `sinh_cosh(self) -> (Fixed, Fixed)`: **bit-identical** to `(self.sinh(), self.cosh())` for every input. That is
  the contract: the gain is in steps, never in results. Same panics as `sinh` / `cosh`.
- `asinh(self) -> Fixed`, `acosh(self) -> Fixed` (panics `'Fixed: acosh domain'` below 1, or the existing message
  convention of the crate: check `DESIGN.md` and the other domain panics), `atanh(self) -> Fixed` (panics outside
  `(-1, 1)`, same convention). Check simba 0.10's `ComplexField` for exact names and meanings and mirror them;
  add nothing else.
- The existing `sinh`, `cosh`, `tanh`, `sinhc`, `coshc`, `exp`, `ln` keep their results bit for bit: their
  goldens and tests pass unchanged. A change of any existing result stops the task (escalation).

## Numerics (measure; the winner in the library, losers in `benches::alt::exp`)

- `sinh_cosh`: share one exponential (and whatever else `sinh` and `cosh` compute in common) so that both outputs
  equal the separate functions bit for bit; prove it by an exhaustive comparison on a dense grid plus every
  segment junction and the overflow boundary, in a test.
- Inverses: accuracy against a high-precision oracle (mpmath in the Python mirror, and the `refgen` goldens);
  report the max error in ULP per function and range, target the order of `ln` (<= ~2 ULP) and state the bound in
  each doc comment. Required properties, tested: `asinh` and `atanh` odd bit for bit; monotonic (dense grid and
  junctions); `acosh(1) == 0`, `asinh(0) == atanh(0) == 0` exactly; no cancellation near 0 (`asinh(x) ~ x`,
  `atanh(x) ~ x`): use `ln_1p`-style forms or a dedicated polynomial, not `ln(x + sqrt(x^2 + 1))` naively; large
  `|x|` for `asinh` / `acosh` without overflow in intermediates; `atanh` near `+-1` stays finite and monotonic up
  to the last representable input.
- Candidates for each inverse: compositions of `ln` / `ln_1p` / `sqrt`, versus a minimax segment near 0 from
  `gen_exp.py`. Bench each (`X__base` / `X__op` with several inputs for branching code).
- Rounding: as the crate's other transcendentals (DESIGN 2), decided by the generator's check and documented.
- If you generate new coefficients, use the pinned environment of `scripts/requirements.txt` and the `reconcile`
  rule of `gen_exp.py`; say whether the committed coefficients are reproduced.

## Measures (in the pull request body and your report)

- Steps and gas, before and after, on the probes of `packages/benches` (`scripts/bench.py`): `sinh` + `cosh` as two
  calls against `sinh_cosh`, at x = 0.5, 1.5, 10 and one input per branch; each inverse at several inputs. Name the
  machine of each figure; these are measures, not estimates.
- The accuracy table (max ULP per function and range) from `gen_exp.py sweep`.

## Files you may edit (in fixed-cairo)

`packages/fixed/src/exp.cairo`, `packages/fixed/tests/test_exp.cairo`, the fixed goldens through `tools/refgen`
(specs and oracles of `fixed`), `scripts/gen_exp.py`, `packages/benches/tests/bench_exp.cairo`,
`packages/benches/src/alt/exp.cairo`, `gas/exp.snap`, `gas/bytecode.size` if the fixture changes, the README gas
tables (`scripts/gas_tables.py`), `CHANGELOG.md` (an "Unreleased" entry only). Not the version (the release is a
separate step on the project manager's go), not `docs/DESIGN.md` (the orchestrator's; propose its text in your
report).

## Done

Conventional commits (`feat(exp): ...`), push through the pre-push hook (never `--no-verify`), pull request with
the step and gas table and the accuracy table, CI green, report with `Ready to merge at <sha>`. Batch all fixes of
one review into one push. Never merge unless prompted with a `Merge the PR` line. Never launch a review or any
agent. Run everything in the foreground.
