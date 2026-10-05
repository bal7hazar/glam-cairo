# Execution plan

How the port is sequenced and delegated. Status per item lives in `docs/PORTING_STATUS.md`;
design decisions in `docs/DESIGN.md`; evidence in `docs/research/`.

## Operating model

- One **orchestrator** session owns sequencing, task briefs, review, merges, the serialized files
  (`Scarb.toml`, `lib.cairo` files, `scripts/**`, `.github/**`, `docs/DESIGN.md`,
  `docs/PORTING_STATUS.md`, `CHANGELOG.md`) and the
  releases. It does not write large implementations.
- **Porter sub-agents** each own exactly one module: source + tests + benches + docs, in an
  isolated git worktree and branch (`feat/<module>`), delivered as one pull request.
- Every module file, test file and bench file already exists as an empty stub and is already
  declared in the `lib.cairo` files, and gas snapshots are one file per module
  (`gas/<module>.snap`): **parallel pull requests never touch a shared file**.
- Merge gate: CI `all-checks` green (fmt, lint, build, tests, gas snapshot check, docs) + the
  orchestrator's review of API parity, deviations and the gas table. Squash merge.
- When the optimum is unclear, the porter implements the variants (math / bitwise / loop / table),
  benches them, ships the winner and leaves the losers in `benches::alt` (DESIGN rule 9).

## Waves

Dependencies come from the glam-rs analysis (report 01 section 4). Items inside a wave are
independent and run in parallel; a wave starts when the modules it depends on are merged.

### Wave 0 - foundations (orchestrator, serialized) - DONE in the bootstrap PR
Research reports, workspace, toolchain pin, bench harness + snapshot script, CI, `AGENTS.md`,
`DESIGN.md`, this plan.

### Wave 1 - the scalar (critical path)
| id | task | depends on |
|---|---|---|
| F1 | `fixed` tier A: consts, `from_*`/`to_*`, `Add Sub Mul Div Rem Neg`, `PartialOrd`, `abs signum copysign min max clamp`, `floor ceil round trunc fract fract_gl`, `recip`, `sqrt`, `div_euclid rem_euclid`, `lerp`-family (`FloatExt`), `Zero`/`One`, bounded-int plumbing generator | - |
| F2 | `fixed::wide`: accumulator types, `dot2/3/4`, `mul_sub`, `mul_add`, `norm2/3/4`, wide-sum API for larger kernels | F1 (same agent, second PR) |
| F3 | `fixed::trig` tier B: `sin cos sin_cos tan atan2 acos asin` + coefficient generator + bit-exact Python mirror + error sweeps | F1 |
| T1 | `tools/refgen`: Rust crate pinned to glam `=0.33.8` generating golden vectors (f64 oracle, Q32.32-quantized inputs, seeded) as Cairo test data | - (parallel with F1) |

### Wave 2 - vectors (parallel, after F1+F2; `angle`/`rotate` methods need F3)
| id | task |
|---|---|
| V0 | `BVec2`, `BVec3`, `BVec4` |
| V2 | `Vec2` core (incl. `perp`, `perp_dot`, `angle_to`, `rotate`, `from_angle`) |
| V3 | `Vec3` core (incl. `cross`, `any_orthonormal_pair`; Quat-dependent methods deferred to wave 4) |
| V4 | `Vec4` core |
| VI | `IVec2/3/4` and `UVec2/3/4` (independent of `fixed`, can start in wave 1) |

### Wave 3 - matrices and quaternion (parallel)
| id | task | depends on |
|---|---|---|
| M2 | `Mat2` | V2 |
| M3 | `Mat3` (core: no `from_quat`, no `Mat4` conversions) | V2, V3 |
| M4 | `Mat4` (core) | V3, V4 |
| Q1 | `Quat` core (`mul_quat`, `mul_vec3`, `normalize`, `from_axis_angle`, `from_scaled_axis`, `to_axis_angle`, `lerp`/`nlerp`, `slerp`, `inverse`, ...) | V3, V4, F3 |
| S1 | swizzle traits for `Vec2`, `Vec3` (generated) | V2, V3, V4 |

### Wave 4 - cross-type integration (parallel)
| id | task | depends on |
|---|---|---|
| X1 | cycle-closing methods: `Vec3::rotate_*`, `Mat3/Mat4::from_quat`, `Quat::from_mat3/4`, `Mat2<->Mat3<->Mat4` conversions, TRS compose / decompose | M2-M4, Q1 |
| A2 | `Affine2` | M2, (M3 for conversions) |
| A3 | `Affine3` | M3, Q1, (M4 for conversions) |
| E1 | `EulerRot` (24 orders) and the `from_euler`/`to_euler` methods | M3, Q1 |

### Wave 5 - completion
| id | task |
|---|---|
| C1 | `camera` module (`rh`/`lh` x `view` / `proj::{opengl,vulkan,directx}`), deprecated `Mat4::perspective_*`/`look_at_*` aliases skipped |
| S2 | `Vec4` and integer swizzles |
| F4 | `fixed` tier C: `exp exp2 ln log2 powf` and the element-wise vector wrappers |
| P0 | bootstrap of the `glamx` package (manifest, stubs, CI matrix, benches dependency, refgen `glamx =0.3.1` f64 oracle): done by the orchestrator. Scope and priorities: `docs/research/06-glamx-scope.md` |
| P1a | `glamx::pose3` (+ `rot3` alias of `Quat`): `Pose3 { rotation: Quat, translation: Vec3 }`, fused `inv_mul`, `transform_point`... |
| P1b | `glamx::rot2`: `Rot2 { re, im }` |
| P1c | `glamx::pose2` (after P1b) |
| P1d | `glamx::sdp`: parry's `SdpMatrix3` / `SdpMatrix2` and the fused world-inertia kernel `R D R^T` |
| P1e | `glamx::eigen3`: `SymmetricEigen3` (setup-time only, low priority; `Svd*`, `SymmetricEigen2`, look-at are not ported: no consumer in parry / rapier) |
| X2 | `IVec*/UVec*::as_vec*` casts (gap found by the P1 research; needed by voxel code) |
| R1 | audit pass: API parity table vs glam-rs 0.33.8, optimizer pass over the top-20 hottest benches, README gas tables, `v0.1.0` tag, publish `fixed` then `glam` on scarbs.xyz |

The physics-critical path is `F1 -> F2 -> V3 -> M3 + Q1 -> A3/P1`. The 2D track
(`V2 -> M2 -> A2`) is independent and is the cheapest end-to-end slice.

## Porter brief template

Each delegation message contains: the task id and goal; the glam-rs source files to mirror
(`docs/research` clone path or URL at tag 0.33.8); the files the agent may edit (its module, its
test file, its bench file, its `gas/<module>.snap`, `benches/src/alt/<module>.cairo`); the API list; acceptance = `scripts/check.sh` green +
definition of done of `AGENTS.md`; and the report format. Agents read `AGENTS.md` and
`docs/DESIGN.md` first.

## Risks

| risk | mitigation |
|---|---|
| `core::internal::bounded_int` changes or breaks (unstable API; misuse = compiler panic) | isolated in `fixed::internal`, generated plumbing, pinned toolchain, stable fallback in `benches::alt` |
| overflow panics make a physics step unprovable (liveness) | document ranges per kernel, `try_*` variants where glam has them, engine-level bounds belong to `rapier-cairo` |
| f32-tuned epsilons meaningless at 2^-32 resolution | re-derived per call site in ULPs (DESIGN section 3) |
| bytecode growth from `inline(always)` + polynomial segments | track class size once a consumer contract exists (wave 5 audit) |
| gas numbers shift with compiler releases | snapshots are per-toolchain; bumps are dedicated PRs |

## Status (2026-10-05): PAUSED by the owner's decision

The whole Slingfall programme is paused, libraries included: no new lot, thread, release or publication until the
owner lifts it (`hp resume`). Nothing of this track is running.

**Published (scarbs.xyz)**
- `fixed` 0.5.0 (fixed-cairo `v0.5.0`, release commit `693ca3e`, PR #12): `ExpTrait::{sinh_cosh, asinh, acosh,
  atanh}` (F8, PR #11); registry checksum `697d3e82…0fb9` read back equal to the go.
- `glam_core` 0.5.0 (glam-cairo release commit `b5bd10f`, PR #69) on `fixed` 0.5.0: AP's 92 glam-rs items (Sum /
  Product, `from_span` / `write_to`, `map`; PR #67), Q-AA's MINOR result change of `Quat::to_axis_angle` /
  `to_scaled_axis` (PR #68); registry checksum `a5e6e486…5975` read back equal to the go. Record:
  `docs/releases/glam-0.5.0.md`.

**Merged, not released**
- fixed-cairo `main`: FS (PR #15), `narrow32` is at the Scarb 2.20 libfunc floor (no reformulation wins);
  `norm{2,3,4}_squared` / `distance{2,3,4}_squared` drop the sign bias (-1 step each, `distance4_squared` -9). Its
  CHANGELOG entry is still to add with the next fixed lot. D1 (PR #10): `gen_trig.py check` reproducible.
- All three repositories: the pre-push check and hook, path-gated CI, PR-only cancel-in-progress, retries of the
  scarb and snforge downloads.

**Stopped by the pause (not published)**
- glam 0.5 family, stage 2: `glam_int`, `glam_swizzles`, `glam_int_swizzles` 0.5.0. Their archives were built from
  `b5bd10f` and their SHA-256 are in `docs/releases/glam-0.5.0.md` (PR #72); the request was not sent for a go.
- Stage 3: the `glam` facade 0.5.0, which depends on stage 2.
- `glamx` 0.5.0 on `glam_core` 0.5.0: not prepared.

**Next lots, when the pause is lifted**
1. Stage 2 then stage 3 of the glam 0.5 family (go, publish in dependency order, read-back), then the tag `v0.5.0`
   and the GitHub release of glam-cairo.
2. `glamx` 0.5.0 on `glam_core` 0.5.0 (release PR, request, go, publish).
3. The next `fixed` release when it has a reason (FS's sum-of-squares wins; its CHANGELOG entry).
4. Backlog on request: P2 (parked on the parry-split decision); small review notes kept in the orchestrator's task
   list (golden filter widening, wretry on Node 20, a `reconcile` self-test, two stale `fixed 0.3.0` mentions).

## Status (2026-10-02)

The track runs as the herdr project `slingfall-glam` (coordinator plus threads, see
`docs/ORCHESTRATOR.md` and `docs/HANDOFF.md`). Everything planned for the day is merged:
- orchestration documents aligned with herdr (glam-cairo #53) and the toolchain briefs (#54);
- toolchain bump D-180, in order: TC-F fixed-cairo #5 (`d444ffe`), TC-G glam-cairo #55
  (`ca32b37`), TC-X glamx-cairo #7 (`230d848`). The three repositories are on Scarb 2.20.1 /
  starknet-foundry 0.64.0, Cairo pins 2.20.0 (Scarb 2.20.1 bundles Cairo 2.20.0). No numeric
  change anywhere and no release: the published `fixed` 0.4.0, `glam` 0.4.1 and `glamx` 0.4.1 are
  unchanged.
- Gas: `l2_gas` only; steps, builtins and bytecode sizes are unchanged. `fixed`: 76 of 278 rows
  -120. `glam`: 1 160 rows -120, with calls that use the Bitwise builtin +100 relative to that
  (uvec bit operations net +100, ivec net -20) and `bvec` `benches::alt` span literals +10 per
  element. `glamx`: 82 rows -120.

The track is idle. Backlog, on request only: F8, P2, D1.

Rule to carry: the first Cairo / Scarb release carrying starkware-libs/cairo#10359 (closure names
become path-free) changes every closure-holding class hash and needs a re-pin lot of its own; no
class hash is pinned in this track today.

## Resume point (2026-09-29, clean stop: weekly quota nearly exhausted)

Everything below is on `main` of each repository; no agent runs, no pull request is open, no
release is pending, no work sits in a worktree (the only worktree left is the orchestrator's own).

**Published** (scarbs.xyz, each from its own repository, each on the programme session's written
go under the owner's delegation):
- `fixed` 0.4.0 (fixed-cairo `v0.4.0`, `d3215fe`): adds `ExpTrait::{sinh, cosh, tanh, sinhc,
  coshc}` (<= 1.5 ULP, round-half-even division since 0.3.0).
- `glam` 0.4.1 (glam-cairo `v0.4.1`, `674b613`): non-breaking split, `glam` is a facade over
  `glam_core` (18.7k lines: float types, `BVec*`, integer vector types and their operator impls,
  `as_ivec*` kept on `Vec{n}Trait`), `glam_int`, `glam_swizzles`, `glam_int_swizzles`; every 0.4.0
  path unchanged, every gas snapshot identical (`docs/audits/PK-G-glam-cut-plan.md`, #48-#50).
- `glamx` 0.4.1 (glamx-cairo `v0.4.1`, `30dbdb6`): depends on `glam_core` 0.4.1 + `fixed` 0.4.0
  instead of the `glam` facade (-0.45 s / -0.25 GB); `packages/facade_check` proves that `glam`
  facade values are glamx's types.

**Gates**: `Consumer cost` enforcing in the three repositories (`scripts/consumer_cost.py` and
`scripts/packages_table.py` copied unchanged from nalgebra-cairo `ded2847`); `docs/PACKAGES.md` in
each repository shows every package against 40 000 lines / 5 s / 1 GB marginal and every closure
against 15 s / 3 GB: all pass, smallest margin `glam_core` lines (+53 %). CI: six-family test
matrix and `scripts/affected.py` selective runs on pull requests (full run on `main`, ~6 min).

**Open backlog** (`docs/PORTING_STATUS.md` for the rows; nothing is urgent, nothing is started):
- F8 (`fixed-cairo`, next MINOR 0.5.0): `ExpTrait::sinh_cosh(x) -> (Fixed, Fixed)` sharing one
  exponential (nalgebra-cairo escalation: separate `sinh` + `cosh` = 57 540 gas at x = 1.5, ~29 890
  expected); `asinh` / `acosh` / `atanh` only if asked. Launch when more `fixed` work accumulates
  or a consumer asks for the release; then `glam` / `glamx` follow only if their dependency must
  move (pure addition in `fixed`: `^0.4` consumers need a MINOR bump of `fixed` to 0.5.0 only if
  they want the new function).
- P2 (`glamx-cairo`): rapier's measured `Pose2` fused kernels (its PR #21), only if the owner
  approves a parry split.
- D1 (`fixed-cairo`): `gen_trig.py` fit is still platform-dependent (`gen_exp.py` fixed in F7).
- Small debts: the golden headers of `fixed-cairo` still say "glam-rs 0.33.8 (f64)"; one relative
  link in the generated region of `packages/glam/README.md` (`scripts/gas_tables.py`); the
  appendix of `docs/audits/R1-deviations.md` is a dated snapshot (not gated); the branch
  `scratch/pk-g-glam-cut` on glam-cairo holds the PK-G prototype (never merge; delete when
  unneeded).

**How the next session starts**: read `docs/HANDOFF.md` (reading order, repositories and local
layout, operating loop, rules), then this section and the inbox `pm/messages/to-glam/`. Rules in
force: implementation lots on the `claude` CLI (Sonnet / Opus / Fable by difficulty), codex only
for audits; at most 6 sub-agents machine-wide; task descriptions start with the model; agents run
crate-scoped checks, the pull request CI is the full gate; cold builds under
`flock ~/orchestrator/heavy-build.lock`; releases only on a written go of the owner or the
programme session ("Angry Birds Cairo orchestration"); launch agents with `scripts/agent.sh`
(systemd user units), check `scripts/agent.sh status` before relaunching anything.
