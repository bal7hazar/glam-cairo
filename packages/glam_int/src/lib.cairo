//! The methods of the integer vectors of the glam port: `IVec2Trait` .. `UVec4Trait` (constants,
//! constructors, `checked_*` / `wrapping_*` / `saturating_*`, ...) and the `ivec2` .. `uvec4`
//! constructors. The types and the operator / conversion impls are in `glam_core`; use both
//! through the `glam` facade (`glam::ivec2::{IVec2, IVec2Trait, ivec2}`).

pub mod ivec2;
pub mod ivec3;
pub mod ivec4;
pub mod uvec2;
pub mod uvec3;
pub mod uvec4;
pub use ivec2::IVec2Trait;
pub use ivec3::IVec3Trait;
pub use ivec4::IVec4Trait;
pub use uvec2::UVec2Trait;
pub use uvec3::UVec3Trait;
pub use uvec4::UVec4Trait;
