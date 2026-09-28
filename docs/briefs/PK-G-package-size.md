# PK-G - package-size gate in the three repositories, glam cut plan

Owner's rule of 2026-09-28 (`/home/claude/projects/pm/decisions/2026-09-28-package-granularity-rule.md`,
measurements `/home/claude/projects/pm/research/R7-package-granularity.md`): a published crate has
at most 40 000 library lines (inline tests excluded); an empty consumer of the crate alone adds at
most 5 s and 1 GB to the no-dependency build (cold); scopes follow the upstream module tree, a
facade keeps names and paths; zero extra Cairo steps; checked in CI with a shared script
(`scripts/consumer_cost.py`, merged by nalgebra-cairo's lot NS0: copy it from there).

Read `docs/briefs/R1-common.md` and `docs/briefs/COMMON.md` first (foreground only; crate-scoped
local checks; CI is the full gate; **timings come from GitHub runners or from a quiet machine,
never from contended local runs**).

## Part A - the CI gate (three pull requests, one per repository)

In `fixed-cairo`, `glam-cairo`, `glamx-cairo`: add `scripts/consumer_cost.py` (copied, not
reinvented) and one CI job running it on the package(s) of the repository, wired into
`all-checks`. `fixed` (10.9k lines) and `glamx` (3.3k) pass. For `glam` (41 484 lines today), the
job may fail on lines only: ship the job with the `glam` line threshold marked as a known failure
(allowlisted with a pointer to this brief) until part B lands, rather than a red `main`.

## Part B - glam cut: measurements and a plan (NO code moved in this lot)

Library lines of `packages/glam/src` today: swizzles 14 399, integer vectors (`ivec*`, `uvec*`)
10 538, 3D (`vec3`, `mat3`, `quat`, `affine3`) 5 912, 4D 4 240, 2D 3 376, camera 1 622, boolean
vectors 771, euler 577, lib 49.

Dependency facts (read the `use crate::...` lines to confirm and complete them):
- the float vectors return `BVecN` from their comparisons: **`bvec*` stays in the core crate**;
- the integer vectors depend only on `bvec*` and other integer vectors (no float type);
- `vec2.cairo` depends on the integer vectors through `Vec2Trait::as_ivec2` / `as_uvec2` and the
  `Into<IVec2, Vec2>` / `Into<UVec2, Vec2>` impls it hosts (likewise `vec3`, `vec4`);
- the swizzle traits are distinct per type (`Vec2Swizzles`, `IVec2Swizzles`, ...), declared in
  `swizzles/<type>.cairo` and re-exported by `swizzles.cairo`.

Programme criteria, in this order:
1. **Measured consumer cost of what remains in the core crate**: a project that only wants
   `Vec2` / `Vec3` / `Mat*` / `Quat` is the case to optimise.
2. **No dependency cycle**: the float <-> integer conversions live in the crate that depends on
   the other; the swizzle traits in `glam_swizzles` with the impls for the core types. Say where
   the integer-vector swizzles go (options: in `glam_swizzles`, which then depends on
   `glam_int`; in `glam_int` itself, possible because their traits are distinct; or a fourth
   crate) with the measured cost of each option for the four consumer profiles below.
3. **Zero step change** on the gas snapshots.
4. The **`glam` facade** re-exports everything under today's paths. State exactly what cannot be
   kept path-identical (e.g. `as_ivec2` moving from `Vec2Trait` to an extension trait of
   `glam_int` if `glam_int` depends on the core: method-call syntax needs that trait in scope) and
   the alternatives.

Measure, on scratch branches (never pushed as a release, never merged), with the NS0 script:
consumer profiles "core only", "core + swizzles", "core + integers", "everything (facade)", for
(a) `glam_swizzles` cut only, (b) `glam_int` cut only, (c) both. Report lines per crate, cold
build time / peak memory per profile, and the dependency graph. If both cuts pass, doing both is
acceptable (swizzles are a third of the crate and few consumers need them).

Deliverable of part B: `docs/audits/PK-G-glam-cut-plan.md` in a pull request on glam-cairo
(the plan only), plus `REPORT.md`. The orchestrator sends the plan to the programme session;
code moves in a later lot, after its go.

Implementation on the claude CLI (Sonnet); no release in this lot.
