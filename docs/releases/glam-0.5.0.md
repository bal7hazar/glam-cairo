# Request to publish the glam family 0.5.0

Written by the orchestrator thread t-0081 of the glam track. Nothing is published, tagged or
released by this document: it asks the project manager for a go naming package, version, commit
and archive SHA-256.

Release commit: `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e` (main, PR #69, "glam 0.5.0 on fixed
0.5.0"). Every archive was built with `scarb package -p <name>` from a clean checkout whose HEAD
was exactly this commit, before any commit of this request (each archive embeds the building
checkout's HEAD in `VCS.json`, so a checkout of another commit gives another hash).

## What is released

- All five packages move to 0.5.0 and depend on `fixed` 0.5.0 (published, was `^0.4.0`).
- AP's 92 additions: `Sum` / `Product` (50 items), `from_span` / `write_to` and the matrix
  variants (33 items), and `map` of the vector types.
- MINOR result change (`CHANGELOG.md` [0.5.0]): `Quat::to_axis_angle` and `Quat::to_scaled_axis`
  return a different axis for a vector part of length in `[2^-16, 2^-8)`; every other input gives
  the same result as 0.4.1.
- Requested by nalgebra-cairo, which moves to simba 0.3.0 on glam 0.5.0.
- Publication is in dependency order: `glam_core`, then `glam_int`, `glam_swizzles` and
  `glam_int_swizzles`, then `glam`.

## Packages

| Package | Version | Commit | SHA-256 | Built on |
|---|---|---|---|---|
| `glam_core` | 0.5.0 | `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e` | `a5e6e4863acfc4be492e06f8f965a16982b8a8975a5179a903d64092a9f05975` | srv1792539 (VPS), `/home/claude/.herdr/worktrees/glam-cairo/hp-slingfall-glam-t-0081-glam-0-5-0-publication-request`, 2026-10-03T20:30:11Z |

`glam_core-0.5.0.tar.zst`: 33 files, 754.74 KiB, 67.26 KiB compressed (68 878 bytes). Verification
(`Verifying` and `Compiling` in the packaged copy) passed; peak memory 1 159 652 KiB under
`prlimit --as=8589934592`.

## Packages that follow after `glam_core` 0.5.0 is published

Each depends on `glam_core ^0.5.0`, which is not on the registry yet, so `scarb package`
verification fails. No workaround was used (no `--no-verify`, `--allow-dirty` or `--index`). Each
follows after glam_core 0.5.0 is published: its archive and SHA-256 are then built from the same
commit in a follow-up to this request.

| Package | Version | Exact error (2026-10-03, 20:30 UTC, same host and path) |
|---|---|---|
| `glam_int` | 0.5.0 | `error: failed to verify package tarball` / `Caused by: 0: cannot get dependencies of \`glam_int@0.5.0\`` / `1: cannot find package \`glam_core ^0.5.0\`` |
| `glam_swizzles` | 0.5.0 | `error: failed to verify package tarball` / `Caused by: 0: cannot get dependencies of \`glam_swizzles@0.5.0\`` / `1: cannot find package \`glam_core ^0.5.0\`` |
| `glam_int_swizzles` | 0.5.0 | `error: failed to verify package tarball` / `Caused by: 0: cannot get dependencies of \`glam_int_swizzles@0.5.0\`` / `1: cannot find package \`glam_core ^0.5.0\`` |
| `glam` | 0.5.0 | `error: failed to verify package tarball` / `Caused by: 0: cannot get dependencies of \`glam@0.5.0\`` / `1: cannot find package \`glam_core ^0.5.0\`` |

`glam` also needs the three other packages published first.

## Go requested now

Package `glam_core`, version 0.5.0, commit `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e`, archive
SHA-256 `a5e6e4863acfc4be492e06f8f965a16982b8a8975a5179a903d64092a9f05975`.
