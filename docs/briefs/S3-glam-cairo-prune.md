# S3 - `glam-cairo` without `fixed` and `glamx`

Read `docs/SPLIT.md` first, then `docs/briefs/R1-common.md` (foreground only, gate under `flock`,
one scarb / snforge command at a time) and `docs/briefs/COMMON.md`. `fixed-cairo` and
`glamx-cairo` exist and are green (they were extracted from this repository at `3843c6c`);
nothing of `fixed` / `glamx` is lost by deleting it here.

Branch `chore/split-prune`, one pull request on `glam-cairo` (normal flow: never merge).

1. **Dependencies**: `glam` (and `benches`, `consumer`) depend on the **published**
   `fixed = "0.3.0"` (registry, `[workspace.dependencies]`) instead of `packages/fixed`. Delete
   `packages/fixed` and `packages/glamx`. `Scarb.lock` records the registry checksum.
2. **Benches**: delete the benches, `alt` modules, `[[test]]` targets and `gas/*.snap` of `fixed`,
   `wide`, `trig`, `exp`, `eigen3`, `pose2`, `pose3`, `rot2`, `rot3`, `sdp`. Every remaining
   `gas/*.snap` must stay **byte-identical** (the registry `fixed` 0.3.0 is `main`'s: a difference
   means otherwise: stop and report).
3. **Consumer / bytecode**: keep one glam-only fixture (e.g. `GlamSink`: the `KitchenSink` entry
   points that use `glam` only: `Vec3`, `Quat`, `Mat3` / `Mat4` inverse, `slerp`, Euler, camera);
   the scalar and glamx fixtures now live in `fixed-cairo` / `glamx-cairo`. Regenerate
   `gas/bytecode.size`.
4. **Scripts**: delete `gen_bounded.py`, `gen_trig.py`, `gen_exp.py`, `gen_eigen3.py` and their
   lines in `check.sh` / CI. Prune `panic_coverage.py`, `deviations.py`, `gas_tables.py`,
   `bytecode_size.py`, `bench.py` of `fixed` / `glamx`. `api_parity.py`: it also inventories the
   `Fixed` scalar against `f32`; keep that section by reading the `fixed` 0.3.0 sources from the
   registry cache (`scarb metadata --format-version 1` gives the package root) if that is simple
   and deterministic; otherwise restrict the table to `glam` and say so in the report.
   `docs/API_PARITY.md` regenerated.
5. **refgen**: delete the specs / oracles of `fixed`, `wide`, `eigen3`, `pose2`, `pose3`, `rot2`,
   `sdp`; drop the `glamx` crate dependency (`Cargo.lock` regenerated); the remaining golden files
   byte-identical.
6. **CI**: the test matrix is `glam` only; everything else as today; `all-checks` the single
   required status.
7. **Documents you may edit**: `README.md` (packages table: `glam` here, links to `fixed-cairo`
   and `glamx-cairo`; generated gas tables), `packages/glam/README.md`, `AGENTS.md` (repository
   map, commands), `docs/DESIGN.md` section 1 (the package table becomes the repository table of
   `docs/SPLIT.md`) and section 2 (replace the body by a short summary of what `glam` relies on
   and a link to `fixed-cairo`'s `docs/DESIGN.md`, which now owns it). Do not edit `CHANGELOG.md`,
   `docs/PORTING_STATUS.md`, `docs/HANDOFF.md`, `docs/ORCHESTRATOR.md`, `docs/SPLIT.md`,
   `docs/research`, `docs/audits`, `docs/briefs` (the orchestrator's or historical).
   `packages/glam/src/**` doc comments that link to a deleted path: point them to the new
   repository, nothing else in the sources changes.

Done: gate green in the foreground, commits `chore(split): ...` with your model's trailer, pull
request `chore(split): glam-cairo depends on fixed 0.3.0 from the registry; fixed and glamx moved
out`, CI green, `REPORT.md` (what was deleted, what stayed, byte-identity checks, the api_parity
choice). Do not merge.
