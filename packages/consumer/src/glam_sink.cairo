//! The `glam` entry points of the former `KitchenSink`: `Vec2` / `Vec3`, `Quat`, `Mat3` / `Mat4`
//! inverse, `slerp`, Euler conversions and a camera projection.

#[starknet::contract]
pub mod GlamSink {
    use fixed::Fixed;
    use glam::{Mat3, Mat4, Quat, Vec2, Vec3};
    use crate::sim;

    #[storage]
    struct Storage {}

    #[external(v0)]
    fn contact(
        self: @ContractState, a: Vec2, ra: Fixed, b: Vec2, rb: Fixed,
    ) -> Option<(Vec2, Fixed)> {
        sim::circle_contact(a, ra, b, rb)
    }

    #[external(v0)]
    fn contact_frame(
        self: @ContractState, rotation: Quat, origin: Vec3, point: Vec3, local_normal: Vec3,
    ) -> (Vec3, Vec3, Fixed) {
        sim::contact_frame(rotation, origin, point, local_normal)
    }

    #[external(v0)]
    fn inertia_basis(self: @ContractState, m: Mat3, q: Quat) -> Mat3 {
        sim::inertia_basis(m, q)
    }

    #[external(v0)]
    fn mat4_inverse_point(self: @ContractState, m: Mat4, p: Vec3) -> Vec3 {
        sim::mat4_inverse_point(m, p)
    }

    #[external(v0)]
    fn slerp_euler(self: @ContractState, a: Quat, b: Quat, s: Fixed) -> Quat {
        sim::slerp_euler(a, b, s)
    }

    #[external(v0)]
    fn camera_project(
        self: @ContractState, eye: Vec3, center: Vec3, fov: Fixed, aspect: Fixed, p: Vec3,
    ) -> Vec3 {
        sim::camera_project(eye, center, fov, aspect, p)
    }
}
