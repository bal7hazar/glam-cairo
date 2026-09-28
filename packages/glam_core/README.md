# glam_core

The core of the [`glam`](https://github.com/bal7hazar/glam-cairo/tree/main/packages/glam) port of [glam-rs](https://github.com/bitshifter/glam-rs) 0.33.8:
`Vec2/3/4`, `Mat2/3/4`, `Quat`, `Affine2/3`, `BVec*`, the Euler angles, `camera`, and the integer
vector *types* `IVec2/3/4`, `UVec2/3/4` with the impls of the core traits for them (operators,
conversions, indexing). Built on the [`fixed`](https://github.com/bal7hazar/fixed-cairo) Q32.32
scalar. Same module, type and method names as glam-rs.

Depend on `glam_core` when you need the vectors, matrices and quaternions only: it is the smallest
build (about 18 500 library lines). The methods of the integer vectors are in `glam_int`, the
swizzles in `glam_swizzles` / `glam_int_swizzles`; the [`glam`](https://github.com/bal7hazar/glam-cairo/tree/main/packages/glam) facade re-exports all of
them under the paths of a single crate.

The `pub fn` helpers of `glam_core::ivec*` / `uvec*` (`bitand_i32`, ...) exist so that `glam_int`
can reach them: they are internal, not re-exported by `glam`, and not part of the API.

Compatible with Cairo 2.19.4. Gas tables: [`glam`](https://github.com/bal7hazar/glam-cairo/tree/main/packages/glam#gas).
