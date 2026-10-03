//! The consumer case of `Sum` / `Product`: only the types are imported from the facade, the
//! impls are found without a `use` and the glam-rs method form `.sum()` / `.product()` works.

use fixed::fixed::{Fixed, FixedTrait};
use glam::{IVec2, Mat3, Quat, Vec3};

fn f(k: i32) -> Fixed {
    FixedTrait::from_int(k)
}

fn v3(x: i32, y: i32, z: i32) -> Vec3 {
    Vec3 { x: f(x), y: f(y), z: f(z) }
}

fn diag(x: i32, y: i32, z: i32) -> Mat3 {
    Mat3 { x_axis: v3(x, 0, 0), y_axis: v3(0, y, 0), z_axis: v3(0, 0, z) }
}

fn q(x: i32, y: i32, z: i32, w: i32) -> Quat {
    Quat { x: f(x), y: f(y), z: f(z), w: f(w) }
}

#[test]
fn test_vec3_method_form() {
    let s: Vec3 = array![v3(1, 2, 3), v3(4, 5, 6)].into_iter().sum();
    assert!(s == v3(5, 7, 9), "sum");
    let p: Vec3 = array![v3(1, 2, 3), v3(4, 5, 6)].into_iter().product();
    assert!(p == v3(4, 10, 18), "product");
}

#[test]
fn test_ivec2_method_form() {
    let s: IVec2 = array![IVec2 { x: 1, y: 2 }, IVec2 { x: 3, y: 4 }].into_iter().sum();
    assert!(s == IVec2 { x: 4, y: 6 }, "sum");
    let p: IVec2 = array![IVec2 { x: 1, y: 2 }, IVec2 { x: 3, y: 4 }].into_iter().product();
    assert!(p == IVec2 { x: 3, y: 8 }, "product");
}

#[test]
fn test_mat3_method_form() {
    let s: Mat3 = array![diag(2, 3, 4), diag(1, 1, 1)].into_iter().sum();
    assert!(s == diag(3, 4, 5), "sum");
    let p: Mat3 = array![diag(2, 3, 4), diag(2, 2, 2)].into_iter().product();
    assert!(p == diag(4, 6, 8), "product");
}

#[test]
fn test_quat_method_form() {
    let s: Quat = array![q(1, 0, 0, 0), q(0, 1, 0, 0)].into_iter().sum();
    assert!(s == q(1, 1, 0, 0), "sum");
    let p: Quat = array![q(1, 0, 0, 0), q(0, 1, 0, 0)].into_iter().product();
    assert!(p == q(0, 0, 1, 0), "i * j = k");
}
