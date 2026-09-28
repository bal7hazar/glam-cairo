# PK-G part B - glam cut plan (measurements, no code moved)

Toolchain: scarb 2.19.4 / Cairo 2.19.4, starknet-foundry 0.61.0. Measured on `main` at `8e7a5bf`
(`glam` 0.4.0). The rule (`docs/briefs/PK-G-package-size.md`): a published crate has at most 40 000
library lines; an empty cold consumer of it adds at most 5 s / 1 GB. Prototypes, scripts and the
measurement workflow are on the scratch branch `scratch/pk-g-glam-cut` (never merged; run
`36407831302`, two attempts); nothing in this plan changes `packages/`.

## 1. Summary

* `glam` fails the rule on **lines only** (41 484 > 40 000). Its cold consumer already passes the time
  and memory gates: **2.1 s / 0.70 GB** (GitHub runner, 5 cold builds per sample, two samples: 2.1 and
  2.5 s, 0.70 and 0.69 GB). The cut is therefore a line-count and core-footprint decision, not a
  build-time emergency.
* Any of the three cuts brings every crate under 40 000 lines. Measured, they only differ by what the
  *core* costs and by what the API loses.
* **Recommendation: cut (c3), four crates behind a facade**: `glam_core` (16 330 lines, **0.43 GB,
  about 1.3 to 1.7 s**, -39 % memory against today), `glam_swizzles` (float swizzles, 4 798),
  `glam_int` (integer vectors and the float -> integer casts, 10 781) and `glam_int_swizzles`
  (integer swizzles, 9 595), plus `glam` (53 lines: re-exports under today's paths). It is the only
  layout where each of the four consumer profiles pays for what it uses only.
* The **one** thing that cannot stay path-identical is the method-call syntax of
  `Vec{2,3,4}Trait::as_ivec*` / `as_uvec*` (section 5): it needs one extra `use` in the caller.
  Everything else measured stays identical (95 distinct `use glam::...` statements of the tests,
  benches and consumer fixture resolve; `.into()` between integer and float vectors resolves without an
  import).
* If an API change of `as_ivec*` is unacceptable, **cut (a)** (swizzles only, section 4.1) changes no
  path at all and passes the gate (27 056 + 14 392 lines); it leaves the integer vectors in the core
  (core = 0.54 GB instead of 0.43 GB).
* Zero step change: proven on the prototype (section 6): 9 bench modules bit-identical to `gas/*.snap`,
  all six test targets pass (1 685 tests in the crate), `GlamSink` has the same Sierra and CASM felts.

## 2. Dependency facts (confirmed from the `use crate::...` lines)

| module | depends on |
|---|---|
| `bvec2..4` | nothing |
| `ivec{n}`, `uvec{n}` | `bvec{n}` and the other integer vectors; no float type, no `fixed` |
| `vec{n}` | `bvec{n}`, `vec{m}`, **`ivec{n}`, `uvec{n}`** (only `as_ivec{n}` / `as_uvec{n}`, the `to_u32` helper and the `Into<IVec{n}, Vec{n}>` / `Into<UVec{n}, Vec{n}>` impls), `quat` (vec3 only) |
| `mat*`, `quat`, `affine*`, `euler`, `camera` | float types only |
| `swizzles/vec{n}` | `vec{2,3,4}` only |
| `swizzles/ivec{n}`, `swizzles/uvec{n}` | the integer vectors of the same family only |

The float and the integer swizzle traits are distinct (`Vec3Swizzles`, `IVec3Swizzles`, ...): the
integer ones never reference a float type and vice versa. So every edge between the "float world" and
the "integer world" is the four casts of section 5: that is the only thing to place to avoid a cycle.

Lines per family today (`consumer_cost.py --modules`): swizzles 14 399 (float 4 791, integer 9 582),
integer vectors 10 538, 3D 5 912, 4D 4 240, 2D 3 376, camera 1 622, bvec 771, euler 577, lib 49.

## 3. Prototype

`scratch/make.py SRC OUT VARIANT` builds a workspace from `packages/glam/src` by text transformation
(no hand edit): it cuts the four items out of `vec{2,3,4}.cairo`, hosts them in `glam_int`, rewrites
`crate::` paths across crates and writes a `glam` facade with `pub use glam_core::vec2;`-style module
re-exports. Every variant `scarb build`s, `scarb doc` builds, and `scarb lint` reports only three
unused imports of the prototype.

Crates of each variant (all depend on `fixed`; arrows = "depends on"):

```
a   glam_swizzles (float + int) -> glam_core (everything else)
b   glam_int (ints, casts, int swizzles) -> glam_core (floats, bvec, camera, float swizzles)
c1  glam_swizzles (float + int) -> glam_int -> glam_core
c2  glam_swizzles (float) -> glam_core <- glam_int (ints, casts, int swizzles)
c3  glam_swizzles (float) -> glam_core <- glam_int <- glam_int_swizzles
    facade `glam` -> every crate above (all variants)
```

Where the integer swizzles go (programme criterion 2):

| option | variant | verdict |
|---|---|---|
| in `glam_swizzles`, which then depends on `glam_int` | c1 | float-swizzle consumers pull the integer vectors: 30 722 lines and 0.70 GB instead of 21 128 and 0.49 GB |
| in `glam_int` itself | c2 | integer consumers pay the integer swizzles (9 595 lines): `core + ints` = 36 706 lines and 0.66 GB instead of 27 111 and 0.55 GB. Still under the gate; three crates instead of four |
| a fourth crate `glam_int_swizzles` | c3 | each profile minimal (table below). One more package to publish |

## 4. Measurements

GitHub runner (`ubuntu-latest`, 4 cores, 15 GB), one job per variant, `scripts/consumer_cost.py
--repeat 5` (median of 5 cold builds, `SCARB_INCREMENTAL=false`), "added" = consumer minus the empty
baseline consumer of the same job. Two independent attempts: cells show `s` as `attempt1 / attempt2`
(noise across runner VMs is about +/- 0.4 s; the baseline itself varies from 0.9 to 1.4 s between
jobs), memory is stable to +/- 0.02 GB. Lines = physical lines of the library, tests excluded. The
local numbers (contended 8-core machine) tell the same story.

Today, `glam` alone: **41 484 lines, 2.1 / 2.5 s, 0.70 / 0.69 GB** (FAIL on lines only).

### 4.1 Cut (a): swizzles only (no API change)

| profile | crates | lines | added s | added GB |
|---|---|---:|---|---:|
| core only | `glam_core` (ints inside) | 27 056 | 2.0 / 1.6 | 0.54 |
| core + swizzles | `glam_core` + `glam_swizzles` | 41 448 | 2.4 / 1.8 | 0.71 |
| core + integers | = core only | 27 056 | 2.0 / 1.6 | 0.54 |
| everything (facade) | `glam` | 52 (+ all) | 2.2 / 2.1 | 0.71 |

`glam_swizzles` alone (with its `glam_core` dependency): 14 392 lines, 2.3 / 1.9 s, 0.70 GB.

### 4.2 Cut (b): integer vectors only

The float swizzles stay in `glam_core`; the integer swizzles must follow the integer vectors (they
would otherwise force `glam_core -> glam_int`), i.e. they sit in `glam_int` (option "in `glam_int`").

| profile | crates | lines | added s | added GB |
|---|---|---:|---|---:|
| core only | `glam_core` | 21 128 | 1.5 / 1.7 | 0.49 |
| core + swizzles | = core only | 21 128 | 1.5 / 1.7 | 0.49 |
| core + integers | `glam_core` + `glam_int` | 41 504 | 2.0 / 2.2 | 0.71 |
| everything (facade) | `glam` | 53 (+ all) | 2.0 / 2.3 | 0.70 |

`glam_int` alone: 20 376 lines, 2.0 / 2.4 s, 0.71 GB.

### 4.3 Cut (c): both, three ways of placing the integer swizzles

| profile | c1 (int swizzles in `glam_swizzles`) | c2 (in `glam_int`) | c3 (fourth crate) |
|---|---|---|---|
| core only (`glam_core`) | 16 330 lines, 1.1 / 1.3 s, 0.43 GB | 16 330, 1.7 / 1.4 s, 0.44 GB | 16 330, 1.7 / 1.3 s, 0.43 GB |
| core + swizzles | 30 722, 1.7 / 1.8 s, **0.70 GB** | 21 128, 1.9 / 1.6 s, 0.50 GB | 21 128, 2.1 / 1.5 s, 0.49 GB |
| core + integers | 27 111, 1.4 / 1.6 s, 0.54 GB | 36 706, 2.3 / 1.9 s, **0.66 GB** | 27 111, 2.1 / 1.6 s, 0.55 GB |
| everything (facade) | 53 (+ all), 1.9 / 1.8 s, 0.69 GB | 53, 2.3 / 2.0 s, 0.69 GB | 53, 2.6 / 1.9 s, 0.71 GB |

Per crate (c3): `glam_core` 16 330, `glam_int` 10 781 (alone 2.1 / 1.6 s, 0.54 GB), `glam_swizzles`
4 798 (alone 1.9 / 1.6 s, 0.49 GB), `glam_int_swizzles` 9 595 (alone with its closure `glam_int` + core:
2.4 / 1.8 s, 0.65 GB), `glam` 53. Sum 41 557 lines, +73 against today (headers and imports of the new
crates, the casts trait). The four sub-crates and the facade each pass every gate (lines, 5 s, 1 GB).

Reading:

* Memory is the reliable signal: the core drops from 0.70 to **0.43 GB** (c) or 0.49 / 0.54 GB (b / a).
  The time gain is real but of the order of the noise (about 0.5 to 1 s).
* Every cut passes the rule; (c) is where the *core-only* project (criterion 1) is best served.
* Under (c), the largest profile that is not "everything" is 36 706 lines (c2) or 27 111 (c3): both under
  40 000, so the closures need no further cut for a long time (headroom: the biggest crate of c3 is the core, 16 330 lines).

## 5. The integer <-> float casts and the facade (criteria 2 and 4)

Cycle-free layering (b, c): `glam_int` depends on `glam_core` (it needs `BVec*`), never the reverse.
The four things that mention both worlds move to `glam_int`:

| item (today, in `vec{n}.cairo`) | after the cut |
|---|---|
| `Vec{n}Trait::as_ivec{n}`, `Vec{n}Trait::as_uvec{n}` (declarations and impls) | extension trait `Vec{n}IntCasts` (prototype name; final name to follow the `XTrait` / `XImpl` convention, e.g. `Vec{n}IntCastTrait`) in `glam_int::casts`, re-exported as `glam::casts::*` and at the facade root |
| `to_u32` (private helper) | private helper of `glam_int::casts` (`'Vec{n}: cast out of range'` messages unchanged) |
| `IVec{n}IntoVec{n}` (`Into<IVec{n}, Vec{n}>`) | in the module `glam_int::ivec{n}` |
| `UVec{n}IntoVec{n}` (`Into<UVec{n}, Vec{n}>`) | in the module `glam_int::uvec{n}` |

Verified on a scratch crate and on the prototype: Cairo finds an `Into<IVec2, Vec2>` impl hosted in the
module of the *source* type without any import, so `let v: Vec2 = iv.into();` keeps compiling
unchanged (with the impl in the module of the *cast* trait instead, it fails with E2311: that is why
the `Into` impls go to `ivec{n}` / `uvec{n}`).

**What cannot be kept path-identical**, exhaustively (all 95 distinct `use glam::...` statements of
`packages/glam/tests`, `packages/benches`, `packages/consumer` resolve against the facade of every
variant; the six test targets compile):

1. `v.as_ivec2()` / `v.as_uvec2()` / `...3` / `...4` on a float vector: method-call syntax needs the
   trait in scope, so the caller adds `use glam::casts::Vec2IntCasts;` (the facade cannot merge the
   new trait into `Vec2Trait`: Cairo has no supertraits). `Vec2Trait::as_ivec2(v)` (call by trait path)
   also stops working. In this repository that is one added `use` in 6 test / golden files
   (`test_vec{2,3,4}`, `golden_vec{2,3,4}`) and 3 bench files (`bench_vec{2,3,4}`); no other
   repository of the programme uses `as_ivec*`, `as_uvec*`, integer vectors or swizzles
   (`nalgebra-cairo`, `rapier-cairo`, `glamx-cairo` checked by grep).
2. Documentation paths: `scarb doc` and the generated `docs/API_PARITY.md` list the casts under the
   new trait instead of `Vec{n}Trait`. Nothing else moves: the `Into` impls are found as before.

Alternatives for the casts, all rejected:

| alternative | verdict |
|---|---|
| Keep the integer vectors below the core (`glam_core` depends on `glam_int`, `bvec*` moves down with them) | no API change at all, but the core carries the integer vectors: identical to cut (a)'s core (27 056 lines, 0.54 GB). Contradicts criterion 1 and the "`bvec*` stays in the core" fact. It is the fallback if 1. is unacceptable |
| `Into<Vec2, IVec2>` / `Into<Vec2, UVec2>` in `glam_int::ivec2` | call sites need no import, but it invents `From` impls that glam-rs does not have and drops the name `as_ivec2` (rule 5), and `as_uvec2` panics: an `Into` must not |
| A facade-level `Vec2Trait` that repeats the ~150 methods and delegates | duplicated declarations to maintain, the delegation must be `#[inline(always)]` to keep the steps: rejected as noise for one method pair |
| Generic parameter on `Vec2Trait` | no |

The **facade** `glam`: `pub use glam_core::vec2;`, `pub use glam_int::ivec2;`, ... keeps `glam::vec2::Vec2`,
`glam::ivec2::IVec2`, `glam::camera::rh::view::look_at_mat4`, the crate-root re-exports and
`glam::swizzles::{Vec2Swizzles, ...}` (a `pub mod swizzles { pub use ...; }` per variant). The
constructors `vec2(..)` etc. stay at their module path. Modules re-exported whole cannot get extra
items, hence the new trait sits at `glam::casts`, not at `glam::vec2`.

## 6. Zero step change (criterion 3)

Prototype c3 with the repository's own tests, benches and fixture pointed at the facade (only the nine
`use` lines of section 5, item 1, added), everything on the same commit:

| check | result |
|---|---|
| `snforge test` `test_integers`, `test_swizzles`, `test_vectors`, `test_matrices`, `test_rotations`, `test_camera` | 477 + 15 + 500 + 198 + 246 + 251 passed, 0 failed (fuzzer `--fuzzer-runs 32 --fuzzer-seed 1` as in CI) |
| `scripts/bench.py check` `bench_vec2/3/4`, `bench_uvec2`, `bench_ivec4`, `bench_swizzles`, `bench_camera`, `bench_quat`, `bench_mat4` | `gas snapshot OK`, 9 modules bit-identical (l2_gas, steps, builtins) to the committed `gas/*.snap` |
| `scripts/bytecode_size.py check` (`GlamSink`) | Sierra felts 9 773 and CASM felts 21 040 and CASM bytes 622 848 identical; Sierra class bytes +182 (510 547 -> 510 729, +0.04 %, longer crate names in the debug info) |

By construction: no function body changes, `#[inline(always)]` is kept, and the compiler inlines across
crates. The one moved-cast trait is a pure re-homing (the same `Fixed::to_int_trunc` bodies).

## 7. The later lot (after the programme session's go)

Order, one pull request each unless said, no release in between (publishing intermediate layouts would
freeze paths):

1. **Layout**: new `packages/glam_core`, `glam_swizzles`, `glam_int`, `glam_int_swizzles` (`Scarb.toml`
   per package, workspace `[workspace.dependencies]`, the orchestrator owns those files), `glam`
   becomes the facade + the tests.
2. **Generators**: `tools/codegen/fvec.py` stops emitting the four casts items (and the `to_u32` helper);
   `tools/codegen/intvec.py` emits the `Into` impls and `casts`; `tools/codegen/swizzles.py` writes
   per-crate output. `--check` of the three generators stays in `fmt-lint`. Also `tools/refgen`
   (goldens live in the facade's `tests/`, no change) and `scripts/affected.py`
   (`GLAM_SRC`, `MODULES`, `USE_RE` assume one crate: it must map a changed file to the crates'
   dependents), `scripts/bench.py`, `scripts/bytecode_size.py`, `scripts/gas_tables.py`,
   `scripts/api_parity.py`, `scripts/panic_coverage.py` (all read `packages/glam/src`).
3. **Tests / benches**: unchanged files, one added `use` in the nine files of section 5; they keep
   compiling as integration tests of the facade (compile budget: the test crates compile the whole
   closure exactly as today).
4. **CI**: `Consumer cost` job becomes enforcing (drop the allowlist step of `.github/workflows/ci.yml`),
   `consumer_cost.toml` gets closures (`core_swizzles`, `core_int`, `core_int_swizzles`); one snapshot of
   the sizes goes to the changelog.
5. **Docs**: `docs/DESIGN.md` (crate layout), `docs/SPLIT.md`, README of each crate, `CHANGELOG.md`,
   `docs/API_PARITY.md`; the release order is `fixed` -> `glam_core` -> `glam_int`, `glam_swizzles` ->
   `glam_int_swizzles` -> `glam`. `nalgebra-cairo`, `rapier-cairo` and `glamx-cairo` keep depending on
   `glam` (facade) unchanged; they may narrow to `glam_core` later to save the build (that is their
   choice, measured by their own `Consumer cost`).

Open points to decide with the programme session: (1) accept the `as_ivec*` import (recommended) or take
cut (a) as the whole cut; (2) c3 (four crates, recommended) or c2 (three crates, `core + ints` at
36 706 lines, still under the gate); (3) final names (`glam_core`, `glam_int`, `glam_swizzles`,
`glam_int_swizzles`; extension trait `Vec{n}IntCastTrait`); (4) whether the tests move with the crates
(not needed: they test the facade).

## 8. Reproduce

`python3 scratch/make.py packages/glam/src /tmp/w c3 && python3 scratch/cfg.py c3 /tmp/w && cp
scripts/consumer_cost.py /tmp/w/ && (cd /tmp/w && python3 consumer_cost.py --report-only --repeat 5)`
on the scratch branch, or the workflow `.github/workflows/pkg-cost.yml` of that branch (matrix
`today`, `a`, `b`, `c1`, `c2`, `c3`, artifacts `cost-<variant>`). Local heavy runs go through
`flock ~/orchestrator/heavy-build.lock`.
