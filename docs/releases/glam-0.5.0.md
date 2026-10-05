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

## Stage 1: published

- `glam_core` 0.5.0 was published on 2026-10-05 by the orchestrator, by hand (`scarb publish -p
  glam_core`, under `prlimit --as=8589934592`), from a clean clone detached at
  `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e`, after the archive SHA-256 matched the go. Go: the
  project manager (slingfall).
- Registry read-back: scarbs.xyz index, version 0.5.0, cksum
  `sha256:a5e6e4863acfc4be492e06f8f965a16982b8a8975a5179a903d64092a9f05975` (equal to the request),
  dependency `fixed ^0.5.0`.

## Stage 2: request

| Package | Version | Commit | SHA-256 | Built on |
|---|---|---|---|---|
| `glam_int` | 0.5.0 | `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e` | `b8067667ba5985bbf53d43b7bbf80a09c5b205c1abae5722af5d97082495a0bc` | srv1792539 (VPS), clean clone detached at b5bd10f, 2026-10-05T07:17Z, verification passed, peak RSS 1 162 172 KiB under the 8 GiB cap |
| `glam_swizzles` | 0.5.0 | `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e` | `54389e759f14c0fd59ececd829387f703488cdf72c383592f3671b63d0eabd79` | same, peak 1 094 636 KiB |
| `glam_int_swizzles` | 0.5.0 | `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e` | `f9886ae154bb9e267888353e84dfedc097c48c02bbe863e59bd1fffa9d0d65bf` | same, peak 1 151 936 KiB |

Stage 3 (glam, the facade) follows after these three are published: it depends on them.

## Stage 2: published

- `glam_int`, `glam_swizzles`, `glam_int_swizzles` 0.5.0 were published on 2026-10-05, in that
  order, by the orchestrator, by hand (`scarb publish -p <name>`, under `prlimit --as=8589934592`),
  from a clean clone detached at `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e`, after each archive's
  SHA-256 matched the go. Go: the project manager (slingfall), three rows.
- Registry read-back (scarbs.xyz index), each equal to the request, each depending on
  `glam_core ^0.5.0` and `fixed ^0.5.0`:
  `glam_int` `sha256:b8067667ba5985bbf53d43b7bbf80a09c5b205c1abae5722af5d97082495a0bc`;
  `glam_swizzles` `sha256:54389e759f14c0fd59ececd829387f703488cdf72c383592f3671b63d0eabd79`;
  `glam_int_swizzles` `sha256:f9886ae154bb9e267888353e84dfedc097c48c02bbe863e59bd1fffa9d0d65bf`.

## Stage 3: request

| Package | Version | Commit | SHA-256 | Built on |
|---|---|---|---|---|
| `glam` | 0.5.0 | `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e` | `e7ff692eb6c33d81926abffe72df7fbda83d9daa232fe313ac3ae5b2d345521e` | srv1792539 (VPS), clean clone detached at b5bd10f, 2026-10-05T07:38Z, verification passed (62 files), peak RSS 1 272 900 KiB under the 8 GiB cap |

After stage 3: the tag `v0.5.0` on b5bd10f and the GitHub release of glam-cairo.

## Stage 3: published

- `glam` 0.5.0 was published on 2026-10-05 by the orchestrator, by hand (`scarb publish -p glam`,
  under `prlimit --as=8589934592`), from a clean clone detached at
  `b5bd10f69d4f3e7127dd28c6f96d0ff2164b5e5e`, after the archive's SHA-256 matched the go. Go: the
  project manager (slingfall).
- Registry read-back: version 0.5.0, cksum
  `sha256:e7ff692eb6c33d81926abffe72df7fbda83d9daa232fe313ac3ae5b2d345521e` (equal to the request),
  depending on `glam_core`, `glam_int`, `glam_swizzles`, `glam_int_swizzles` `^0.5.0` and `fixed ^0.5.0`.
- Tag: `v0.5.0` (annotated, on `b5bd10f`). Release:
  https://github.com/bal7hazar/glam-cairo/releases/tag/v0.5.0.

The glam 0.5.0 family is complete on the registry: glam_core, glam_int, glam_swizzles, glam_int_swizzles, glam.
