# Porting status

Maintained by the orchestrator after each merge. Task ids refer to `docs/PLAN.md`.
Status: `todo`, `inprogress`, `inreview`, `done`.

| id | module(s) | status | PR |
|---|---|---|---|
| W0 | research, workspace, CI, bench harness, docs | done | bootstrap |
| F1 | `fixed::fixed` tier A | done | #6 |
| F2 | `fixed::wide` fused kernels | done | #6 |
| F3 | `fixed::trig` tier B | done | #8 |
| T1 | `tools/refgen` golden vector generator | done | #3 |
| V0 | `bvec2`, `bvec3`, `bvec4` | done | #2 |
| V2 | `vec2` | done | #9 |
| V3 | `vec3` | done | #9 |
| V4 | `vec4` | done | #9 |
| VI | `ivec2/3/4`, `uvec2/3/4` | done | #5 |
| M2 | `mat2` | done | #13 |
| M3 | `mat3` | done | #13 |
| M4 | `mat4` | done | #13 |
| Q1 | `quat` | done | #12 |
| S1 | swizzles (Vec2, Vec3) | done | #10 |
| X1 | cross-type methods | done | #17 |
| A2 | `affine2` | done | #14 |
| A3 | `affine3` | done | #21 |
| E1 | `euler` | done | #15 |
| C1 | `camera` | done | #16 |
| S2 | swizzles (Vec4, integer) | done | #10 |
| F4 | `fixed` tier C (`exp`, `ln`, `powf`) | done | #18 |
| P0 | `glamx` package bootstrap + scope research (`docs/research/06-glamx-scope.md`) | done | #19 |
| P1a | `glamx::pose3`, `glamx::rot3` | done | #22 |
| P1b | `glamx::rot2` | done | #24 |
| P1c | `glamx::pose2` | done | #27 |
| P1d | `glamx::sdp` | done | #23 |
| P1e | `glamx::eigen3` | done | #29 |
| X2 | `IVec*/UVec*::as_vec*` | done | covered by the `Into<IVecN, VecN>` / `Into<UVecN, VecN>` impls (`docs/API_PARITY.md`: 0 missing) |
| R1a | API parity table (`scripts/api_parity.py`, `docs/API_PARITY.md`) | done | #20 |
| X3a | parity closure of `Vec2/3/4` (element-wise transcendentals, `step`/`smoothstep`/`saturate`, `From<BVec>`, homogeneous, `project`) | done | #25 |
| X3b | parity closure of `Quat`, `Mat3/4`, `Affine2/3`, camera views | done | #26 |
| R1b | generated gas tables in the READMEs (`scripts/gas_tables.py`, checked in CI) | done | #28 |
| R1 | release audit: optimizer pass, deviation review, bytecode size, `v0.1.0` (briefs `docs/briefs/R1-common.md` + `R1c`..`R1m`) | done | #30-#39 |
| R1c | optimizer pass on `glamx::eigen3`: metered one-rotation iterations (zero pivots free), polish-free `eigenvalues`, diagonal short-circuit: `new` -8.6 %, `eigenvalues` -15.9 %, diagonal -45.5 %; rotation order changed (numeric change, all overall worst cases improve) | done | #34 |
| R1d | optimizer pass on `quat`: `rotate_towards` 162 720 -> 129 100 gas, `slerp` back to 122 180, `is_normalized` / `is_near_identity` total and ~2x cheaper; flaky `fuzz_mul_quat_drift` fixed (test helper built quaternions 5 ULP off unit) | done | #36 |
| R1e | optimizer pass on `fixed::wide` + `Vec2/3/4`: `is_unit2/3/4` kernels (`is_normalized` total and ~2x cheaper), shared norm in `Vec3::rotate_towards`; single-division and `slerp` candidates measured and kept in `benches::alt` | done | #32 |
| R1f | `camera` / `Mat4::look_to_*` duplication | dropped | the bytecode audit (#31) shows no gain: inlined bodies are paid per call site whichever function holds them |
| R1g | faster bench job: one snforge test crate per bench file (CI bench job 928 s -> 198 s, local check ~2 090 s -> 230 s, snapshots identical); `all-checks` is now bounded by `Test glam` (~16 min) | done | #33 |
| R1h | audit of every `#### Deviations` entry against DESIGN section 3 (`docs/audits/R1-deviations.md`); 8 rows added to DESIGN section 3 | done | #30 |
| R1j | `glamx::rot2`: `lerp` aligned with upstream (not normalised, 15 330 -> 4 880 gas), `is_normalized` added (audit P0) | done | #35 |
| R1k | panic coverage: `scripts/panic_coverage.py` (item -> `should_panic` test, checked in CI), 324 tests added (372 missing pairs -> 0), doc template on the nine `IndexView` impls | done | #37 |
| R1m | follow-up of #37: the 21 allowlisted `quat` panic tests, and the 25 escalated doc gaps (documented panics that cannot happen, wrong native messages on `move_towards` / sdp); brief `docs/briefs/R1m-panic-followup.md` | done | #39 |
| R1l | doc-only deviation fixes: stale camera module doc, `Deviations: None.` replaced on items that panic where upstream continues, non-semantic bullets moved out of `Deviations` | done | #38 |
| R1i | bytecode size of a consumer contract (`packages/consumer`, `docs/audits/R1-bytecode-size.md`): kitchen-sink class at 61.5 % of the 81 920 CASM felt limit, keep the inlining; `gas/bytecode.size` checked in CI | done | #31 |
| R1z | `v0.1.0`: tag `v0.1.0` (2ac9a82) and GitHub release cut 2026-09-22; `scarb publish` of `fixed`, `glam`, `glamx` by the owner | done | [release](https://github.com/bal7hazar/glam-cairo/releases/tag/v0.1.0) |
| F5 | `fixed::wide::Acc` count-agnostic accumulator + `WideSqrt` for `W1..W16` (nalgebra-cairo escalation, 2026-09-23); release `v0.2.0` of the three packages (tag on 69c2db7, published on scarbs.xyz 2026-09-23) | done | #40, [release](https://github.com/bal7hazar/glam-cairo/releases/tag/v0.2.0) |
| F6 | correctly rounded `div_nearest` / `recip_nearest` / `RecipTrait::div_nearest` (nalgebra-cairo escalation, 2026-09-23); `/`, `recip`, `from_ratio` switched to round-half-even (Rust reference; +10.7 % on `/`, 173 benches in 18 snapshots); released `v0.3.0` (tag on e30f7e6, published on scarbs.xyz 2026-09-23) | done | #42, [release](https://github.com/bal7hazar/glam-cairo/releases/tag/v0.3.0) |
| D1 | (now in `fixed-cairo`; `gen_exp.py` fixed by F7, `gen_trig.py` still platform-dependent) reproducible environment for `scripts/gen_trig.py` / `gen_exp.py` (numpy / mpmath not pinned: `emit --check` depends on the numpy version; not in the gate) | todo | |
| D2 | test runtime: one test crate per file / group (`Test glam` 22 min in CI), `scripts/affected.py` selective runs on pull requests, full run on `main`; six-family test matrix (CI full run 24 min 28 s -> 5 min 38 s, measured on GitHub runners), `scripts/affected.py` + `check.sh --affected` on pull requests | done | #44 |
| RN | repositories renamed `*.cairo` -> `*-cairo` (GitHub renames + live docs) | done | #41 |
| S1 | split `fixed-cairo` out (history kept, standalone gate and CI), `docs/SPLIT.md` | done | [fixed-cairo](https://github.com/bal7hazar/fixed-cairo) `efa78b8` |
| S2 | split `glamx-cairo` out (history kept, `fixed` / `glam` 0.3.0 from the registry; 145 benches identical to the snapshots) | done | [glamx-cairo](https://github.com/bal7hazar/glamx-cairo) `d8a2e81` |
| S3 | remove `fixed` and `glamx` from `glam-cairo`, `fixed` 0.3.0 from the registry (2 020 benches, goldens and `API_PARITY.md` identical; `GlamSink` bytecode fixture) | done | #43 |
| F7 | `fixed-cairo`: hyperbolic kernels `sinh`, `cosh`, `tanh` (ideally `sinhc`) through `TrigTrait` / `ExpTrait` (nalgebra-cairo escalation of 2026-09-24, relayed by the programme session): `sinh` / `cosh` / `tanh` (+ simba's `sinhc`, `coshc`) in `fixed-cairo`, <= 1.5 ULP, ~35 % cheaper than two `exp`; `gen_exp.py` fit made platform-independent (D1 for `exp`); released 2026-09-25 on the programme session's written go (owner's delegation): `fixed` 0.4.0 (fixed-cairo `v0.4.0` `d3215fe`), `glam` 0.4.0 (`v0.4.0` `e095aa6`, #47), `glamx` 0.4.0 (glamx-cairo `v0.4.0` `3d3cf1c`, its #1) | done | fixed-cairo #1, #47, glamx-cairo #1 |
| P2 | `glamx-cairo`: receive rapier-cairo's measured `Pose2` fused kernels (its PR #21) if the owner approves the parry split (`glamx::Pose2` is the pivot of `fixed -> glam -> glamx -> parry -> rapier`); nothing before that decision | todo | |
| D3 | `test_quat::fuzz_axis_angle` counterexample found by D2 (another fuzz order): `Mat3::from_quat(r).abs_diff_eq(m, 16 ULP)` fails for `a=-5252968756010171118, b=-3096882712146088177, c=-8084405785948374804, d=-3340032920127808801`: replay, find whether the test's bound or the library is wrong; on `main` today, latent; brief `docs/briefs/D3-quat-axis-angle-fuzz.md`: the test's 16 ULP bound was measured, not derived; the library is within its documented bounds (checked against a 60-digit evaluation); bounds derived as `8 + 2 drift` / `44 + 12 drift` ULP, regression test kept; doc of `from_rotation_axes` corrected | done | #45, #46 |
| F8 | `fixed-cairo`, next MINOR (0.5.0), batched: **`ExpTrait::sinh_cosh(x) -> (Fixed, Fixed)`** sharing one exponential like `sin_cos` / simba's `ComplexField::sinh_cosh` (nalgebra-cairo escalation of 2026-09-25, relayed by the programme session: separate `sinh` + `cosh` = 57 540 gas at x = 1.5 vs 47 070 for nalgebra's two-exp composition, ~29 890 expected joint); candidates to batch if asked: `asinh`, `acosh`, `atanh`. Launch when more `fixed` work accumulates or a consumer asks for the release | todo | |
| PK-G | package-size gate: `scripts/consumer_cost.py` (from nalgebra-cairo `bff3462`) + CI job `Consumer cost` in the three repositories (fixed 11 131 lines / 0.24 GB, glamx 3 291 / 0.76 GB, glam 41 484 / 0.69 GB: over on lines only, allowlisted until the cut); glam cut plan `docs/audits/PK-G-glam-cut-plan.md` (recommended: `glam_core` 16.3k / `glam_swizzles` 4.8k / `glam_int` 10.8k / `glam_int_swizzles` 9.6k behind the `glam` facade; only `as_ivec*` / `as_uvec*` need an extra `use`) sent to the programme session for its go | done | #48, fixed-cairo #2, glamx-cairo #2 |
| PK-G2 | glam cut per the plan (four crates agreed; variant B won: `glam_core` 18 498 lines, +2-3 % time / +8-10 % memory vs A, no path change, #49), brief `docs/briefs/PK-G2-glam-cut.md`; `Consumer cost` enforcing | done | #50 |
| PK-G3 | release `glam` 0.4.1 (facade + `glam_core`, `glam_swizzles`, `glam_int`, `glam_int_swizzles`; non-breaking, no numeric change) after PK-G2, on the programme session's written go. Conditions it set: `main` CI green at the release commit with `Consumer cost` ENFORCING; gas snapshots identical to 0.4.0; every 0.4.0 public path resolved through the facade (the 0.4.0 consumer fixtures compile unchanged); publication order `glam_core` -> `glam_swizzles` -> `glam_int` -> `glam_int_swizzles` -> `glam`, each checked against the registry copy of the previous ones; one README per package (content, dependencies); CHANGELOG "Added: sub-crates; `glam` is now a facade". No `fixed` / `glamx` release. Released 2026-09-28 on the programme session's written go: tag `v0.4.1` on `674b613`, the five crates on scarbs.xyz | done | [release](https://github.com/bal7hazar/glam-cairo/releases/tag/v0.4.1) |
| PK-G4 | shared `consumer_cost.py` from nalgebra-cairo `7177cf3` in the three repositories (marginal gate 2, `facades = ["glam"]`, glamx closure with registry crates, `--self-test`, `--repeat 3`) | done | #51, fixed-cairo #3, glamx-cairo #3 |
| X4 | glamx next release: depend on `glam_core` 0.4.1 instead of the `glam` facade (it only uses core types): empty consumer of glamx -0.45 s / -0.25 GB (2.42-2.60 s / 0.51 GB vs 2.89-3.02 s / 0.76 GB), 145 benches identical, `gas/bytecode.size` class bytes +40..227 (debug names); go for the merge and conditional release go for glamx 0.4.1 given by the programme session (type-identity fixture, CI green with `Consumer cost`, snapshots identical, CHANGELOG / README); brief `docs/briefs/X4-glamx-on-glam-core.md`; released 2026-09-28: glamx 0.4.1 on `glam_core` 0.4.1 + `fixed` 0.4.0, tag `v0.4.1` on glamx-cairo `30dbdb6`, `packages/facade_check` proves the type identity with the `glam` facade | done | glamx-cairo #5, [release](https://github.com/bal7hazar/glamx-cairo/releases/tag/v0.4.1) |
| PK-G5 | `consumer_cost.py` + `packages_table.py` from nalgebra-cairo `ded2847` in the three repositories; `docs/PACKAGES.md` (every package vs 40 000 lines / 5 s / 1 GB, closures vs 15 s / 3 GB) generated on a GitHub runner and appended to the `Consumer cost` summary; all pass, smallest margin `glam_core` lines +53 % | done | #52, fixed-cairo #4, glamx-cairo #6 |
| TC-F | toolchain bump (owner's D-180) of `fixed-cairo`: Scarb 2.20.1 / snforge 0.64.0, results bit-identical; brief `docs/briefs/TC-F-fixed-scarb-2.20.md`; 76 of 278 gas rows -120 l2_gas, nothing else changed | done | fixed-cairo #5 |
| TC-G | toolchain bump of `glam-cairo` (same versions), after TC-F; brief `docs/briefs/TC-G-glam-scarb-2.20.md`; 1 160 gas rows -120 l2_gas (Bitwise-builtin calls +100 relative: uvec bit ops net +100, ivec net -20; `benches::alt` bvec span literals +10 per element), steps / builtins / bytecode sizes unchanged | done | #55 |
| TC-X | toolchain bump of `glamx-cairo` (same versions), after TC-G; brief `docs/briefs/TC-X-glamx-scarb-2.20.md`; 82 gas rows -120 l2_gas, nothing else changed | done | glamx-cairo #7 |
