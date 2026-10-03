# D1 - `fixed-cairo`: make `scripts/gen_trig.py check` reproducible

Repository **`bal7hazar/fixed-cairo`**. Read `AGENTS.md`, `scripts/gen_trig.py`, `scripts/gen_exp.py` (its
docstring and its `reconcile` function) and `scripts/requirements.txt`.

## Why

`gen_trig.py check` is not reproducible: its numpy fits differ by platform noise from the committed coefficients,
so `check` fails on some machines and versions (`scripts/requirements.txt` says so). `gen_exp.py` already solved
the same problem with `reconcile`: it keeps a committed polynomial whenever the fresh fit agrees with it to within
`2^-48` of the polynomial value, and replaces it otherwise. A later lot (FS, step optimisation of the trig
kernels) needs a trustworthy generator before it refits anything.

## What to do

1. Apply the same `reconcile` rule to every fitted polynomial of `gen_trig.py` (library and `benches::alt`), with
   the same tolerance and the same docstring explanation. Do not edit `gen_exp.py`: F8 runs in parallel and owns
   it; copy the helper into `gen_trig.py` (a later lot may factor it).
2. `gen_trig.py check` must pass, with the pinned environment of `scripts/requirements.txt`, with numpy 1.26.4
   and with numpy 2.5.3 (as `gen_exp.py` is documented to). Measure each and say which you ran.
3. Results unchanged: `gen_trig.py emit` rewrites nothing in `packages/fixed/src/trig.cairo` or
   `packages/benches/src/alt/trig.cairo` (`git diff --exit-code` after `emit`), and every trig test and golden
   passes unchanged. A change of any committed coefficient stops the task (escalation).
4. Update `scripts/requirements.txt`'s comment: `gen_trig.py check` is now green, and with which versions.
5. If CI or `scripts/check.sh` can now run `gen_trig.py check` cheaply, say so in your report with the measured
   time; do not change CI or `check.sh` in this lot.

## Files you may edit

`scripts/gen_trig.py` and `scripts/requirements.txt`. Nothing else (F8 owns `gen_exp.py` and `exp.cairo`).

## Done

One commit (`build(gen): reproducible gen_trig check`), push through the pre-push hook (never `--no-verify`), pull
request, CI green, report with the versions you ran and `Ready to merge at <sha>`. Never merge unless prompted
with a `Merge the PR` line. Never launch a review or any agent. Foreground only.
