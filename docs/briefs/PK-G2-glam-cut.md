# PK-G2 - cut `glam` into four crates behind the `glam` facade

Read `docs/audits/PK-G-glam-cut-plan.md` (the plan, the measurements and the **verdict between
variants A and B**: implement the winner exactly as measured), `docs/briefs/PK-G-package-size.md`,
`docs/briefs/R1-common.md`, `docs/briefs/COMMON.md` (foreground only; crate-scoped local checks;
CI is the full gate; cold builds under `flock ~/orchestrator/heavy-build.lock`).

Branch `feat/glam-cut`, one pull request on glam-cairo. Agreed by the programme session:
- crates `packages/glam_core`, `packages/glam_swizzles`, `packages/glam_int`,
  `packages/glam_int_swizzles`, and `packages/glam` the **facade** re-exporting everything under
  today's paths (`glam::vec3::Vec3`, `glam::Vec3Trait`, `glam::swizzles::*`, ...); all share the
  workspace version; dependencies between them by name (`glam_int` depends on `glam_core`, never
  the reverse); each published crate with its README;
- generated modules stay generated: adapt `tools/codegen/*.py` so that they write into the new
  crates (`--check` clean), never hand-edit their output;
- **zero step change**: every `gas/*.snap` byte-identical, `gas/bytecode.size` Sierra / CASM felts
  identical (class bytes may move, say by how much); goldens byte-identical;
- every `use glam::...` of the tests, benches and consumer keeps compiling unchanged, except,
  under variant A only, the documented `use glam::casts::Vec{n}IntCastTrait;` (then add a
  `#### Deviations` bullet on the moved methods and say it in the pull request body for the
  CHANGELOG);
- tests: the six family test targets keep running against the facade; `scripts/affected.py`
  learns the new crate layout (a change in `glam_core` affects everything, in `glam_int` the
  integer targets, ...); `scripts/api_parity.py`, `panic_coverage.py`, `deviations.py`,
  `gas_tables.py`, `bytecode_size.py` read the new source roots;
- `consumer_cost.toml` lists the five crates; the `Consumer cost` CI step becomes **enforcing**
  (remove the allowlisted line verdict of #48): every published crate under 40 000 lines and the
  measured gates.

Report: lines and added cost per crate (GitHub runner), the identity checks, what changed in
paths (nothing, or the variant-A `use`). Do not bump the version, do not edit `CHANGELOG.md`, do
not release: the orchestrator prepares `glam` 0.5.0 (or a patch, if nothing breaks) after merge,
on the programme session's written go. Implementation on the claude CLI (Sonnet).

## Verdict (2026-09-28): variant B

Implement **section 9** of `docs/audits/PK-G-glam-cut-plan.md` (variant B, #49): `glam_core` holds
the integer vector types, their operator / conversion impls (Cairo finds an impl of a core trait
without an import only in the type's own module) and the float -> int casts as methods of
`Vec{n}Trait`, unchanged; `glam_int` holds the integer method traits and constants. **No path
changes at all** (no `Vec{n}IntCastTrait`): no test, bench or consumer `use` may need an edit.
The bodies that the prototype duplicated into `glam_core` (`*AssignScalar` impls, `Into<[i32; n],
_>`) must come from one template in the generator, not be copied by hand; the helpers made `pub`
in `glam_core` for `glam_int` are not re-exported by the facade (doc them as internal). The
prototype (`scratch/make_vb.py`, runner workflow) is on `scratch/pk-g-glam-cut`: reuse it, do not
merge that branch.
