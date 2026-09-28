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

## Start signal and practical details (2026-09-28, programme session)

NS0 is merged in nalgebra-cairo (PR #61, `bff3462`). Copy the script **unchanged**:
`gh api "repos/bal7hazar/nalgebra-cairo/contents/scripts/consumer_cost.py?ref=bff3462" -q .content | base64 -d > scripts/consumer_cost.py`
(stdlib Python, repository-agnostic), and read nalgebra's `consumer_cost.toml` the same way as the
model of the per-repository configuration. Do not edit nalgebra-cairo or its checkout.
- One `consumer_cost.toml` per repository; one CI job named `Consumer cost`, **non-blocking**
  until glam's cut lands (then enforcing: the orchestrator flips it).
- Its line count is physical lines reachable from the lib root minus test-only files and blocks.
- Builds are sequential, under the programme's machine-wide lock:
  `flock ~/orchestrator/heavy-build.lock <command>` for every cold build / measurement run locally
  (it replaces `/tmp/glam-cairo-gate.lock` for heavy builds).
- Worktrees prepared by the orchestrator: glam-cairo `.claude/worktrees/cli-pkg` (branch
  `chore/consumer-cost`), fixed-cairo `.claude/worktrees/cli-pkg` (same branch), glamx-cairo
  `.claude/worktrees/cli-pkg` (same branch). One pull request per repository for part A; part B's
  plan in the glam-cairo pull request (or a second one), never code moved.

## Part B2 - variant B (programme session, 2026-09-28): remove the path change

The four crates and the names `glam_core` / `glam_swizzles` / `glam_int` / `glam_int_swizzles` are
agreed. Variant B, to measure on the scratch branch `scratch/pk-g-glam-cut` (never merged):
`glam_core` also holds the integer vector **types** (`struct IVec2/3/4`, `UVec2/3/4` and their
derives), and the float -> int casts (`as_ivec*`, `as_uvec*`) stay methods of the existing
`Vec{n}Trait`; `glam_int` holds everything else about the integer vectors (their method traits,
constants, int -> float casts). Operator impls of core traits for the integer types (`Add`, `Sub`,
`Mul`, `Neg`, `PartialEq`...): put them where Cairo's impl lookup finds them without an import
for a consumer of `glam_int`; if that forces them into `glam_core`, count their lines there.

Report for A (the plan) and B: `glam_core` lines, added time / memory (GitHub runners), whether
every `use glam::...` path of today is unchanged, and the step / Sierra / CASM identity.
**Decision rule**: B wins if `glam_core` stays under 22 000 lines and its measured cost is within
15 % of A's; otherwise A, with the extra `use glam::casts::Vec{n}IntCastTrait` recorded as a
deviation from glam-rs. Update `docs/audits/PK-G-glam-cut-plan.md` with the B measurements and
the verdict (a small pull request on glam-cairo), and put a two-line result at the top of
`REPORT.md`. No code moved on `main`.
