# Design

Decisions that every module must follow. Evidence lives in `docs/research/` (reports 01-05);
this file only records the conclusions. Changing anything here is a breaking change and is decided
by the orchestrator, never by a porting sub-agent.

## 1. Scope

`glam-cairo` (named `glam.cairo` until 2026-09; the dated documents under `docs/research/`,
`docs/audits/`, `docs/briefs/` and the past `CHANGELOG.md` entries keep that name) ports
[glam-rs](https://github.com/bitshifter/glam-rs) **0.33.8** to pure Cairo
(no `starknet` dependency). It is the base layer of a provable game physics stack; the sibling
repositories consume the published packages. Since 2026-09-25 each repository mirrors one Rust
reference repository ([`docs/SPLIT.md`](SPLIT.md)):

| repository | packages | depends on (registry) |
|---|---|---|
| [`bal7hazar/fixed-cairo`](https://github.com/bal7hazar/fixed-cairo) | `fixed`: the signed Q32.32 scalar, its fused kernels and its transcendental functions | - |
| `bal7hazar/glam-cairo` (this one) | `glam`: `Vec2/3/4`, `Mat2/3/4`, `Quat`, `Affine2/3`, `BVec*`, `IVec*`, `UVec*`, `EulerRot`, swizzles, camera | `fixed` |
| [`bal7hazar/glamx-cairo`](https://github.com/bal7hazar/glamx-cairo) | `glamx`: Dimforge's `glamx` 0.3.1 extensions (`Rot2`, `Rot3 = Quat`, `Pose2/3`, `SdpMatrix2/3`, `SymmetricEigen3`) | `fixed`, `glam` |
| `bal7hazar/nalgebra-cairo` | `nalgebra` | `fixed` |
| `bal7hazar/rapier-cairo` | `rapier*` | all of the above |

This workspace also holds two unpublished packages: `benches` (gas/step benchmarks and the
losing alternative implementations) and `consumer` (the `GlamSink` contract fixture whose class
size is tracked in `gas/bytecode.size`).

Type mapping from glam-rs (one scalar, so the f32/f64/SIMD/aligned variants collapse):

| glam-rs | glam-cairo |
|---|---|
| `Vec2`, `DVec2` | `Vec2` |
| `Vec3`, `Vec3A`, `DVec3` | `Vec3` |
| `Vec4`, `DVec4` | `Vec4` |
| `Mat2/DMat2`, `Mat3/Mat3A/DMat3`, `Mat4/DMat4` | `Mat2`, `Mat3`, `Mat4` |
| `Quat`, `DQuat` | `Quat` |
| `Affine2/DAffine2`, `Affine3A/Affine3/DAffine3` | `Affine2`, `Affine3` |
| `BVec2/3/4` (+`A` variants) | `BVec2`, `BVec3`, `BVec4` |
| `IVec*` / `UVec*` (i32 / u32) | `IVec2/3/4`, `UVec2/3/4` |
| other integer widths (i8, i16, i64, u8, u16, u64, usize) | not ported (add on demand) |
| `EulerRot`, swizzle traits, `camera` | ported (Vec4 swizzles and camera last) |
| SIMD, `bytemuck`, `serde`, `rand`, `mint`, `NAN`/`INFINITY`, `is_nan`, `is_finite` | dropped |

## 2. The scalar: `fixed::Fixed`

The scalar is owned by [`fixed-cairo`](https://github.com/bal7hazar/fixed-cairo), whose
`docs/DESIGN.md` is the reference for its format, rounding, overflow, kernels and
transcendentals; `glam` depends on the published `fixed = "0.3.0"`. What `glam` relies on:

- `Fixed { raw: i64 }`, signed Q32.32 (`value = raw / 2^32`), one felt per value, `Copy`,
  `Serde`, `Hash`, `Default`. There is no generic scalar: every type is written against `Fixed`.
- Rounding and overflow are API: products and fused kernels floor, `Fixed / Fixed` and `recip`
  round to nearest (ties to even), `wide::RecipTrait::mul` rounds to nearest; every overflow
  panics (never wraps or saturates). A change of any of them in `fixed` is a MINOR bump and one
  pull request here (new `gas/*.snap`, golden vectors).
- Escalations about the scalar (a missing kernel, a rounding question) go to `fixed-cairo`.

### 2.1 Fused kernels (`fixed::wide`)

Multiply raw values into exact wide products, sum them, **rescale once per output scalar**
(`dot2/3/4`, `mul_sub`, `mul_add`, `det3`, `norm*`, `normalize*`, the shared division `Recip`,
the accumulators `W1..W16` / `T1..T16`). Every product of `glam` goes through them, never through
chains of `Fixed * Fixed` (`dot3` 2 080 fused vs 7 540 unfused gas). Quadruple products do not fit
a felt: narrow a partial sum and re-lift.

### 2.2 Transcendentals (`fixed::trig`, `fixed::exp`)

Loop-free, deterministic `sin`, `cos`, `sin_cos` (one call: ~31 300 gas, cheaper than `sin` +
`cos`), `tan`, `atan2`, `asin`, `acos`, `exp`, `ln`, `powf`; `glam` uses them for rotations,
Euler angles, `slerp` and the camera.

## 3. Semantics that differ from glam-rs

Every deviation is also documented on the item under `#### Deviations`.

| topic | glam-rs (f32) | glam-cairo |
|---|---|---|
| NaN / infinity | propagate | do not exist; the operation panics instead |
| overflow | infinity | panic (`'Fixed: overflow'` or native i64 message) |
| `normalize` of zero | NaN vector | panics `'VecN: normalize zero'`; `try_normalize` / `normalize_or_zero` as in glam |
| `recip`, division by zero | infinity | panic |
| `signum(0)` | `+1.0` | `+1` (kept: `angle_to` and `any_orthonormal_*` rely on it) |
| epsilon thresholds (`is_normalized` 2e-4, slerp `1 - 1e-6`, `1e-8`, ...) | tuned for f32 | re-derived per call site, expressed in raw ULPs, listed in the item doc |
| `abs_diff_eq`, `Eq`, `Hash` | approximate only | `abs_diff_eq` kept; exact `PartialEq`/`Hash` also meaningful |
| `try_inverse` / `inverse` | `det == 0` | divide the adjugate **once** by the determinant; singular = `det == 0` raw |
| `Vec * scalar` operators | `Mul<f32> for Vec3` | core `Mul<T>` is homogeneous: named methods `mul_scalar`, `div_scalar` (+ heterogeneous `MulAssign`) |
| `round`, `fract`, `%` on negatives | IEEE | `round` = half away from zero as in Rust; `fract = x - trunc(x)`, `fract_gl = x - floor(x)`; `rem` truncated, `rem_euclid` euclidean |
| `as_*` casts | saturating | `Fixed -> i32/u32` panics when out of range |
| `glam_assert!` (opt-in debug asserts) | feature flag | not checked (document the precondition) unless the check is free |
| `acos_approx` | degree-7 approximation | the precise `fixed::trig::acos` (7.6e-10) |
| algebraic reassociation | rounds after each f32 operation | products are accumulated by `fixed::wide` and rescaled once per output: an equivalent formula may differ bitwise from a line-by-line float port |
| interpolation | `lerp` is `a*(1-t) + b*t`; glamx `Rot2::lerp` is not normalised | `Fixed` / vector `lerp` is `a + (b-a)*t` (exact at both ends, one rescale). A same-name rotation `lerp` keeps the upstream semantics: normalisation is spelled `lerp(..).normalize()` or `nlerp` where upstream has it |
| small-distance snap | `move_towards` snaps below `1e-4` | only a distance of exactly zero raw is snapped: every non-zero Q32.32 distance is resolved |
| camera validation | `glam_assert!` on positive near / far; other invalid inputs flow to IEEE values | projection constructors always check positive near / far, `0 < fov < PI`, non-zero aspect and non-zero denominators, and panic with the documented messages (no NaN to return; the checks are cheap next to a `sin_cos`) |
| integer-vector overflow | depends on debug / release and on the operation order | plain operators panic; fused helpers range-check the final result only, so an out-of-range intermediate is accepted when the result fits |
| alternative algorithms | platform libm, glamx closed forms | the deterministic transcendentals of `fixed` and the scaled Jacobi solver of `glamx::eigen3` are public numeric choices; the measured error bounds live on the items |
| API surface | inherent methods, reference / iterator / `Display` / `Deref` glue | extension traits to import, named heterogeneous operations, pass by value, derived `Debug`; every omission or addition is listed on the type |
| unchecked preconditions and degenerate inputs | feature-gated assertions | out-of-contract results are unspecified but deterministic: a degenerate input either flows through (`Affine2::to_scale_angle_translation` returns a zero scale) or reaches a mandatory division and panics (`Mat4` / `Affine3::to_scale_rotation_translation`); the item says which |

The `#### Deviations` section of an item is semantic only: gas notes, inlining choices and
"exact" parity statements do not belong there. The audit of all 1 179 documented items before
`v0.1.0` is `docs/audits/R1-deviations.md` (inventory: `python3 scripts/deviations.py`; the
appendix of the audit is a snapshot of its date, it is deliberately not part of the gate).

## 4. Code conventions

Naming mirrors glam-rs exactly (modules, types, methods). `pub trait Vec3Trait` +
`pub impl Vec3Impl of Vec3Trait`; operator impls `Vec3Add`, `Vec3Neg`, ...; conversions
`Vec2IntoVec3`; panic messages `'<Type>: <reason>'` (<= 31 chars).

Hard rules (each one is backed by a measurement in report 05 section 6 / report 03 R1-R12):

1. Value types are `#[derive(Copy, Drop, Serde, PartialEq, Debug, Default, Hash)]` structs of
   named scalar fields with `pub` fields, passed **by value**. No `Array`, `Span`, `Felt252Dict`
   or loop in any fixed-size math (a `Span`+loop `Mat3*Mat3` is 9.2x the unrolled one).
2. Products go through the fused kernels of `fixed::wide`: one rescale per output scalar.
3. `#[inline(always)]` on every scalar operator, constructor, accessor and kernel helper. Public
   kernels are the only call boundaries. Large bodies (`Mat4::inverse`, `slerp`) are not inlined.
   Any inlining decision on a hot path is backed by a snapshot delta. Bytecode is the price
   (`docs/audits/R1-bytecode-size.md`, #31): an inlined item is paid at every call site (51 CASM
   felts for `Fixed * Fixed`, ~900 for `Mat4::mul_mat4`, ~1 100 for a camera `perspective`), a
   non-inlined one once per class (`powf` 9.3k); a kitchen-sink contract of 22 entry points sits
   at 62 % of the 81 920-felt class limit. The library does not ship non-inlined twins: a
   consumer short of bytecode wraps the call site in its own `#[inline(never)]` function
   (+15 to +42 % gas on that call), which is possible in that direction only; the compiler's
   `inlining-strategy` is left at its default (`avoid` costs +177 % gas). `gas/bytecode.size`
   tracks the fixture sizes in CI.
4. No bitwise operators. Masks and shifts are `DivRem` by a constant power of two
   (`NonZero` const). Never `pow(2, n)` at runtime.
5. Tables are `const [T; N]` + `.span()` (1 270 gas, size independent); dispatch is `match` on a
   small integer (2 370). Never if-chains.
6. Stay <= 64-bit operands. No `u128` multiplication, no `u256`, no `felt252 -> int` conversion
   in hot paths unless measured.
7. Plain panicking operators only: `wrapping_*` / `checked_*` / `saturating_*` are slower.
8. One `DivRem::div_rem` instead of `/` and `%`. Do not recompute derived values.
9. When the cheapest formulation is not obvious, implement the candidates (math / bitwise / loop /
   table), bench them all, keep the winner in the library and the losers in `benches::alt` with
   their benches, so the comparison stays reproducible across compiler upgrades.
10. No stubbed success: an unported function does not exist.

Re-exports: `glam/src/lib.cairo` re-exports types and traits only (`pub use vec3::{Vec3, Vec3Trait};`).
The glam-rs constructor functions (`vec3(x, y, z)`, `bvec3(..)`) share their module's name, and
in Cairo a root re-export of the function shadows the module (`glam::vec3::Vec3` stops resolving):
import them from their module (`use glam::vec3::vec3;`).

Gas accounting note (measured on `eigen3`, #34): inside a function Sierra gas is charged for the
most expensive branch whichever one runs (a skipped Jacobi rotation still cost its 38 040 gas),
while steps count what ran; only the iterations of a loop are metered as they execute. So a
cheap early-out saves steps, not gas, unless it is the exit condition of a `while`; and benches
of branching functions carry several inputs (`_first` / `_last` ...) mainly for the steps and
for the cases where the compiler does redeposit the gas of the cheaper branch.

Doc template (every public item):

```cairo
/// Computes the dot product of `self` and `rhs`.
///
/// Mirrors `glam::Vec3::dot`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
```

## 5. Tests and gas tracking

- Correctness tests: `packages/<pkg>/tests/test_<module>.cairo`. Golden vectors come from glam-rs
  (`=0.33.8`, f64 `D*` types as the oracle, inputs quantized to Q32.32 first) via the generator in
  `tools/refgen`; tolerances are budgeted in raw ULPs and justified (0 for exact ops, ~`dim` ULP
  for dot / matrix products, relative to the determinant for inverses). Plus edge cases, seeded
  fuzz properties (`#[fuzzer(runs: 256, seed: ...)]`) and `#[should_panic(expected: ...)]` with
  the exact message for every panic path.
- Benchmarks: `packages/benches/tests/bench_<module>.cairo`. A bench `X` is a pair of tests
  `X__base` / `X__op` with the same prelude; inputs go through `bb`, results through `sink`
  (`#[inline(never)]`), otherwise the compiler constant-folds the work down to the empty-test
  floor (13 620 gas). **Every public function of `fixed` and every non-trivial public function of
  `glam` has a bench.**
- `scripts/bench.py snapshot` writes `gas/<module>.snap` (l2_gas = Sierra gas, the north star;
  steps, range checks and bitwise cells, the prover's cost). `scripts/bench.py check` fails on any
  difference; CI runs it, so every gas change is a reviewable diff in the pull request.
- `scripts/check.sh` = fmt + lint (`--deny-warnings`) + build + tests + snapshot check + docs.

## 6. Versioning

Pre-1.0. PATCH: fixes/perf with identical API **and identical numeric results**. MINOR: any API
change or any change of a numeric result (downstream determinism depends on bit-exact outputs).
Siblings pin a tag: `{ git = "https://github.com/bal7hazar/glam-cairo", tag = "vX.Y.Z" }`, never
a branch. Compiler bumps are dedicated pull requests that regenerate every snapshot.
