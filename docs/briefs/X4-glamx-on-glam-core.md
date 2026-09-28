# X4 - glamx 0.4.1: depend on `glam_core` instead of the `glam` facade

Repository **`bal7hazar/glamx-cairo`**, branch `feat/glam-core-dep`, one pull request. Read that
repository's `AGENTS.md`, and from the glam-cairo checkout (read-only, `git -C
/home/claude/projects/glam-cairo show origin/main:<path>`): `docs/briefs/COMMON.md`,
`docs/briefs/R1-common.md` (foreground only; crate-scoped local checks; CI is the full gate; cold
builds under `flock ~/orchestrator/heavy-build.lock`), and `docs/audits/PK-G-glam-cut-plan.md`.

Base: the draft pull request glamx-cairo #4 (branch `scratch/glamx-dep-glam-core`, measured in
PK-G4: -0.45 s / -0.25 GB for an empty consumer, 145 benches identical). Re-apply its dependency
change on a fresh branch from `origin/main` (glamx-cairo #3, the new `consumer_cost.py`, is merged
since), then add what the programme session's release conditions require:

1. **Type identity for a consumer of the facade**: an unpublished fixture package
   (`publish = false`, e.g. `packages/facade_check`) that depends on the **registry**
   `glam = "0.4.1"` and on `glamx` (path), builds values with `glam::vec3::Vec3`, `glam::quat::Quat`,
   `glam::mat4::Mat4` (and `Vec2` / `Mat3` where glamx takes them) through the facade paths, passes
   them to `glamx` functions (`Pose3`, `Rot2` / `Pose2`, `SdpMatrix3`, `SymmetricEigen3`...) and
   checks a result: `snforge` tests that compile and pass in CI. A type mismatch would fail to
   compile: that is the proof.
2. Dependency `glam_core = "0.4.1"` (registry) instead of `glam` for the `glamx` package; the
   workspace keeps `glam` only for the fixture. `consumer_cost.toml`: the glamx closure becomes
   `glam_core@0.4.1` + `fixed@0.4.0`. Gas snapshots byte-identical to `main`;
   `gas/bytecode.size` regenerated (class bytes only; Sierra / CASM felts unchanged: check it).
3. Release preparation (allowed in this lot): workspace version `0.4.1`; `CHANGELOG.md` section
   `[0.4.1]` with "Changed: depends on `glam_core` instead of the `glam` facade (closure -0.45 s /
   -0.25 GB); no API change"; `README.md` states the dependency (`glam_core`, `fixed`) and that
   `glamx` values interoperate with `glam` facade users (the fixture proves it).

Pull request `feat(glamx): depend on glam_core (0.4.1)`, CI green (including `Consumer cost`
enforcing), `REPORT.md`. Then close draft #4 without merging it (`gh pr close 4 -R
bal7hazar/glamx-cairo --comment "superseded by <new PR>"`). Do not merge the new pull request, do
not tag, do not publish: the orchestrator does.
