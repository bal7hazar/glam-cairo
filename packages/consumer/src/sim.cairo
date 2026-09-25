//! The logic shared by the contracts: plain functions over the library types.

use fixed::{Fixed, FixedTrait, ONE, ZERO};
use glam::camera::rh::proj::opengl;
use glam::camera::rh::view::look_at_mat4;
use glam::{
    EulerRot, Mat3, Mat3Trait, Mat4, Mat4Trait, Quat, QuatEulerTrait, QuatTrait, Vec2, Vec2Trait,
    Vec3, Vec3Trait,
};

fn f(raw: i64) -> Fixed {
    FixedTrait::from_raw(raw)
}

// ---------------------------------------------------------------------------------------------
// 2D

/// Circle-circle contact: the normal from `a` to `b` and the penetration depth, if any.
pub fn circle_contact(a: Vec2, ra: Fixed, b: Vec2, rb: Fixed) -> Option<(Vec2, Fixed)> {
    let d = b - a;
    let r = ra + rb;
    if d.length_squared() >= r * r {
        return None;
    }
    Some((d.normalize_or_zero(), r - d.length()))
}

// ---------------------------------------------------------------------------------------------
// 3D

/// Contact frame of a body at `origin` with orientation `rotation`: the world normal, a tangent
/// and the signed distance of a world point along the normal.
pub fn contact_frame(
    rotation: Quat, origin: Vec3, point: Vec3, local_normal: Vec3,
) -> (Vec3, Vec3, Fixed) {
    let n = rotation.mul_vec3(local_normal).normalize();
    let t = n.cross(Vec3Trait::X).normalize_or_zero();
    (n, t, (point - origin).dot(n))
}

/// Rotated and inverted inertia tensor through `Mat3` products: `(R M R^T)^-1`.
pub fn inertia_basis(m: Mat3, q: Quat) -> Mat3 {
    let r = Mat3Trait::from_quat(q);
    r.mul_mat3(m).mul_mat3(r.transpose()).inverse()
}

// ---------------------------------------------------------------------------------------------
// Heavy remaining items

/// Inverse of a `Mat4` applied to a point.
pub fn mat4_inverse_point(m: Mat4, p: Vec3) -> Vec3 {
    m.inverse().transform_point3(p)
}

/// Spherical interpolation between two orientations, then its Euler angles, rebuilt as a quat.
pub fn slerp_euler(a: Quat, b: Quat, s: Fixed) -> Quat {
    let (y, x, z) = a.slerp(b, s).to_euler(EulerRot::YXZ);
    QuatEulerTrait::from_euler(EulerRot::YXZ, y, x, z)
}

/// Projects a world point through a right-handed OpenGL camera.
pub fn camera_project(eye: Vec3, center: Vec3, fov: Fixed, aspect: Fixed, p: Vec3) -> Vec3 {
    let up = Vec3Trait::new(ZERO, ONE, ZERO);
    let proj = opengl::perspective(fov, aspect, ONE, f(100 * 0x100000000));
    proj.mul_mat4(look_at_mat4(eye, center, up)).project_point3(p)
}
