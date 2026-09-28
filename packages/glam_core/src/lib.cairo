//! The core of the glam port: the `fixed` Q32.32 vectors, matrices, quaternions, affine
//! transforms, the camera helpers and the integer vector *types* with the impls of the core traits
//! for them. Use it through the `glam` facade, or directly to depend on the smallest crate.
//!
//! Module names mirror glam-rs one-to-one. The methods of the integer vectors (`IVec2Trait`, ...)
//! live in `glam_int`, the swizzles in `glam_swizzles` / `glam_int_swizzles`; the `glam` facade
//! re-exports all of them under the paths of a single crate.

pub mod affine2;
pub mod affine3;
pub mod bvec2;
pub mod bvec3;
pub mod bvec4;
pub mod camera;
pub mod euler;
pub mod ivec2;
pub mod ivec3;
pub mod ivec4;
pub mod mat2;
pub mod mat3;
pub mod mat4;
pub mod quat;
pub mod uvec2;
pub mod uvec3;
pub mod uvec4;
pub mod vec2;
pub mod vec3;
pub mod vec4;
pub use affine2::{Affine2, Affine2Trait};
pub use affine3::{Affine3, Affine3RigidTrait, Affine3Trait};

pub use bvec2::{BVec2, BVec2Trait};
pub use bvec3::{BVec3, BVec3Trait};
pub use bvec4::{BVec4, BVec4Trait};
pub use euler::{EulerRot, Mat3EulerTrait, Mat4EulerTrait, QuatEulerTrait};
pub use ivec2::IVec2;
pub use ivec3::IVec3;
pub use ivec4::IVec4;
pub use mat2::{Mat2, Mat2Trait};
pub use mat3::{Mat3, Mat3Trait};
pub use mat4::{Mat4, Mat4Trait};
pub use quat::{Quat, QuatTrait};
pub use uvec2::UVec2;
pub use uvec3::UVec3;
pub use uvec4::UVec4;
pub use vec2::{Vec2, Vec2Trait};
pub use vec3::{Vec3, Vec3Trait};
pub use vec4::{Vec4, Vec4Trait};
