# glam_int

The methods of the integer vectors of the [`glam`](https://github.com/bal7hazar/glam-cairo/tree/main/packages/glam) port of
[glam-rs](https://github.com/bitshifter/glam-rs) 0.33.8: `IVec2Trait` .. `UVec4Trait` (constants,
`checked_*` / `wrapping_*` / `saturating_*`, shifts, ...) and the `ivec2` .. `uvec4` constructors.

The types `IVec2` .. `UVec4` and the impls of the core traits for them (`+`, `-`, `.into()`, ...)
are in [`glam_core`](https://github.com/bal7hazar/glam-cairo/tree/main/packages/glam_core), on which this crate depends: Cairo finds such an impl without
an import only in the module of the type. Use both through the [`glam`](https://github.com/bal7hazar/glam-cairo/tree/main/packages/glam) facade
(`glam::ivec2::{IVec2, IVec2Trait, ivec2}`); depend on `glam_int` directly to skip the float
swizzles.

Compatible with Cairo 2.20.0.
