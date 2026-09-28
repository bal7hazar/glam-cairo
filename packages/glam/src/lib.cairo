//! Port of glam-rs (https://github.com/bitshifter/glam-rs) on top of the `fixed` Q32.32 scalar.
//!
//! Module names mirror glam-rs one-to-one. See `docs/PORTING_STATUS.md` for progress.
//!
//! This crate is a facade: it re-exports `glam_core`, `glam_int`, `glam_swizzles` and
//! `glam_int_swizzles` under the paths of a single crate (`glam::vec3::Vec3`, `glam::Vec3Trait`,
//! `glam::swizzles::Vec3Swizzles`, ...). Depend on the smaller crates to pay for less code.

pub use glam_core::{
    affine2, affine3, bvec2, bvec3, bvec4, camera, euler, mat2, mat3, mat4, quat, vec2, vec3, vec4,
};
pub mod ivec2;
pub mod ivec3;
pub mod ivec4;
pub mod swizzles;
pub mod uvec2;
pub mod uvec3;
pub mod uvec4;
pub use affine2::{Affine2, Affine2Trait};
pub use affine3::{Affine3, Affine3RigidTrait, Affine3Trait};

pub use bvec2::{BVec2, BVec2Trait};
pub use bvec3::{BVec3, BVec3Trait};
pub use bvec4::{BVec4, BVec4Trait};
pub use euler::{EulerRot, Mat3EulerTrait, Mat4EulerTrait, QuatEulerTrait};
pub use ivec2::{IVec2, IVec2Trait};
pub use ivec3::{IVec3, IVec3Trait};
pub use ivec4::{IVec4, IVec4Trait};
pub use mat2::{Mat2, Mat2Trait};
pub use mat3::{Mat3, Mat3Trait};
pub use mat4::{Mat4, Mat4Trait};
pub use quat::{Quat, QuatTrait};
pub use swizzles::{
    IVec2Swizzles, IVec3Swizzles, IVec4Swizzles, UVec2Swizzles, UVec3Swizzles, UVec4Swizzles,
    Vec2Swizzles, Vec3Swizzles, Vec4Swizzles,
};
pub use uvec2::{UVec2, UVec2Trait};
pub use uvec3::{UVec3, UVec3Trait};
pub use uvec4::{UVec4, UVec4Trait};
pub use vec2::{Vec2, Vec2Trait};
pub use vec3::{Vec3, Vec3Trait};
pub use vec4::{Vec4, Vec4Trait};
