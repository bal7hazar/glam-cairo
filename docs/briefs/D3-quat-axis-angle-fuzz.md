# D3 - `test_quat::fuzz_axis_angle` counterexample

Branch `fix/quat-axis-angle-fuzz`. Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`
(crate-scoped local checks, CI is the full gate), `packages/glam/src/quat.cairo`
(`from_axis_angle`, `to_axis_angle`, and `Mat3::from_quat` in `mat3.cairo`), and
`packages/glam/tests/test_quat.cairo` (`fuzz_axis_angle` and its helpers).

Facts: while measuring the D2 test layouts (#44), a different fuzz order produced a failing input
for `fuzz_axis_angle` on unchanged library code (the property is latent on `main`):
arguments `["-5252968756010171118", "-3096882712146088177", "-8084405785948374804",
"-3340032920127808801"]`, failure `assertion failed:
Mat3Trait::from_quat(r).abs_diff_eq(m, f(16))` (CI run 36150886581 of bal7hazar/glam-cairo).

Do, in this order:
1. Replay these arguments in a plain `#[test]` (keep it as a regression test) and print the
   quantities involved: the axis / angle the helper builds, the quaternion `r`, both matrices,
   the component-wise difference in raw ULP.
2. Decide, with evidence, which side is wrong:
   - **the property**: its 16 ULP bound is not what the documented error bounds of
     `from_axis_angle` / `Mat3::from_quat` imply for this input (for instance a nearly zero axis
     that `normalize_or` sends elsewhere, an angle near a branch, magnitudes the helper did not
     intend). Then fix the helper or derive the correct bound from the documented bounds, in
     ULP, and write the derivation in a comment. **Never widen a bound without that derivation.**
   - **the library**: a result outside its documented bound. Then fix the library, show the
     before / after on this input and on the golden vectors, and list it as a numeric change in
     `REPORT.md` (the orchestrator decides the version).
3. Run `fuzz_axis_angle` with several seeds (`snforge test test_quat -p glam --fuzzer-seed <s>
   --fuzzer-runs 512` for a handful of seeds) to show no other counterexample remains.

Files you may edit: `packages/glam/tests/test_quat.cairo`; and, only in the library case,
`packages/glam/src/quat.cairo` / `mat3.cairo` (through `tools/codegen/fmat.py` if generated),
their goldens / refgen, benches and `gas/*.snap` if they change. Commit scope `test(quat)` or
`fix(quat)`. Pull request with the diagnosis in the body, CI green, `REPORT.md`. Do not merge.
