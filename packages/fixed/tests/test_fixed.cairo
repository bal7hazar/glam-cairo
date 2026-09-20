//! Tests of `fixed::fixed`.
//!
//! The expected values of the `*_table` tests were computed offline with Python big integers
//! (exact arithmetic, the rounding of each operation is stated above its table). They cover the
//! edge values (0, +-1 ULP, +-1/2, ties, MIN, MAX, negative operands of the floor rounding) and
//! seeded random operands of every magnitude. The fuzz properties use an independent `i128` /
//! `u128` reference written with the stable corelib.
use core::num::traits::{Bounded, One, Zero};
use fixed::fixed::{
    DEG_TO_RAD, E, EPSILON, FRAC_1_PI, FRAC_1_SQRT_2, FRAC_2_PI, FRAC_BITS, FRAC_PI_2,
    FRAC_PI_2_RAW, FRAC_PI_3, FRAC_PI_4, FRAC_PI_6, FRAC_PI_8, HALF, HALF_RAW, LN_10, LN_2, MAX,
    MIN, NEG_ONE, PI, PI_RAW, RAD_TO_DEG, SQRT_2, TAU, TAU_RAW, TWO,
};
use fixed::{Fixed, FixedTrait, ONE, ONE_RAW, ZERO};

const I64_MIN: i64 = -0x8000000000000000;
const I64_MAX: i64 = 0x7fffffffffffffff;
const ONE_I128: i128 = 0x100000000;

fn f(raw: i64) -> Fixed {
    FixedTrait::from_raw(raw)
}

/// Floor division by 2^32 on the stable API (the corelib `/` truncates toward zero).
fn floor_shift(p: i128) -> i128 {
    let (q, r) = DivRem::div_rem(p, ONE_I128.try_into().unwrap());
    if r < 0 {
        q - 1
    } else {
        q
    }
}

/// Maps a fuzzed `i64` to a magnitude class chosen by `sel` so that small, medium and large
/// operands are all exercised (a uniform `i64` is almost always huge).
fn scale(x: i64, sel: u8) -> i64 {
    match sel % 4 {
        0 => x % 0x10000, // below 2^-16
        1 => x % 0x1000000000, // below 16.0
        2 => x % 0x1000000000000, // below 2^16
        _ => x,
    }
}

// ------------------------------------------------------------------ constants and conversions

#[test]
fn test_constants() {
    assert_eq!(FRAC_BITS, 32);
    assert_eq!(ZERO.raw, 0);
    assert_eq!(ONE.raw, 4294967296);
    assert_eq!(ONE_RAW, 4294967296);
    assert_eq!(NEG_ONE.raw, -4294967296);
    assert_eq!(HALF.raw, 2147483648);
    assert_eq!(HALF_RAW, 2147483648);
    assert_eq!(TWO.raw, 8589934592);
    assert_eq!(MIN.raw, I64_MIN);
    assert_eq!(MAX.raw, I64_MAX);
    assert_eq!(EPSILON.raw, 1);
    // round(x * 2^32), x evaluated with 80 significant digits.
    assert_eq!(PI.raw, 13493037705);
    assert_eq!(PI_RAW, 13493037705);
    assert_eq!(TAU.raw, 26986075409);
    assert_eq!(TAU_RAW, 26986075409);
    assert_eq!(FRAC_PI_2.raw, 6746518852);
    assert_eq!(FRAC_PI_2_RAW, 6746518852);
    assert_eq!(FRAC_PI_3.raw, 4497679235);
    assert_eq!(FRAC_PI_4.raw, 3373259426);
    assert_eq!(FRAC_PI_6.raw, 2248839617);
    assert_eq!(FRAC_PI_8.raw, 1686629713);
    assert_eq!(FRAC_1_PI.raw, 1367130551);
    assert_eq!(FRAC_2_PI.raw, 2734261102);
    assert_eq!(E.raw, 11674931555);
    assert_eq!(SQRT_2.raw, 6074001000);
    assert_eq!(FRAC_1_SQRT_2.raw, 3037000500);
    assert_eq!(LN_2.raw, 2977044472);
    assert_eq!(LN_10.raw, 9889527671);
    assert_eq!(DEG_TO_RAD.raw, 74961321);
    assert_eq!(RAD_TO_DEG.raw, 246083499208);
}

#[test]
fn test_constants_are_consistent() {
    // Each constant is rounded to nearest independently: relations hold within 1 ULP.
    assert!((PI + PI).abs_diff_eq(TAU, EPSILON));
    assert!((FRAC_PI_2 + FRAC_PI_2).abs_diff_eq(PI, EPSILON));
    assert!((SQRT_2 * SQRT_2).abs_diff_eq(TWO, f(2)));
    assert!((SQRT_2 * FRAC_1_SQRT_2).abs_diff_eq(ONE, f(2)));
    assert!((PI * FRAC_1_PI).abs_diff_eq(ONE, f(4)));
    assert!((DEG_TO_RAD * RAD_TO_DEG).abs_diff_eq(ONE, f(64)));
}

#[test]
fn test_from_raw_to_raw() {
    assert_eq!(f(-5).to_raw(), -5);
    assert_eq!(FixedTrait::from_raw(I64_MIN), MIN);
    assert_eq!(MAX.to_raw(), I64_MAX);
    let d: Fixed = Default::default();
    assert_eq!(d, ZERO);
}

#[test]
fn test_from_int() {
    assert_eq!(FixedTrait::from_int(0), ZERO);
    assert_eq!(FixedTrait::from_int(1), ONE);
    assert_eq!(FixedTrait::from_int(-1), NEG_ONE);
    assert_eq!(FixedTrait::from_int(-7).raw, -30064771072);
    assert_eq!(FixedTrait::from_int(0x7fffffff).raw, 0x7fffffff00000000);
    assert_eq!(FixedTrait::from_int(-0x80000000), MIN);
}

#[test]
fn test_into_and_try_into() {
    let a: Fixed = (-128_i8).into();
    assert_eq!(a.raw, -128 * ONE_RAW);
    let b: Fixed = (-32768_i16).into();
    assert_eq!(b.raw, -32768 * ONE_RAW);
    let c: Fixed = (-0x80000000_i32).into();
    assert_eq!(c, MIN);
    let d: Fixed = 255_u8.into();
    assert_eq!(d.raw, 255 * ONE_RAW);
    let e: Fixed = 65535_u16.into();
    assert_eq!(e.raw, 65535 * ONE_RAW);
    let g: Option<Fixed> = 0x7fffffff_u32.try_into();
    assert_eq!(g, Some(f(0x7fffffff00000000)));
    let h: Option<Fixed> = 0x80000000_u32.try_into();
    assert_eq!(h, None);
    let i: Option<Fixed> = (-0x80000000_i64).try_into();
    assert_eq!(i, Some(MIN));
    let j: Option<Fixed> = (-0x80000001_i64).try_into();
    assert_eq!(j, None);
    let k: Option<Fixed> = 0x80000000_i64.try_into();
    assert_eq!(k, None);
    let l: Option<Fixed> = 3_u64.try_into();
    assert_eq!(l, Some(f(3 * ONE_RAW)));
    let m: Option<Fixed> = 0x80000000_u64.try_into();
    assert_eq!(m, None);
}

#[test]
fn test_zero_one_bounded() {
    assert_eq!(Zero::<Fixed>::zero(), ZERO);
    assert!(ZERO.is_zero());
    assert!(!EPSILON.is_zero());
    assert!(EPSILON.is_non_zero());
    assert!(!ZERO.is_non_zero());
    assert_eq!(One::<Fixed>::one(), ONE);
    assert!(ONE.is_one());
    assert!(!f(1).is_one());
    assert!(f(1).is_non_one());
    assert!(!ONE.is_non_one());
    assert_eq!(Bounded::<Fixed>::MIN, MIN);
    assert_eq!(Bounded::<Fixed>::MAX, MAX);
}

#[test]
fn test_partial_ord_and_eq() {
    let a = f(-3);
    let b = f(2);
    assert!(a < b && !(b < a) && !(a < a));
    assert!(a <= b && !(b <= a) && a <= a);
    assert!(b > a && !(a > b) && !(a > a));
    assert!(b >= a && !(a >= b) && a >= a);
    assert!(MIN < MAX && MAX > MIN && MIN <= MIN && MAX >= MAX);
    assert!(a == f(-3) && a != b);
}

#[test]
fn test_assign_operators() {
    let mut x = f(5 * ONE_RAW);
    x += f(HALF_RAW);
    assert_eq!(x.raw, 11 * HALF_RAW);
    x -= ONE;
    assert_eq!(x.raw, 9 * HALF_RAW);
    x *= f(-2 * ONE_RAW);
    assert_eq!(x.raw, -9 * ONE_RAW);
    x /= f(4 * ONE_RAW);
    assert_eq!(x.raw, -9 * ONE_RAW / 4);
    x %= ONE;
    assert_eq!(x.raw, -ONE_RAW / 4);
}

#[test]
fn test_sign_predicates() {
    assert!(f(-1).is_negative() && !ZERO.is_negative() && !f(1).is_negative());
    assert!(f(1).is_positive() && !ZERO.is_positive() && !f(-1).is_positive());
    assert!(f(-1).is_sign_negative() && !ZERO.is_sign_negative());
    assert!(ZERO.is_sign_positive() && f(1).is_sign_positive() && !f(-1).is_sign_positive());
    assert!(MIN.is_negative() && MAX.is_positive());
}

#[test]
fn test_lerp_end_points_are_exact() {
    assert_eq!(MIN.lerp(MAX, ZERO), MIN);
    assert_eq!(MIN.lerp(MAX, ONE), MAX);
    assert_eq!(MAX.lerp(MIN, ONE), MIN);
    assert_eq!(MAX.lerp(MIN, HALF).raw, -1);
    // Extrapolation is allowed.
    assert_eq!(ONE.lerp(TWO, TWO).raw, 3 * ONE_RAW);
    assert_eq!(ONE.lerp(TWO, NEG_ONE), ZERO);
}

#[test]
fn test_rounding_direction_of_mul_and_div() {
    // -1 ULP * 1/2 = -1/2 ULP: floor gives -1 ULP, truncation would give 0.
    assert_eq!((f(-1) * HALF).raw, -1);
    assert_eq!((f(1) * HALF).raw, 0);
    // -1 ULP / 2 = -1/2 ULP: truncation gives 0 (floor would give -1 ULP).
    assert_eq!((f(-1) / TWO).raw, 0);
    assert_eq!((f(1) / TWO).raw, 0);
    assert_eq!((f(-3) / TWO).raw, -1);
    assert_eq!(f(-3 * ONE_RAW).recip().raw, -1431655765);
    assert_eq!(f(3 * ONE_RAW).recip().raw, 1431655765);
}

#[test]
fn test_mul_extremes() {
    assert_eq!(MIN * ONE, MIN);
    assert_eq!(MAX * ONE, MAX);
    assert_eq!(MAX * NEG_ONE, f(-I64_MAX));
    assert_eq!(MIN * ZERO, ZERO);
    assert_eq!((MIN * HALF).raw, I64_MIN / 2);
    // Largest positive product that fits: MIN * (-1 + 1 ULP) = 2^31 - 1/2.
    assert_eq!((MIN * f(-ONE_RAW + 1)).raw, 0x7fffffff80000000);
}

// ------------------------------------------------------------------ panics

#[test]
#[should_panic(expected: 'i64_add Overflow')]
fn test_add_overflow_panics() {
    let _ = MAX + f(1);
}

#[test]
#[should_panic(expected: 'i64_add Underflow')]
fn test_add_underflow_panics() {
    let _ = MIN + f(-1);
}

#[test]
#[should_panic(expected: 'i64_sub Overflow')]
fn test_sub_overflow_panics() {
    let _ = MAX - f(-1);
}

#[test]
#[should_panic(expected: 'i64_sub Underflow')]
fn test_sub_underflow_panics() {
    let _ = MIN - f(1);
}

#[test]
#[should_panic(expected: 'i64_neg Underflow')]
fn test_neg_min_panics() {
    let _ = -MIN;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_overflow_panics() {
    let _ = MIN * NEG_ONE;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_overflow_by_one_ulp_panics() {
    // MAX * (1 + 1 ULP) = MAX + (MAX >> 32) > MAX
    let _ = MAX * f(ONE_RAW + 1);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_underflow_panics() {
    let _ = MIN * f(ONE_RAW + 1);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_min_min_panics() {
    let _ = MIN * MIN;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_assign_overflow_panics() {
    let mut x = MAX;
    x *= TWO;
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_div_by_zero_panics() {
    let _ = ONE / ZERO;
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_div_negative_by_zero_panics() {
    let _ = NEG_ONE / ZERO;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_overflow_panics() {
    let _ = MAX / HALF;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_min_by_neg_one_panics() {
    let _ = MIN / NEG_ONE;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_negative_overflow_panics() {
    let _ = MIN / HALF;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_by_negative_overflow_panics() {
    let _ = MAX / f(-1);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_rem_by_zero_panics() {
    let _ = ONE % ZERO;
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_from_ratio_zero_den_panics() {
    let _ = FixedTrait::from_ratio(1, 0);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_from_ratio_overflow_panics() {
    let _ = FixedTrait::from_ratio(0x80000000, 1);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_abs_min_panics() {
    let _ = MIN.abs();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_copysign_min_panics() {
    let _ = MIN.copysign(ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_ceil_overflow_panics() {
    let _ = f(0x7fffffff00000001).ceil();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_round_overflow_panics() {
    let _ = f(0x7fffffff80000000).round();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_to_int_round_overflow_panics() {
    let _ = f(0x7fffffff80000000).to_int_round();
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_recip_zero_panics() {
    let _ = ZERO.recip();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_recip_overflow_panics() {
    let _ = f(2).recip();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_recip_negative_overflow_panics() {
    let _ = f(-1).recip();
}

#[test]
#[should_panic(expected: 'Fixed: sqrt negative')]
fn test_sqrt_negative_panics() {
    let _ = f(-1).sqrt();
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_div_euclid_by_zero_panics() {
    let _ = ONE.div_euclid(ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_euclid_overflow_panics() {
    let _ = MAX.div_euclid(HALF);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_euclid_negative_overflow_panics() {
    let _ = MIN.div_euclid(f(-1));
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_rem_euclid_by_zero_panics() {
    let _ = ONE.rem_euclid(ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_add_overflow_panics() {
    let _ = MAX.mul_add(ONE, f(1));
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_lerp_overflow_panics() {
    let _ = ZERO.lerp(MAX, TWO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_powi_overflow_panics() {
    let _ = f(65536 * ONE_RAW).powi(2);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_powi_cube_overflow_panics() {
    let _ = f(-2048 * ONE_RAW).powi(3);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_powi_loop_overflow_panics() {
    let _ = TWO.powi(31);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_powi_negative_of_zero_panics() {
    let _ = ZERO.powi(-1);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_inverse_lerp_degenerate_panics() {
    let _ = FixedTrait::inverse_lerp(ONE, ONE, TWO);
}

#[test]
#[should_panic(expected: 'i64_sub Overflow')]
fn test_inverse_lerp_range_overflow_panics() {
    let _ = FixedTrait::inverse_lerp(MIN, MAX, ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_smoothstep_degenerate_panics() {
    let _ = ONE.smoothstep(TWO, TWO);
}

#[test]
#[should_panic(expected: 'i64_sub Overflow')]
fn test_move_towards_range_overflow_panics() {
    let _ = MIN.move_towards(MAX, ONE);
}

#[test]
#[should_panic(expected: 'i64_neg Underflow')]
fn test_move_towards_min_step_panics() {
    let _ = ONE.move_towards(ZERO, MIN);
}

// ------------------------------------------------------------------ properties (seeded fuzzing)

#[test]
#[fuzzer(runs: 256, seed: 101)]
fn fuzz_add_sub_neg_match_i64(x: i64, y: i64) {
    let (a, b) = (x / 2, y / 2);
    assert_eq!((f(a) + f(b)).raw, a + b);
    assert_eq!((f(a) - f(b)).raw, a - b);
    assert_eq!((-f(a)).raw, -a);
    assert_eq!(f(a) + f(b), f(b) + f(a));
}

#[test]
#[fuzzer(runs: 256, seed: 102)]
fn fuzz_mul_is_floor_of_exact_product(x: i64, y: i64, sel: u8) {
    let (a, b) = (scale(x, sel), scale(y, sel / 4));
    let exact: i128 = floor_shift(a.into() * b.into());
    let fits: Option<i64> = exact.try_into();
    if let Some(e) = fits {
        assert_eq!((f(a) * f(b)).raw, e);
        assert_eq!(f(a) * f(b), f(b) * f(a));
        assert_eq!(f(a).mul_add(f(b), ZERO).raw, e);
    }
}

#[test]
#[fuzzer(runs: 256, seed: 103)]
fn fuzz_div_is_trunc_of_exact_quotient(x: i64, y: i64, sel: u8) {
    let (a, b) = (scale(x, sel), scale(y, sel / 4));
    if b != 0 {
        let num: i128 = a.into() * ONE_I128;
        let exact: i128 = num / b.into(); // the corelib signed division truncates
        let fits: Option<i64> = exact.try_into();
        if let Some(e) = fits {
            assert_eq!((f(a) / f(b)).raw, e);
            assert_eq!(FixedTrait::from_ratio(a, b).raw, e);
        }
    }
}

#[test]
#[fuzzer(runs: 256, seed: 104)]
fn fuzz_recip_is_one_over_x(x: i64, sel: u8) {
    let a = scale(x, sel);
    if a > 2 || a < -2 {
        assert_eq!(f(a).recip(), ONE / f(a));
    }
}

#[test]
#[fuzzer(runs: 256, seed: 105)]
fn fuzz_rem_matches_i64_rem(x: i64, y: i64, sel: u8) {
    let (a, b) = (scale(x, sel / 4), scale(y, sel));
    if b != 0 {
        assert_eq!((f(a) % f(b)).raw, a % b);
    }
}

#[test]
#[fuzzer(runs: 256, seed: 106)]
fn fuzz_euclid_decomposition(x: i64, y: i64, sel: u8) {
    let (a, b) = (scale(x, sel / 4), scale(y, sel));
    if b != 0 {
        let r = f(a).rem_euclid(f(b)).raw;
        assert!(r >= 0);
        let r_wide: i128 = r.into();
        let b_wide: i128 = b.into();
        let b_abs = if b_wide < 0 {
            -b_wide
        } else {
            b_wide
        };
        assert!(r_wide < b_abs);
        // a = n * b + r with an integer n
        let (n, zero) = DivRem::div_rem(a.into() - r_wide, b_wide.try_into().unwrap());
        assert_eq!(zero, 0);
        let fits: Option<i64> = (n * ONE_I128).try_into();
        if let Some(e) = fits {
            assert_eq!(f(a).div_euclid(f(b)).raw, e);
        }
    }
}

#[test]
#[fuzzer(runs: 256, seed: 107)]
fn fuzz_rounding_family(x: i64, sel: u8) {
    let a = f(scale(x, sel));
    let fl = a.floor();
    let tr = a.trunc();
    assert!(fl <= a && fl.raw % ONE_RAW == 0);
    assert_eq!(fl.raw + a.fract_gl().raw, a.raw);
    assert!(a.fract_gl() >= ZERO && a.fract_gl() < ONE);
    assert_eq!(tr.raw + a.fract().raw, a.raw);
    assert!(tr.raw % ONE_RAW == 0);
    assert_eq!(tr.raw, (a.raw / ONE_RAW) * ONE_RAW);
    let int_floor: i64 = a.to_int().into();
    let int_trunc: i64 = a.to_int_trunc().into();
    assert_eq!(int_floor * ONE_RAW, fl.raw);
    assert_eq!(int_trunc * ONE_RAW, tr.raw);
    if a.raw < 0x7fffffff00000000 {
        let ce = a.ceil();
        assert!(ce >= a && ce.raw - fl.raw <= ONE_RAW && ce.raw % ONE_RAW == 0);
        let ro = a.round();
        assert!(ro.abs_diff_eq(a, HALF) && ro.raw % ONE_RAW == 0);
        let int_round: i64 = a.to_int_round().into();
        assert_eq!(int_round * ONE_RAW, ro.raw);
        if a.raw > -0x7fffffff00000000 {
            // symmetric: ties away from zero
            assert_eq!((-a).round(), -ro);
        }
    }
}

#[test]
#[fuzzer(runs: 256, seed: 108)]
fn fuzz_abs_signum_copysign(x: i64, y: i64) {
    if x != I64_MIN {
        let a = f(x);
        assert!(a.abs() >= ZERO);
        assert_eq!(a.abs().raw * (a.signum().raw / ONE_RAW), a.raw);
        assert_eq!(a.copysign(f(y)).abs(), a.abs());
        assert_eq!(a.copysign(f(y)).is_negative(), y < 0 && x != 0);
        assert_eq!(a.is_negative(), x < 0);
    }
}

#[test]
#[fuzzer(runs: 256, seed: 109)]
fn fuzz_min_max_clamp(x: i64, y: i64, z: i64) {
    let (a, b, c) = (f(x), f(y), f(z));
    let (lo, hi) = (a.min(b), a.max(b));
    assert!(lo <= hi && (lo == a || lo == b) && (hi == a || hi == b));
    let k = c.clamp(lo, hi);
    assert!(k >= lo && k <= hi);
    if c >= lo && c <= hi {
        assert_eq!(k, c);
    }
    let s = c.saturate();
    assert!(s >= ZERO && s <= ONE);
}

#[test]
#[fuzzer(runs: 256, seed: 110)]
fn fuzz_sqrt_is_integer_root(x: i64, sel: u8) {
    let a = scale(x, sel);
    if a >= 0 {
        let r: u128 = f(a).sqrt().raw.try_into().unwrap();
        let s: u128 = a.try_into().unwrap() * 0x100000000;
        assert!(r * r <= s && s < (r + 1) * (r + 1));
    }
}

#[test]
#[fuzzer(runs: 256, seed: 111)]
fn fuzz_lerp(x: i64, y: i64, t: u32) {
    let (a, b) = (f(x), f(y));
    assert_eq!(a.lerp(b, ZERO), a);
    assert_eq!(a.lerp(b, ONE), b);
    // t in [0, 1): the result stays between the end points
    let r = a.lerp(b, f(t.into()));
    assert!(r >= a.min(b) && r <= a.max(b));
}

#[test]
#[fuzzer(runs: 256, seed: 112)]
fn fuzz_smoothstep_and_step(x: i64, sel: u8) {
    let v = f(scale(x, sel) / 4);
    let s = v.smoothstep(NEG_ONE, TWO);
    assert!(s >= ZERO && s <= ONE);
    if v <= NEG_ONE {
        assert_eq!(s, ZERO);
    }
    if v >= TWO {
        assert_eq!(s, ONE);
    }
    assert_eq!(ONE.step(v) == ONE, v >= ONE);
}

#[test]
#[fuzzer(runs: 256, seed: 113)]
fn fuzz_move_towards(x: i64, y: i64, d: u32) {
    let (a, b) = (f(x / 4), f(y / 4));
    let step = f(d.into() * 0x10000);
    let m = a.move_towards(b, step);
    assert!(m.abs_diff_eq(b, (b - a).abs()));
    if (b - a).abs() <= step {
        assert_eq!(m, b);
    } else {
        assert!(m.abs_diff_eq(a, step) && !m.abs_diff_eq(a, step - EPSILON));
    }
}

#[test]
#[fuzzer(runs: 256, seed: 114)]
fn fuzz_abs_diff_eq(x: i64, y: i64, m: i64) {
    let d: i128 = x.into() - y.into();
    let expected = (if d < 0 {
        -d
    } else {
        d
    }) <= m.into();
    assert_eq!(f(x).abs_diff_eq(f(y), f(m)), expected);
    assert_eq!(f(y).abs_diff_eq(f(x), f(m)), expected);
}

#[test]
#[fuzzer(runs: 256, seed: 115)]
fn fuzz_int_round_trip(v: i32) {
    let a = FixedTrait::from_int(v);
    assert_eq!(a.to_int(), v);
    assert_eq!(a.to_int_trunc(), v);
    assert_eq!(a.to_int_round(), v);
    assert_eq!(a.floor(), a);
    assert_eq!(a.trunc(), a);
    assert_eq!(a.fract(), ZERO);
    let b: Fixed = v.into();
    assert_eq!(a, b);
}

#[test]
#[fuzzer(runs: 256, seed: 116)]
fn fuzz_powi_small_exponents(x: i64) {
    let a = f(x % 0x2000000000); // |a| < 32: a^4 fits
    assert_eq!(a.powi(0), ONE);
    assert_eq!(a.powi(1), a);
    assert_eq!(a.powi(2), a * a);
    assert_eq!(a.powi(4), (a * a) * (a * a));
    assert_eq!(a.powi(5), (a * a) * (a * a) * a);
    if a.powi(2).raw > 2 {
        assert_eq!(a.powi(-2), (a * a).recip());
    }
}

// exact; panics on i64 overflow
#[test]
fn test_add_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (4294967295, -13493037705, -9198070410), (-2147483648, 10737418240, 8589934592),
        (-3, -323966328, -323966331), (37359273344, 2147483648, 39506756992),
        (-30064771072, 2147483649, -27917287423),
        (-6442450944, 759070236955776737, 759070230513325793),
        (9223372036854775807, -4294967296, 9223372032559808511),
        (-274358740097498, 9223372032559808511, 9223097673819711013),
        (-478330528170494661, 6442450944, -478330521728043717),
        (-2147483649, 10737418240, 8589934591), (2147483647, -4294967296, -2147483649),
        (0, 4294967296, 4294967296), (4294967295, 4294967296, 8589934591),
        (2147483647, 10737418240, 12884901887),
        (-9223372032559808512, 199033079463936, -9223172999480344576),
        (3, -13493037705, -13493037702), (-3, -3, -6),
        (-4294967295, 9223372036854775806, 9223372032559808511),
        (2147483648, 37437668627, 39585152275), (-10737418240, 241, -10737417999), (-1, 1, 0),
        (4611686018427387904, -9223372036854775807, -4611686018427387903),
        (9223372036854775807, -199028784496640, 9223173008070279167),
        (-10737418240, 0, -10737418240), (-24855183368564, 3, -24855183368561),
        (1, -13493037705, -13493037704), (-6442450944, -4294967297, -10737418241),
        (3, 37359273344, 37359273347), (-9223372032559808512, -2, -9223372032559808514),
        (-6442450944, 10737418240, 4294967296), (4294967295, -3, 4294967292),
        (24649316121, 2147483648, 26796799769),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = (f(a) + f(b)).raw;
        assert!(got == want, "add({} {}) = {} expected {}", a, b, got, want);
    }
}

// exact; panics on i64 overflow
#[test]
fn test_sub_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (-2147483647, -302743759664, 300596276017),
        (4294967296, 9223372034707292159, -9223372030412324863),
        (3, -4611686018427387904, 4611686018427387907),
        (7211765186901912905, 2147483648, 7211765184754429257), (-6442450944, 2, -6442450946),
        (466908701094, -2147483649, 469056184743),
        (-2147483649, 4713042415780199964, -4713042417927683613), (-2, -4294967296, 4294967294),
        (2147483648, 10737418240, -8589934592),
        (759070236955776737, 4294967296333, 759065941988480404),
        (-9223372036854775808, -2147483647, -9223372034707292161),
        (-2147483649, -13493037705, 11345554056), (0, 9223372034707292160, -9223372034707292160),
        (-57862, -199028784496640, 199028784438778), (43, -302743759664, 302743759707),
        (-4294967296, -199028784496640, 199024489529344), (10737418240, 3, 10737418237),
        (-10737418240, 466908701094, -477646119334), (4294967295, -13493037705, 17788005000),
        (-1, -10737418240, 10737418239), (1352092485, 3, 1352092482), (-3, 3, -6),
        (-4294967296, -4294967296, 0), (-2147483648, 7211765186901912905, -7211765189049396553),
        (4294967296, -4294967296, 8589934592), (-199028784496640, -3, -199028784496637),
        (0, 4294967296, -4294967296), (2147483647, -13493037705, 15640521352),
        (4294967295, 3, 4294967292), (37437668627, -1, 37437668628),
        (-274358740097498, 1, -274358740097499), (37437668627, 2147483648, 35290184979),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = (f(a) - f(b)).raw;
        assert!(got == want, "sub({} {}) = {} expected {}", a, b, got, want);
    }
}

// floor(a * b / 2^32), computed with Python big ints: (a * b) >> 32
#[test]
fn test_mul_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (4713042415780199964, 0, 0), (12345, -671031825505, -1928743),
        (-2147483647, 37359273344, -18679636664), (24649316121, 0, 0),
        (-98765, 759070236955776737, -17455213692258), (-2, -2147483649, 1),
        (-478330528170494661, -6442450944, 717495792255741991),
        (2147483648, 4611686018427387904, 2305843009213693952),
        (-4294967296, -13493037705, 13493037705), (-30064771072, -323966328, 2267764296),
        (-941484277, 4713042415780199964, -1033129014841084125),
        (759070236955776737, 37437668627, 6616539320854642133), (0, 2147483649, 0),
        (466908701094, -131892829986533, -14338155727047450),
        (-4294967295, 9223372032559808511, -9223372030412324865),
        (-2147483647, 10737418240, -5368709118),
        (759070236955776737, 37359273344, 6602684145263795172), (-2, -2, 0),
        (247580, -4294967296, -247580), (-4294967296, -3, 3),
        (-98765, -4942304596022257876, 113650856871655), (2147483647, -2, -1),
        (-302743759664, -671031825505, 47299707705988), (2147483648, 4294967296, 2147483648),
        (-2147483649, 241, -121), (759070236955776737, -10737418240, -1897675592389441843),
        (2147483649, 10737418240, 5368709122), (-4294967296, -4294967296, 4294967296),
        (-6442450944, -13493037705, 20239556557),
        (4611686018427387904, 4294967296, 4611686018427387904),
        (-2147483649, 4294967296, -2147483649), (-869751, -9223372032559808512, 1867776049461897),
        (9223372036854775807, -941484277, -2021822089706602496),
        (-941484277, -302743759664, 66363366712), (-2147483648, -30064771072, 15032385536),
        (-1, 4294967296, -1), (-11674931555, -131892829986533, 358521883070474),
        (208480453546914, -11674931555, -566708628487675), (43, 9223372032559808511, 92341796820),
        (-2, 759070236955776737, -353469624), (-24855183368564, 4294967295, -24855183362777),
        (9223372036854775807, -2147483648, -4611686018427387904),
        (-4294967297, -13493037705, 13493037708), (-4294967296, 10737418240, -10737418240),
        (-2147483649, 10737418240, -5368709123),
        (4294967296, 9223372032559808511, 9223372032559808511), (37437668627, 2, 17),
        (2147483649, -3, -2), (-2147483649, 2, -2), (-1, -4294967296, 1),
        (-2147483648, 247580, -123790), (2, 4294967296, 2), (6442450944, -3, -5),
        (2147483647, -4294967296, -2147483647), (37437668627, 2147483647, 18718834304),
        (-2, -2147483649, 1), (1352092485, -941484277, -296387313),
        (-6442450944, 4294967296, -6442450944), (4294967296333, -671031825505, -671031825557027),
        (-10737418240, -13493037705, 33732594262), (-4294967296, 3, -3), (-3, -4294967296, 3),
        (2147483649, 3, 1), (-4294967297, 12884901888, -12884901891),
        (2147483648, 10737418240, 5368709120), (-3, -3, 0),
        (9223372034707292159, 2147483647, 4611686015206162432), (-98765, 4294967296, -98765),
        (-98765, -2147483649, 49382), (2, 3, 0), (-671031825505, 1352092485, -211246565092),
        (-2147483649, -3, 1),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = (f(a) * f(b)).raw;
        assert!(got == want, "mul({} {}) = {} expected {}", a, b, got, want);
    }
}

// trunc(a * 2^32 / b) (toward zero), Python big ints
#[test]
fn test_div_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (24649316121, 6442450944, 16432877414), (2147483648, 466908701094, 19754123),
        (-9223372032559808512, 4611686018427387904, -8589934588), (-1, 2, -2147483648),
        (1, -24855183368564, 0), (-869751, 2147483648, -1739502),
        (466908701094, 13493037705, 148621655498), (-2, -9223372032559808512, 0),
        (-2, -4294967296, 2), (24649316121, 7211765186901912905, 14),
        (4294967295, 1352092485, 13643108200), (-2147483647, -3, 3074457344186602837),
        (-2147483649, -3, 3074457347049914368), (-4294967297, -13493037705, 1367130551),
        (-2147483649, -899305830393, 10256101), (4294967295, -2147483649, -8589934586),
        (-24855183368564, -4611686018427387904, 23148), (2147483649, -4294967297, -2147483648),
        (-2147483649, 3, -3074457347049914368), (2, 10737418240, 0), (-1, -3337189588997, 0),
        (43, 2147483647, 86), (6442450944, -274358740097498, -100853),
        (12884901888, -2147483649, -25769803764), (-941484277, 4294967297, -941484276),
        (-671031825505, 759070236955776737, -3796), (1352092485, 4713042415780199964, 1),
        (2, -199028784496640, 0), (4294967295, 4294967296, 4294967295),
        (2147483649, -13493037705, -683565275), (4294967297, 6442450944, 2863311531),
        (-57862, -4611686018427387904, 0), (2147483648, 241, 38271253264957575),
        (-4294967297, 37359273344, -493766136), (4294967297, 4294967296, 4294967297),
        (-2147483647, 10737418240, -858993458),
        (-9223372036854775807, -9223372036854775808, 4294967295), (1, -13493037705, 0),
        (-4294967297, -3, 6148914692668172970), (1, 199033079463936, 0),
        (247580, 1352092485, 786446), (24649316121, -869751, -121722201651346),
        (-2147483649, -4294967295, 2147483649), (-6442450944, -13493037705, 2050695826),
        (-4294967295, -13493037705, 1367130550), (43, -869751, -212340), (1, -671031825505, 0),
        (1, 3, 1431655765), (10737418240, 10737418240, 4294967296),
        (-671031825505, 247580, -11640923116241835), (4294967295, 10737418240, 1717986918),
        (-6442450944, 4294967297, -6442450942), (-2147483647, -4294967296, 2147483647),
        (-11674931555, -2147483647, 23349863120), (2, 3, 2863311530), (0, 12884901888, 0),
        (10737418240, -10737418240, -4294967296), (2147483649, 4294967296, 2147483649),
        (10737418240, -13493037705, -3417826377), (-4294967297, -869751, 21209224338925),
        (4713042415780199964, -4611686018427387904, -4389362796),
        (4713042415780199964, 4611686018427387904, 4389362796),
        (2147483648, -4942304596022257876, -1), (37437668627, 9223372034707292160, 17),
        (10737418240, 12345, 3735671136838710), (-4294967295, 3, -6148914689804861440),
        (6442450944, -30064771072, -920350134), (37359273344, -9223372036854775807, -17),
        (1, -941484277, -4), (6442450944, -4294967296, -6442450944),
        (-199028784496640, 9223372032559808511, -92680), (-4294967295, -4294967296, 4294967295),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = (f(a) / f(b)).raw;
        assert!(got == want, "div({} {}) = {} expected {}", a, b, got, want);
    }
}

// remainder of the truncated division: sign(a) * (|a| mod |b|)
#[test]
fn test_rem_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (10737418240, -899305830393, 10737418240), (2, -1, 0),
        (-2147483649, -4294967295, -2147483649),
        (9223372034707292159, -24855183368564, 11169567088783),
        (-199028784496640, -274358740097498, -199028784496640),
        (2147483648, 13493037705, 2147483648), (24649316121, -57862, 46259),
        (-9223372036854775808, -4294967297, -2147483649), (-98765, -9223372036854775807, -98765),
        (-2147483648, 10737418240, -2147483648), (10737418240, 3, 1),
        (-4942304596022257876, 43, -28), (6442450944, 3, 0), (6442450944, -30064771072, 6442450944),
        (-6442450944, -4611686018427387904, -6442450944), (-57862, -274358740097498, -57862),
        (-274358740097498, -4611686018427387904, -274358740097498),
        (37437668627, 12884901888, 11667864851), (-9223372036854775807, 13493037705, -7451081932),
        (37359273344, 1352092485, 852776249), (6442450944, -3, 0), (-4294967296, 4294967296, 0),
        (6442450944, 10737418240, 6442450944), (-30064771072, 37359273344, -30064771072),
        (-4942304596022257876, -4294967297, -4112077053), (2147483647, 10737418240, 2147483647),
        (-4294967295, -3, 0), (-3, 7211765186901912905, -3),
        (199033079463936, 4294967297, 4294920956), (-24855183368564, -98765, -61084),
        (4294967296, 24649316121, 4294967296), (-869751, -671031825505, -869751),
        (37359273344, 37359273344, 0), (-2147483649, 4294967296, -2147483649),
        (-4294967296, -9223372036854775807, -4294967296),
        (-2147483647, -3337189588997, -2147483647), (-2147483647, 7211765186901912905, -2147483647),
        (2147483648, -3, 2), (-274358740097498, -941484277, -806936928), (1, 199033079463936, 1),
        (-6442450944, 10737418240, -6442450944),
        (-9223372032559808512, -199028784496640, -179130201014272), (-941484277, 241, -184),
        (-4294967297, 4294967296, -1), (-98765, 4294967297, -98765), (-57862, 24649316121, -57862),
        (6442450944, 1352092485, 1034081004), (13493037705, 199033079463936, 13493037705),
        (10737418240, -3, 1), (-3337189588997, 4294967295, -782),
        (2147483648, 199033079463936, 2147483648), (-3, 4294967296, -3),
        (9223372034707292159, 37359273344, 13289952767),
        (199033079463936, -24855183368564, 191612515424), (2, -13493037705, 2),
        (24649316121, 13493037705, 11156278416),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = (f(a) % f(b)).raw;
        assert!(got == want, "rem({} {}) = {} expected {}", a, b, got, want);
    }
}

// n * 2^32 with a = n * b + r, 0 <= r < |b|
#[test]
fn test_div_euclid_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (-4294967297, -4942304596022257876, 4294967296), (-10737418240, -323966328, 146028888064),
        (10737418240, -4611686018427387904, 0), (-3, 4294967296333, -4294967296),
        (12345, 9223372034707292160, 0), (3, -4294967295, 0),
        (10737418240, -2147483648, -21474836480), (10737418240, -13493037705, 0),
        (-4294967297, -13493037705, 4294967296), (-2147483647, -131892829986533, 4294967296),
        (-3, 10737418240, -4294967296), (-2, 4294967296, -4294967296), (2147483647, 4294967296, 0),
        (-2147483648, -4294967296, 4294967296), (-6442450944, -4294967296, 8589934592),
        (24649316121, 466908701094, 0), (13493037705, 466908701094, 0),
        (-98765, 2147483648, -4294967296), (-941484277, 4294967297, -4294967296),
        (-199028784496640, 2147483647, -398061863960576), (37437668627, 37359273344, 4294967296),
        (247580, 3, 354446471069696), (-4294967296, 6442450944, -4294967296),
        (-4294967296, 10737418240, -4294967296), (4294967295, -10737418240, 0), (2, 3, 0),
        (-323966328, 9223372034707292159, -4294967296), (247580, -2147483649, 0),
        (-2147483649, 10737418240, -4294967296), (1, -13493037705, 0), (4294967296, 10737418240, 0),
        (208480453546914, -2147483649, -416959720062976),
        (-4611686018427387904, -9223372032559808512, 4294967296),
        (-4294967295, -13493037705, 4294967296), (4294967296, -13493037705, 0),
        (37359273344, -4942304596022257876, 0), (-1, -13493037705, 4294967296),
        (4294967296, -3, -6148914689804861440), (-199028784496640, 2147483648, -398057568993280),
        (3, -4611686018427387904, 0), (9223372034707292159, -4942304596022257876, -4294967296),
        (1, -274358740097498, 0), (-1, 7211765186901912905, -4294967296),
        (9223372036854775806, 199033079463936, 199028784496640),
        (6442450944, 43, 643491069941514240), (10737418240, -2147483647, -21474836480),
        (-9223372036854775807, 7211765186901912905, -8589934592),
        (-4942304596022257876, 37437668627, -566996757506949120),
        (-10737418240, 37359273344, -4294967296), (2147483648, -671031825505, 0),
        (-323966328, 1, -1391424783765209088), (2147483648, 9223372034707292160, 0),
        (-10737418240, -941484277, 51539607552), (3, -4294967296, 0),
        (-2147483649, -941484277, 12884901888), (6442450944, 10737418240, 0),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = f(a).div_euclid(f(b)).raw;
        assert!(got == want, "div_euclid({} {}) = {} expected {}", a, b, got, want);
    }
}

// a mod |b| (Python % with a positive modulus)
#[test]
fn test_rem_euclid_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (4294967296, 6442450944, 4294967296), (-131892829986533, 24649316121, 5660576938),
        (4294967295, 3, 0), (4294967295, 10737418240, 4294967295), (-3, -13493037705, 13493037702),
        (-2147483648, -13493037705, 11345554057),
        (9223372036854775806, -4611686018427387904, 4611686018427387902), (1, 2147483647, 1),
        (-2147483649, 9223372036854775807, 9223372034707292158),
        (-2147483648, 9223372036854775807, 9223372034707292159),
        (-9223372032559808512, 6442450944, 2147483648),
        (-24855183368564, 466908701094, 357886490512), (-1, -3, 2), (-2, 4294967296, 4294967294),
        (-2147483648, 10737418240, 8589934592), (247580, 9223372034707292160, 247580),
        (-2, -869751, 869749), (9223372032559808511, -11674931555, 11117164446),
        (-10737418240, 4294967297, 2147483651), (-4294967296, 4294967296, 0),
        (-11674931555, 12345, 6535), (-6442450944, -3, 0), (-2147483649, 10737418240, 8589934591),
        (-3337189588997, -30064771072, 30064771067),
        (-9223372036854775808, 9223372036854775806, 9223372036854775804),
        (-4942304596022257876, 2147483647, 1025697658), (-11674931555, 247580, 198505),
        (2147483647, -30064771072, 2147483647), (2147483648, -3, 2), (2147483647, -3, 1),
        (6442450944, -3, 0), (241, 9223372034707292159, 241),
        (9223372032559808511, -6442450944, 4294967295), (-323966328, 2147483647, 1823517319),
        (2, 208480453546914, 2), (1, -13493037705, 1), (0, -13493037705, 0),
        (2147483647, -13493037705, 2147483647), (-2, 1, 0), (-2147483649, -10737418240, 8589934591),
        (-2147483647, 247580, 25273), (199033079463936, 4294967296, 0),
        (4294967297, -11674931555, 4294967297), (-2147483649, 2147483649, 0),
        (-4294967297, 9223372034707292160, 9223372030412324863),
        (-2147483649, -4294967296, 2147483647), (-2147483649, -4294967295, 2147483646),
        (-6442450944, -4294967296, 2147483648), (-4294967295, 10737418240, 6442450945),
        (-1, -13493037705, 13493037704), (37437668627, 466908701094, 37437668627),
        (-2147483649, -13493037705, 11345554056), (247580, 466908701094, 247580),
        (-10737418240, -13493037705, 2755619465), (-4294967297, 4294967296, 4294967295),
        (-131892829986533, -9223372036854775808, 9223240144024789275),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = f(a).rem_euclid(f(b)).raw;
        assert!(got == want, "rem_euclid({} {}) = {} expected {}", a, b, got, want);
    }
}

// exact
#[test]
fn test_neg_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, -1), (-1, 1), (2, -2), (-2, 2), (3, -3), (-3, 3), (4294967296, -4294967296),
        (-4294967296, 4294967296), (2147483648, -2147483648), (-2147483648, 2147483648),
        (4294967297, -4294967297), (4294967295, -4294967295), (-4294967297, 4294967297),
        (-4294967295, 4294967295), (6442450944, -6442450944), (-6442450944, 6442450944),
        (10737418240, -10737418240), (-10737418240, 10737418240), (2147483649, -2147483649),
        (2147483647, -2147483647), (-2147483649, 2147483649), (-2147483647, 2147483647),
        (13493037705, -13493037705), (-11674931555, 11674931555), (12345, -12345), (-98765, 98765),
        (2147483647, -2147483647), (2147483648, -2147483648), (-2147483649, 2147483649),
        (4294967296333, -4294967296333), (-3337189588997, 3337189588997),
        (4611686018427387904, -4611686018427387904), (-4611686018427387904, 4611686018427387904),
        (9223372036854775807, -9223372036854775807), (9223372036854775806, -9223372036854775806),
        (-9223372036854775807, 9223372036854775807), (9223372032559808511, -9223372032559808511),
        (-9223372032559808512, 9223372032559808512), (9223372034707292159, -9223372034707292159),
        (9223372034707292160, -9223372034707292160), (12884901888, -12884901888),
        (-30064771072, 30064771072), (199033079463936, -199033079463936),
        (-199028784496640, 199028784496640), (-478330528170494661, 478330528170494661),
        (247580, -247580), (759070236955776737, -759070236955776737), (24649316121, -24649316121),
        (43, -43), (4713042415780199964, -4713042415780199964),
        (-4942304596022257876, 4942304596022257876), (241, -241), (-869751, 869751),
        (-323966328, 323966328), (-671031825505, 671031825505), (-24855183368564, 24855183368564),
        (37437668627, -37437668627), (7211765186901912905, -7211765186901912905),
        (-941484277, 941484277), (-131892829986533, 131892829986533), (-302743759664, 302743759664),
        (-57862, 57862), (-899305830393, 899305830393),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = (-f(a)).raw;
        assert!(got == want, "neg({}) = {} expected {}", a, got, want);
    }
}

// exact; MIN overflows
#[test]
fn test_abs_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, 1), (-1, 1), (2, 2), (-2, 2), (3, 3), (-3, 3), (4294967296, 4294967296),
        (-4294967296, 4294967296), (2147483648, 2147483648), (-2147483648, 2147483648),
        (4294967297, 4294967297), (4294967295, 4294967295), (-4294967297, 4294967297),
        (-4294967295, 4294967295), (6442450944, 6442450944), (-6442450944, 6442450944),
        (10737418240, 10737418240), (-10737418240, 10737418240), (2147483649, 2147483649),
        (2147483647, 2147483647), (-2147483649, 2147483649), (-2147483647, 2147483647),
        (13493037705, 13493037705), (-11674931555, 11674931555), (12345, 12345), (-98765, 98765),
        (2147483647, 2147483647), (2147483648, 2147483648), (-2147483649, 2147483649),
        (4294967296333, 4294967296333), (-3337189588997, 3337189588997),
        (4611686018427387904, 4611686018427387904), (-4611686018427387904, 4611686018427387904),
        (9223372036854775807, 9223372036854775807), (9223372036854775806, 9223372036854775806),
        (-9223372036854775807, 9223372036854775807), (9223372032559808511, 9223372032559808511),
        (-9223372032559808512, 9223372032559808512), (9223372034707292159, 9223372034707292159),
        (9223372034707292160, 9223372034707292160), (12884901888, 12884901888),
        (-30064771072, 30064771072), (199033079463936, 199033079463936),
        (-199028784496640, 199028784496640), (-478330528170494661, 478330528170494661),
        (247580, 247580), (759070236955776737, 759070236955776737), (24649316121, 24649316121),
        (43, 43), (4713042415780199964, 4713042415780199964),
        (-4942304596022257876, 4942304596022257876), (241, 241), (-869751, 869751),
        (-323966328, 323966328), (-671031825505, 671031825505), (-24855183368564, 24855183368564),
        (37437668627, 37437668627), (7211765186901912905, 7211765186901912905),
        (-941484277, 941484277), (-131892829986533, 131892829986533), (-302743759664, 302743759664),
        (-57862, 57862), (-899305830393, 899305830393),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).abs().raw;
        assert!(got == want, "abs({}) = {} expected {}", a, got, want);
    }
}

// -1 below zero, +1 otherwise (signum(0) = +1)
#[test]
fn test_signum_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 4294967296), (1, 4294967296), (-1, -4294967296), (2, 4294967296), (-2, -4294967296),
        (3, 4294967296), (-3, -4294967296), (4294967296, 4294967296), (-4294967296, -4294967296),
        (2147483648, 4294967296), (-2147483648, -4294967296), (4294967297, 4294967296),
        (4294967295, 4294967296), (-4294967297, -4294967296), (-4294967295, -4294967296),
        (6442450944, 4294967296), (-6442450944, -4294967296), (10737418240, 4294967296),
        (-10737418240, -4294967296), (2147483649, 4294967296), (2147483647, 4294967296),
        (-2147483649, -4294967296), (-2147483647, -4294967296), (13493037705, 4294967296),
        (-11674931555, -4294967296), (12345, 4294967296), (-98765, -4294967296),
        (2147483647, 4294967296), (2147483648, 4294967296), (-2147483649, -4294967296),
        (4294967296333, 4294967296), (-3337189588997, -4294967296),
        (4611686018427387904, 4294967296), (-4611686018427387904, -4294967296),
        (9223372036854775807, 4294967296), (-9223372036854775808, -4294967296),
        (9223372036854775806, 4294967296), (-9223372036854775807, -4294967296),
        (9223372032559808511, 4294967296), (-9223372032559808512, -4294967296),
        (9223372034707292159, 4294967296), (9223372034707292160, 4294967296),
        (12884901888, 4294967296), (-30064771072, -4294967296), (199033079463936, 4294967296),
        (-199028784496640, -4294967296), (-478330528170494661, -4294967296), (247580, 4294967296),
        (759070236955776737, 4294967296), (24649316121, 4294967296), (43, 4294967296),
        (4713042415780199964, 4294967296), (-4942304596022257876, -4294967296), (241, 4294967296),
        (-869751, -4294967296), (-323966328, -4294967296), (-671031825505, -4294967296),
        (-24855183368564, -4294967296), (37437668627, 4294967296),
        (7211765186901912905, 4294967296), (-941484277, -4294967296),
        (-131892829986533, -4294967296), (-302743759664, -4294967296), (-57862, -4294967296),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).signum().raw;
        assert!(got == want, "signum({}) = {} expected {}", a, got, want);
    }
}

// |a| with the sign of b (zero is positive)
#[test]
fn test_copysign_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (-4294967296, 10737418240, 4294967296), (4294967297, 2147483648, 4294967297),
        (1352092485, -3337189588997, -1352092485), (-4294967296, 0, 4294967296),
        (4713042415780199964, -131892829986533, -4713042415780199964),
        (-4294967297, -98765, -4294967297),
        (9223372034707292160, 7211765186901912905, 9223372034707292160),
        (9223372036854775806, -2147483648, -9223372036854775806),
        (-4294967297, -13493037705, -4294967297), (-899305830393, -131892829986533, -899305830393),
        (-4294967297, 13493037705, 4294967297), (2147483647, -199028784496640, -2147483647),
        (24649316121, 9223372036854775807, 24649316121), (-2, -13493037705, -2),
        (-3, 2147483648, 3), (-478330528170494661, -4294967296, -478330528170494661),
        (9223372036854775807, 4294967295, 9223372036854775807),
        (37359273344, 4294967296333, 37359273344), (-2, 4294967296, 2),
        (-323966328, 9223372034707292159, 323966328),
        (-4942304596022257876, -9223372032559808512, -4942304596022257876),
        (-478330528170494661, -2147483649, -478330528170494661),
        (4294967297, 13493037705, 4294967297), (4294967297, 3, 4294967297),
        (3, 4713042415780199964, 3), (-671031825505, 7211765186901912905, 671031825505),
        (2147483649, 3, 2147483649), (7211765186901912905, 6442450944, 7211765186901912905),
        (1, -13493037705, -1), (12884901888, 4713042415780199964, 12884901888), (3, 3, 3),
        (1352092485, 43, 1352092485), (9223372034707292160, 199033079463936, 9223372034707292160),
        (-2, 199033079463936, 2), (2147483648, 2147483648, 2147483648),
        (9223372036854775807, -6442450944, -9223372036854775807),
        (2147483648, -302743759664, -2147483648),
        (-4942304596022257876, 4294967297, 4942304596022257876),
        (-4942304596022257876, -2147483647, -4942304596022257876),
        (-899305830393, 9223372034707292160, 899305830393),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = f(a).copysign(f(b)).raw;
        assert!(got == want, "copysign({} {}) = {} expected {}", a, b, got, want);
    }
}

// (a >> 32) << 32
#[test]
fn test_floor_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, 0), (-1, -4294967296), (2, 0), (-2, -4294967296), (3, 0), (-3, -4294967296),
        (4294967296, 4294967296), (-4294967296, -4294967296), (2147483648, 0),
        (-2147483648, -4294967296), (4294967297, 4294967296), (4294967295, 0),
        (-4294967297, -8589934592), (-4294967295, -4294967296), (6442450944, 4294967296),
        (-6442450944, -8589934592), (10737418240, 8589934592), (-10737418240, -12884901888),
        (2147483649, 0), (2147483647, 0), (-2147483649, -4294967296), (-2147483647, -4294967296),
        (13493037705, 12884901888), (-11674931555, -12884901888), (12345, 0), (-98765, -4294967296),
        (2147483647, 0), (2147483648, 0), (-2147483649, -4294967296),
        (4294967296333, 4294967296000), (-3337189588997, -3341484556288),
        (4611686018427387904, 4611686018427387904), (-4611686018427387904, -4611686018427387904),
        (9223372036854775807, 9223372032559808512), (-9223372036854775808, -9223372036854775808),
        (9223372036854775806, 9223372032559808512), (-9223372036854775807, -9223372036854775808),
        (9223372032559808511, 9223372028264841216), (-9223372032559808512, -9223372032559808512),
        (9223372034707292159, 9223372032559808512), (9223372034707292160, 9223372032559808512),
        (12884901888, 12884901888), (-30064771072, -30064771072),
        (199033079463936, 199033079463936), (-199028784496640, -199028784496640),
        (-478330528170494661, -478330529230356480), (247580, 0),
        (759070236955776737, 759070233309741056), (24649316121, 21474836480), (43, 0),
        (4713042415780199964, 4713042414774779904), (-4942304596022257876, -4942304599349395456),
        (241, 0), (-869751, -4294967296), (-323966328, -4294967296), (-671031825505, -674309865472),
        (-24855183368564, -24859270709248), (37437668627, 34359738368),
        (7211765186901912905, 7211765185411809280), (-941484277, -4294967296),
        (-131892829986533, -131894150692864), (-302743759664, -304942678016), (-57862, -4294967296),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).floor().raw;
        assert!(got == want, "floor({}) = {} expected {}", a, got, want);
    }
}

// -floor(-a)
#[test]
fn test_ceil_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, 4294967296), (-1, 0), (2, 4294967296), (-2, 0), (3, 4294967296), (-3, 0),
        (4294967296, 4294967296), (-4294967296, -4294967296), (2147483648, 4294967296),
        (-2147483648, 0), (4294967297, 8589934592), (4294967295, 4294967296),
        (-4294967297, -4294967296), (-4294967295, 0), (6442450944, 8589934592),
        (-6442450944, -4294967296), (10737418240, 12884901888), (-10737418240, -8589934592),
        (2147483649, 4294967296), (2147483647, 4294967296), (-2147483649, 0), (-2147483647, 0),
        (13493037705, 17179869184), (-11674931555, -8589934592), (12345, 4294967296), (-98765, 0),
        (2147483647, 4294967296), (2147483648, 4294967296), (-2147483649, 0),
        (4294967296333, 4299262263296), (-3337189588997, -3337189588992),
        (4611686018427387904, 4611686018427387904), (-4611686018427387904, -4611686018427387904),
        (-9223372036854775808, -9223372036854775808), (-9223372036854775807, -9223372032559808512),
        (9223372032559808511, 9223372032559808512), (-9223372032559808512, -9223372032559808512),
        (12884901888, 12884901888), (-30064771072, -30064771072),
        (199033079463936, 199033079463936), (-199028784496640, -199028784496640),
        (-478330528170494661, -478330524935389184), (247580, 4294967296),
        (759070236955776737, 759070237604708352), (24649316121, 25769803776), (43, 4294967296),
        (4713042415780199964, 4713042419069747200), (-4942304596022257876, -4942304595054428160),
        (241, 4294967296), (-869751, 0), (-323966328, 0), (-671031825505, -670014898176),
        (-24855183368564, -24854975741952), (37437668627, 38654705664),
        (7211765186901912905, 7211765189706776576), (-941484277, 0),
        (-131892829986533, -131889855725568), (-302743759664, -300647710720), (-57862, 0),
        (-899305830393, -897648164864), (37359273344, 38654705664),
        (-274358740097498, -274358215901184), (1352092485, 4294967296),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).ceil().raw;
        assert!(got == want, "ceil({}) = {} expected {}", a, got, want);
    }
}

// half away from zero: sign(a) * floor(|a| + 1/2)
#[test]
fn test_round_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, 0), (-1, 0), (2, 0), (-2, 0), (3, 0), (-3, 0), (4294967296, 4294967296),
        (-4294967296, -4294967296), (2147483648, 4294967296), (-2147483648, -4294967296),
        (4294967297, 4294967296), (4294967295, 4294967296), (-4294967297, -4294967296),
        (-4294967295, -4294967296), (6442450944, 8589934592), (-6442450944, -8589934592),
        (10737418240, 12884901888), (-10737418240, -12884901888), (2147483649, 4294967296),
        (2147483647, 0), (-2147483649, -4294967296), (-2147483647, 0), (13493037705, 12884901888),
        (-11674931555, -12884901888), (12345, 0), (-98765, 0), (2147483647, 0),
        (2147483648, 4294967296), (-2147483649, -4294967296), (4294967296333, 4294967296000),
        (-3337189588997, -3337189588992), (4611686018427387904, 4611686018427387904),
        (-4611686018427387904, -4611686018427387904), (-9223372036854775808, -9223372036854775808),
        (-9223372036854775807, -9223372036854775808), (9223372032559808511, 9223372032559808512),
        (-9223372032559808512, -9223372032559808512), (9223372034707292159, 9223372032559808512),
        (12884901888, 12884901888), (-30064771072, -30064771072),
        (199033079463936, 199033079463936), (-199028784496640, -199028784496640),
        (-478330528170494661, -478330529230356480), (247580, 0),
        (759070236955776737, 759070237604708352), (24649316121, 25769803776), (43, 0),
        (4713042415780199964, 4713042414774779904), (-4942304596022257876, -4942304595054428160),
        (241, 0), (-869751, 0), (-323966328, 0), (-671031825505, -670014898176),
        (-24855183368564, -24854975741952), (37437668627, 38654705664),
        (7211765186901912905, 7211765185411809280), (-941484277, 0),
        (-131892829986533, -131894150692864), (-302743759664, -300647710720), (-57862, 0),
        (-899305830393, -897648164864), (37359273344, 38654705664),
        (-274358740097498, -274358215901184),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).round().raw;
        assert!(got == want, "round({}) = {} expected {}", a, got, want);
    }
}

// toward zero
#[test]
fn test_trunc_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, 0), (-1, 0), (2, 0), (-2, 0), (3, 0), (-3, 0), (4294967296, 4294967296),
        (-4294967296, -4294967296), (2147483648, 0), (-2147483648, 0), (4294967297, 4294967296),
        (4294967295, 0), (-4294967297, -4294967296), (-4294967295, 0), (6442450944, 4294967296),
        (-6442450944, -4294967296), (10737418240, 8589934592), (-10737418240, -8589934592),
        (2147483649, 0), (2147483647, 0), (-2147483649, 0), (-2147483647, 0),
        (13493037705, 12884901888), (-11674931555, -8589934592), (12345, 0), (-98765, 0),
        (2147483647, 0), (2147483648, 0), (-2147483649, 0), (4294967296333, 4294967296000),
        (-3337189588997, -3337189588992), (4611686018427387904, 4611686018427387904),
        (-4611686018427387904, -4611686018427387904), (9223372036854775807, 9223372032559808512),
        (-9223372036854775808, -9223372036854775808), (9223372036854775806, 9223372032559808512),
        (-9223372036854775807, -9223372032559808512), (9223372032559808511, 9223372028264841216),
        (-9223372032559808512, -9223372032559808512), (9223372034707292159, 9223372032559808512),
        (9223372034707292160, 9223372032559808512), (12884901888, 12884901888),
        (-30064771072, -30064771072), (199033079463936, 199033079463936),
        (-199028784496640, -199028784496640), (-478330528170494661, -478330524935389184),
        (247580, 0), (759070236955776737, 759070233309741056), (24649316121, 21474836480), (43, 0),
        (4713042415780199964, 4713042414774779904), (-4942304596022257876, -4942304595054428160),
        (241, 0), (-869751, 0), (-323966328, 0), (-671031825505, -670014898176),
        (-24855183368564, -24854975741952), (37437668627, 34359738368),
        (7211765186901912905, 7211765185411809280), (-941484277, 0),
        (-131892829986533, -131889855725568), (-302743759664, -300647710720), (-57862, 0),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).trunc().raw;
        assert!(got == want, "trunc({}) = {} expected {}", a, got, want);
    }
}

// a - trunc(a)
#[test]
fn test_fract_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, 1), (-1, -1), (2, 2), (-2, -2), (3, 3), (-3, -3), (4294967296, 0),
        (-4294967296, 0), (2147483648, 2147483648), (-2147483648, -2147483648), (4294967297, 1),
        (4294967295, 4294967295), (-4294967297, -1), (-4294967295, -4294967295),
        (6442450944, 2147483648), (-6442450944, -2147483648), (10737418240, 2147483648),
        (-10737418240, -2147483648), (2147483649, 2147483649), (2147483647, 2147483647),
        (-2147483649, -2147483649), (-2147483647, -2147483647), (13493037705, 608135817),
        (-11674931555, -3084996963), (12345, 12345), (-98765, -98765), (2147483647, 2147483647),
        (2147483648, 2147483648), (-2147483649, -2147483649), (4294967296333, 333),
        (-3337189588997, -5), (4611686018427387904, 0), (-4611686018427387904, 0),
        (9223372036854775807, 4294967295), (-9223372036854775808, 0),
        (9223372036854775806, 4294967294), (-9223372036854775807, -4294967295),
        (9223372032559808511, 4294967295), (-9223372032559808512, 0),
        (9223372034707292159, 2147483647), (9223372034707292160, 2147483648), (12884901888, 0),
        (-30064771072, 0), (199033079463936, 0), (-199028784496640, 0),
        (-478330528170494661, -3235105477), (247580, 247580), (759070236955776737, 3646035681),
        (24649316121, 3174479641), (43, 43), (4713042415780199964, 1005420060),
        (-4942304596022257876, -967829716), (241, 241), (-869751, -869751),
        (-323966328, -323966328), (-671031825505, -1016927329), (-24855183368564, -207626612),
        (37437668627, 3077930259), (7211765186901912905, 1490103625), (-941484277, -941484277),
        (-131892829986533, -2974260965), (-302743759664, -2096048944), (-57862, -57862),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).fract().raw;
        assert!(got == want, "fract({}) = {} expected {}", a, got, want);
    }
}

// a - floor(a)
#[test]
fn test_fract_gl_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, 1), (-1, 4294967295), (2, 2), (-2, 4294967294), (3, 3), (-3, 4294967293),
        (4294967296, 0), (-4294967296, 0), (2147483648, 2147483648), (-2147483648, 2147483648),
        (4294967297, 1), (4294967295, 4294967295), (-4294967297, 4294967295), (-4294967295, 1),
        (6442450944, 2147483648), (-6442450944, 2147483648), (10737418240, 2147483648),
        (-10737418240, 2147483648), (2147483649, 2147483649), (2147483647, 2147483647),
        (-2147483649, 2147483647), (-2147483647, 2147483649), (13493037705, 608135817),
        (-11674931555, 1209970333), (12345, 12345), (-98765, 4294868531), (2147483647, 2147483647),
        (2147483648, 2147483648), (-2147483649, 2147483647), (4294967296333, 333),
        (-3337189588997, 4294967291), (4611686018427387904, 0), (-4611686018427387904, 0),
        (9223372036854775807, 4294967295), (-9223372036854775808, 0),
        (9223372036854775806, 4294967294), (-9223372036854775807, 1),
        (9223372032559808511, 4294967295), (-9223372032559808512, 0),
        (9223372034707292159, 2147483647), (9223372034707292160, 2147483648), (12884901888, 0),
        (-30064771072, 0), (199033079463936, 0), (-199028784496640, 0),
        (-478330528170494661, 1059861819), (247580, 247580), (759070236955776737, 3646035681),
        (24649316121, 3174479641), (43, 43), (4713042415780199964, 1005420060),
        (-4942304596022257876, 3327137580), (241, 241), (-869751, 4294097545),
        (-323966328, 3971000968), (-671031825505, 3278039967), (-24855183368564, 4087340684),
        (37437668627, 3077930259), (7211765186901912905, 1490103625), (-941484277, 3353483019),
        (-131892829986533, 1320706331), (-302743759664, 2198918352), (-57862, 4294909434),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).fract_gl().raw;
        assert!(got == want, "fract_gl({}) = {} expected {}", a, got, want);
    }
}

// floor(a / 2^32)
#[test]
fn test_to_int_table() {
    let cases: Span<(i64, i32)> = array![
        (0, 0), (1, 0), (-1, -1), (2, 0), (-2, -1), (3, 0), (-3, -1), (4294967296, 1),
        (-4294967296, -1), (2147483648, 0), (-2147483648, -1), (4294967297, 1), (4294967295, 0),
        (-4294967297, -2), (-4294967295, -1), (6442450944, 1), (-6442450944, -2), (10737418240, 2),
        (-10737418240, -3), (2147483649, 0), (2147483647, 0), (-2147483649, -1), (-2147483647, -1),
        (13493037705, 3), (-11674931555, -3), (12345, 0), (-98765, -1), (2147483647, 0),
        (2147483648, 0), (-2147483649, -1), (4294967296333, 1000), (-3337189588997, -778),
        (4611686018427387904, 1073741824), (-4611686018427387904, -1073741824),
        (9223372036854775807, 2147483647), (-9223372036854775808, -2147483648),
        (9223372036854775806, 2147483647), (-9223372036854775807, -2147483648),
        (9223372032559808511, 2147483646), (-9223372032559808512, -2147483647),
        (9223372034707292159, 2147483647), (9223372034707292160, 2147483647), (12884901888, 3),
        (-30064771072, -7), (199033079463936, 46341), (-199028784496640, -46340),
        (-478330528170494661, -111370005), (247580, 0), (759070236955776737, 176734811),
        (24649316121, 5), (43, 0), (4713042415780199964, 1097340699),
        (-4942304596022257876, -1150719961), (241, 0), (-869751, -1), (-323966328, -1),
        (-671031825505, -157), (-24855183368564, -5788), (37437668627, 8),
        (7211765186901912905, 1679119930), (-941484277, -1), (-131892829986533, -30709),
        (-302743759664, -71), (-57862, -1),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).to_int();
        assert!(got == want, "to_int({}) = {} expected {}", a, got, want);
    }
}

// trunc(a / 2^32)
#[test]
fn test_to_int_trunc_table() {
    let cases: Span<(i64, i32)> = array![
        (0, 0), (1, 0), (-1, 0), (2, 0), (-2, 0), (3, 0), (-3, 0), (4294967296, 1),
        (-4294967296, -1), (2147483648, 0), (-2147483648, 0), (4294967297, 1), (4294967295, 0),
        (-4294967297, -1), (-4294967295, 0), (6442450944, 1), (-6442450944, -1), (10737418240, 2),
        (-10737418240, -2), (2147483649, 0), (2147483647, 0), (-2147483649, 0), (-2147483647, 0),
        (13493037705, 3), (-11674931555, -2), (12345, 0), (-98765, 0), (2147483647, 0),
        (2147483648, 0), (-2147483649, 0), (4294967296333, 1000), (-3337189588997, -777),
        (4611686018427387904, 1073741824), (-4611686018427387904, -1073741824),
        (9223372036854775807, 2147483647), (-9223372036854775808, -2147483648),
        (9223372036854775806, 2147483647), (-9223372036854775807, -2147483647),
        (9223372032559808511, 2147483646), (-9223372032559808512, -2147483647),
        (9223372034707292159, 2147483647), (9223372034707292160, 2147483647), (12884901888, 3),
        (-30064771072, -7), (199033079463936, 46341), (-199028784496640, -46340),
        (-478330528170494661, -111370004), (247580, 0), (759070236955776737, 176734811),
        (24649316121, 5), (43, 0), (4713042415780199964, 1097340699),
        (-4942304596022257876, -1150719960), (241, 0), (-869751, 0), (-323966328, 0),
        (-671031825505, -156), (-24855183368564, -5787), (37437668627, 8),
        (7211765186901912905, 1679119930), (-941484277, 0), (-131892829986533, -30708),
        (-302743759664, -70), (-57862, 0),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).to_int_trunc();
        assert!(got == want, "to_int_trunc({}) = {} expected {}", a, got, want);
    }
}

// round half away from zero
#[test]
fn test_to_int_round_table() {
    let cases: Span<(i64, i32)> = array![
        (0, 0), (1, 0), (-1, 0), (2, 0), (-2, 0), (3, 0), (-3, 0), (4294967296, 1),
        (-4294967296, -1), (2147483648, 1), (-2147483648, -1), (4294967297, 1), (4294967295, 1),
        (-4294967297, -1), (-4294967295, -1), (6442450944, 2), (-6442450944, -2), (10737418240, 3),
        (-10737418240, -3), (2147483649, 1), (2147483647, 0), (-2147483649, -1), (-2147483647, 0),
        (13493037705, 3), (-11674931555, -3), (12345, 0), (-98765, 0), (2147483647, 0),
        (2147483648, 1), (-2147483649, -1), (4294967296333, 1000), (-3337189588997, -777),
        (4611686018427387904, 1073741824), (-4611686018427387904, -1073741824),
        (-9223372036854775808, -2147483648), (-9223372036854775807, -2147483648),
        (9223372032559808511, 2147483647), (-9223372032559808512, -2147483647),
        (9223372034707292159, 2147483647), (12884901888, 3), (-30064771072, -7),
        (199033079463936, 46341), (-199028784496640, -46340), (-478330528170494661, -111370005),
        (247580, 0), (759070236955776737, 176734812), (24649316121, 6), (43, 0),
        (4713042415780199964, 1097340699), (-4942304596022257876, -1150719960), (241, 0),
        (-869751, 0), (-323966328, 0), (-671031825505, -156), (-24855183368564, -5787),
        (37437668627, 9), (7211765186901912905, 1679119930), (-941484277, 0),
        (-131892829986533, -30709), (-302743759664, -70), (-57862, 0), (-899305830393, -209),
        (37359273344, 9), (-274358740097498, -63879),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).to_int_round();
        assert!(got == want, "to_int_round({}) = {} expected {}", a, got, want);
    }
}

// trunc(2^64 / a) (toward zero)
#[test]
fn test_recip_table() {
    let cases: Span<(i64, i64)> = array![
        (-2, -9223372036854775808), (3, 6148914691236517205), (-3, -6148914691236517205),
        (4294967296, 4294967296), (-4294967296, -4294967296), (2147483648, 8589934592),
        (-2147483648, -8589934592), (4294967297, 4294967295), (4294967295, 4294967297),
        (-4294967297, -4294967295), (-4294967295, -4294967297), (6442450944, 2863311530),
        (-6442450944, -2863311530), (10737418240, 1717986918), (-10737418240, -1717986918),
        (2147483649, 8589934588), (2147483647, 8589934596), (-2147483649, -8589934588),
        (-2147483647, -8589934596), (13493037705, 1367130551), (-11674931555, -1580030168),
        (12345, 1494268454735484), (-98765, -186774100883000), (2147483647, 8589934596),
        (2147483648, 8589934592), (-2147483649, -8589934588), (4294967296333, 4294967),
        (-3337189588997, -5527628), (4611686018427387904, 4), (-4611686018427387904, -4),
        (9223372036854775807, 2), (-9223372036854775808, -2), (9223372036854775806, 2),
        (-9223372036854775807, -2), (9223372032559808511, 2), (-9223372032559808512, -2),
        (9223372034707292159, 2), (9223372034707292160, 2), (12884901888, 1431655765),
        (-30064771072, -613566756), (199033079463936, 92681), (-199028784496640, -92683),
        (-478330528170494661, -38), (247580, 74508215824014), (759070236955776737, 24),
        (24649316121, 748367377), (43, 428994048225803525), (4713042415780199964, 3),
        (-4942304596022257876, -3), (241, 76542506529915151), (-869751, -21209224333987),
        (-323966328, -56940312863), (-671031825505, -27490118), (-24855183368564, -742168),
        (37437668627, 492732179), (7211765186901912905, 2), (-941484277, -19593257714),
        (-131892829986533, -139861), (-302743759664, -60931872), (-57862, -318805849671797),
        (-899305830393, -20512203), (37359273344, 493766136), (-274358740097498, -67235),
        (1352092485, 13643108203),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).recip().raw;
        assert!(got == want, "recip({}) = {} expected {}", a, got, want);
    }
}

// isqrt(a * 2^32) (floor)
#[test]
fn test_sqrt_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, 65536), (2, 92681), (3, 113511), (4294967296, 4294967296),
        (2147483648, 3037000499), (4294967297, 4294967296), (4294967295, 4294967295),
        (6442450944, 5260239168), (10737418240, 6790939565), (2147483649, 3037000500),
        (2147483647, 3037000499), (13493037705, 7612631323), (12345, 7281577),
        (2147483647, 3037000499), (2147483648, 3037000499), (4294967296333, 135818791318),
        (4611686018427387904, 140737488355328), (9223372036854775807, 199032864766430),
        (9223372036854775806, 199032864766430), (9223372032559808511, 199032864720089),
        (9223372034707292159, 199032864743259), (9223372034707292160, 199032864743259),
        (12884901888, 7439101573), (199033079463936, 924575884997), (247580, 32609017),
        (759070236955776737, 57098002093698), (24649316121, 10289217978), (43, 429748),
        (4713042415780199964, 142275658636454), (241, 1017392), (37437668627, 12680440149),
        (7211765186901912905, 175995157956618), (37359273344, 12667156634),
        (1352092485, 2409811819), (208480453546914, 946264619352), (466908701094, 44781219293),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).sqrt().raw;
        assert!(got == want, "sqrt({}) = {} expected {}", a, got, want);
    }
}

//
#[test]
fn test_min_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (-3, -3, -3), (-2, 4294967295, -2), (466908701094, 3, 3), (759070236955776737, -2, -2),
        (2147483649, -13493037705, -13493037705),
        (-4942304596022257876, 4294967297, -4942304596022257876),
        (-4294967297, 10737418240, -4294967297), (12884901888, -11674931555, -11674931555),
        (3, -3337189588997, -3337189588997),
        (-3337189588997, -9223372032559808512, -9223372032559808512),
        (1352092485, -131892829986533, -131892829986533),
        (9223372036854775806, -3337189588997, -3337189588997),
        (-4294967295, 9223372036854775806, -4294967295),
        (-274358740097498, 4294967297, -274358740097498), (1, 4294967296, 1),
        (0, -24855183368564, -24855183368564), (-2147483647, 10737418240, -2147483647),
        (-57862, -2, -57862), (-2147483647, 9223372032559808511, -2147483647),
        (1352092485, -4294967295, -4294967295), (2147483648, 241, 241),
        (9223372034707292160, -10737418240, -10737418240), (10737418240, 3, 3),
        (-2147483648, -869751, -2147483648),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = f(a).min(f(b)).raw;
        assert!(got == want, "min({} {}) = {} expected {}", a, b, got, want);
    }
}

//
#[test]
fn test_max_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (24649316121, 2, 24649316121), (4294967297, -57862, 4294967297),
        (-131892829986533, -478330528170494661, -131892829986533),
        (-9223372036854775808, -9223372036854775808, -9223372036854775808),
        (7211765186901912905, -9223372036854775807, 7211765186901912905),
        (-478330528170494661, 9223372034707292159, 9223372034707292159),
        (4294967297, 10737418240, 10737418240), (-4294967295, 37359273344, 37359273344),
        (6442450944, 10737418240, 10737418240), (4294967295, 4294967296, 4294967296),
        (-9223372036854775807, -4611686018427387904, -4611686018427387904), (-302743759664, 2, 2),
        (43, -4294967296, 43), (1, 10737418240, 10737418240), (-4294967297, -2, -2),
        (-4294967295, 3, 3), (2147483649, 10737418240, 10737418240), (2147483647, -3, 2147483647),
        (10737418240, 4294967296, 10737418240), (2147483649, -2, 2147483649),
        (-4611686018427387904, -131892829986533, -131892829986533),
        (-3337189588997, -4294967296, -4294967296), (3, -13493037705, 3),
        (-4294967297, 10737418240, 10737418240),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = f(a).max(f(b)).raw;
        assert!(got == want, "max({} {}) = {} expected {}", a, b, got, want);
    }
}

// 0 if b < a (a is the edge) else 1
#[test]
fn test_step_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (37437668627, 2147483647, 0), (-2, 2147483647, 4294967296),
        (12345, 9223372036854775807, 4294967296), (-6442450944, -3, 4294967296),
        (6442450944, -199028784496640, 0), (-941484277, 759070236955776737, 4294967296),
        (6442450944, -4294967296, 0), (466908701094, 10737418240, 0),
        (-9223372036854775807, -199028784496640, 4294967296), (-1, -3, 0), (1, -4294967296, 0),
        (-98765, -302743759664, 0), (-4294967295, 9223372036854775806, 4294967296),
        (-2147483647, -4294967296, 0), (-2147483647, 208480453546914, 4294967296),
        (-2147483648, 10737418240, 4294967296), (-4294967297, -3337189588997, 0),
        (241, -4294967297, 0), (2147483649, -13493037705, 0),
        (4294967296333, -4611686018427387904, 0), (1, -10737418240, 0),
        (2147483648, 10737418240, 4294967296), (-3, 12884901888, 4294967296),
        (6442450944, 4611686018427387904, 4294967296),
    ]
        .span();
    for case in cases {
        let (a, b, want) = *case;
        let got = f(a).step(f(b)).raw;
        assert!(got == want, "step({} {}) = {} expected {}", a, b, got, want);
    }
}

// min <= max precondition respected by the table
#[test]
fn test_clamp_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (0, 0, 4294967296, 0), (1, -941484277, 2147483647, 1),
        (-4294967296, 4294967296, 8589934592, 4294967296),
        (9223372036854775807, -11674931555, -2147483649, -2147483649),
        (-10737418240, -2147483647, 3, -2147483647), (466908701094, 1, 241, 241),
        (208480453546914, -1, 2147483648, 2147483648),
        (9223372036854775807, 2147483648, 4294967296, 4294967296),
        (7211765186901912905, -4294967297, -4294967295, -4294967295),
        (-478330528170494661, -9223372036854775807, -2147483648, -478330528170494661),
        (-2147483648, -274358740097498, -869751, -2147483648),
        (-9223372036854775807, -24855183368564, 6442450944, -24855183368564),
        (2, -274358740097498, 2147483648, 2),
        (9223372034707292160, -941484277, 2147483648, 2147483648),
        (-9223372036854775808, -1, 9223372036854775807, -1),
        (9223372034707292160, -9223372032559808512, -274358740097498, -274358740097498),
        (-4294967296, 4294967296, 9223372036854775807, 4294967296), (0, 0, 9223372036854775807, 0),
        (9223372036854775807, -9223372036854775808, 4294967296, 4294967296),
        (43, -4294967295, 13493037705, 43),
        (9223372036854775807, -6442450944, 37437668627, 37437668627),
        (0, -4294967296, 1352092485, 0), (0, -1, 9223372036854775807, 0),
        (-131892829986533, 1, 4294967296, 1),
        (-6442450944, 208480453546914, 4713042415780199964, 208480453546914),
        (247580, -2147483648, 208480453546914, 247580),
        (9223372036854775806, -4294967297, -2147483649, -2147483649),
        (0, -9223372036854775808, 1, 0), (10737418240, 1, 10737418240, 10737418240),
        (-11674931555, -4294967296, 13493037705, -4294967296),
        (4294967297, -671031825505, -98765, -98765),
        (9223372036854775807, -9223372036854775808, -1, -1),
    ]
        .span();
    for case in cases {
        let (a, b, c, want) = *case;
        let got = f(a).clamp(f(b), f(c)).raw;
        assert!(got == want, "clamp({} {} {}) = {} expected {}", a, b, c, got, want);
    }
}

// clamp(a, 0, 1)
#[test]
fn test_saturate_table() {
    let cases: Span<(i64, i64)> = array![
        (0, 0), (1, 1), (-1, 0), (2, 2), (-2, 0), (3, 3), (-3, 0), (4294967296, 4294967296),
        (-4294967296, 0), (2147483648, 2147483648), (-2147483648, 0), (4294967297, 4294967296),
        (4294967295, 4294967295), (-4294967297, 0), (-4294967295, 0), (6442450944, 4294967296),
        (-6442450944, 0), (10737418240, 4294967296), (-10737418240, 0), (2147483649, 2147483649),
        (2147483647, 2147483647), (-2147483649, 0), (-2147483647, 0), (13493037705, 4294967296),
        (-11674931555, 0), (12345, 12345), (-98765, 0), (2147483647, 2147483647),
        (2147483648, 2147483648), (-2147483649, 0), (4294967296333, 4294967296),
        (-3337189588997, 0), (4611686018427387904, 4294967296), (-4611686018427387904, 0),
        (9223372036854775807, 4294967296), (-9223372036854775808, 0),
        (9223372036854775806, 4294967296), (-9223372036854775807, 0),
        (9223372032559808511, 4294967296), (-9223372032559808512, 0),
        (9223372034707292159, 4294967296), (9223372034707292160, 4294967296),
        (12884901888, 4294967296), (-30064771072, 0), (199033079463936, 4294967296),
        (-199028784496640, 0), (-478330528170494661, 0), (247580, 247580),
        (759070236955776737, 4294967296), (24649316121, 4294967296), (43, 43),
        (4713042415780199964, 4294967296), (-4942304596022257876, 0), (241, 241), (-869751, 0),
        (-323966328, 0), (-671031825505, 0), (-24855183368564, 0), (37437668627, 4294967296),
        (7211765186901912905, 4294967296), (-941484277, 0), (-131892829986533, 0),
        (-302743759664, 0), (-57862, 0),
    ]
        .span();
    for case in cases {
        let (a, want) = *case;
        let got = f(a).saturate().raw;
        assert!(got == want, "saturate({}) = {} expected {}", a, got, want);
    }
}

// floor((a * b + c * 2^32) / 2^32)
#[test]
fn test_mul_add_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (0, 4294967296, 8589934592, 8589934592), (0, 37359273344, -869751, -869751),
        (-302743759664, 3, -30064771072, -30064771284),
        (-9223372036854775808, 4294967296, 4294967296, -9223372032559808512),
        (-3337189588997, -274358740097498, -2147483648, 213176738908591693),
        (-2147483649, -323966328, 3, 161983167), (2147483647, 2147483648, 13493037705, 14566779528),
        (-131892829986533, 24649316121, -11674931555, -756959944004327),
        (0, -9223372036854775808, 0, 0), (-302743759664, 12345, -899305830393, -899306700568),
        (9223372034707292160, 2147483647, 12345, 4611686015206174777),
        (-4611686018427387904, 2147483647, 37437668627, -2305842970702283501), (-98765, 241, 2, 1),
        (-869751, -1, -131892829986533, -131892829986533),
        (-9223372036854775807, -941484277, 2147483648, 2021822091854086143),
        (-98765, 6442450944, -24855183368564, -24855183516712),
        (2147483648, -302743759664, -30064771072, -181436650904),
        (-869751, -11674931555, -98765, 2265463), (-30064771072, 12345, 6442450944, 6442364529),
        (-9223372036854775808, -2147483647, -2147483649, 4611686014132420607),
        (-4294967296, 9223372036854775807, 4294967296, -9223372032559808511),
        (37359273344, 4294967296, 199033079463936, 199070438737280),
        (-24855183368564, 12884901888, 3, -74565550105689), (1, -98765, 2147483647, 2147483646),
        (4294967297, -1, -4294967296, -4294967298), (1, 2, -941484277, -941484277),
        (0, 1352092485, -302743759664, -302743759664), (2, 1, 12345, 12345),
        (-4294967296, 4294967296, 1, -4294967295),
        (-24855183368564, 466908701094, 12345, -2702023224443288),
        (3, -10737418240, 6442450944, 6442450936),
        (0, -9223372036854775808, 2147483648, 2147483648),
        (0, 9223372036854775807, -4294967296, -4294967296),
        (-2147483649, 12884901888, -4294967297, -10737418244),
        (9223372034707292159, 2, -941484277, 3353483017),
        (37359273344, -57862, -2147483649, -2147986955),
        (247580, -2147483648, 13493037705, 13492913915), (24649316121, 4294967296, -3, 24649316118),
        (-199028784496640, -2147483649, 4294967297, 99518687261957),
        (-30064771072, -98765, -4294967296, -4294275941),
        (-323966328, 9223372036854775806, 2, -695712391882604542),
        (-3337189588997, 208480453546914, 10737418240, -161989301668776642),
        (-2147483649, 466908701094, -2147483649, -235601834305),
        (4294967296333, -131892829986533, -2147483649, -131892832144242644),
        (-2147483648, -4294967296, 241, 2147483889),
        (9223372036854775806, 1, -199028784496640, -199026637012993),
        (9223372036854775806, 12345, 2147483649, 26512833118208),
        (24649316121, -671031825505, 4294967295, -3846834611627),
        (10737418240, 37437668627, 199033079463936, 199126673635503),
        (9223372036854775807, 4294967296, 0, 9223372036854775807),
        (-9223372032559808512, -57862, -4294967295, 124253403815419),
        (-478330528170494661, 24649316121, 241, -2745194453559680295),
        (1, 7211765186901912905, 1352092485, 3031212415),
        (-302743759664, 2147483649, 13493037705, -137878842198), (-98765, 10737418240, 0, -246913),
        (0, 4294967296, 4294967296, 4294967296),
    ]
        .span();
    for case in cases {
        let (a, b, c, want) = *case;
        let got = f(a).mul_add(f(b), f(c)).raw;
        assert!(got == want, "mul_add({} {} {}) = {} expected {}", a, b, c, got, want);
    }
}

// floor((a * 2^32 + (b - a) * c) / 2^32): b - a is exact
#[test]
fn test_lerp_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (9223372036854775807, -9223372036854775808, 0, 9223372036854775807),
        (1, -302743759664, -30064771072, 2119206317656), (-2, -24855183368564, 247580, -1432757431),
        (247580, -30064771072, -3337189588997, 23360519740219),
        (-941484277, 0, -899305830393, -198075069047), (43, 4294967295, 37359273344, 37359273004),
        (-11674931555, -4294967296, -4294967297, -19054895816),
        (12345, -199028784496640, 12345, -572054956),
        (-9223372036854775808, 9223372036854775807, 4294967296, 9223372036854775807),
        (0, -9223372036854775808, 4294967296, -9223372036854775808),
        (4294967296333, 4294967297, 43, 4294967253375),
        (4713042415780199964, -2147483649, -2, 4713042417974881363),
        (4294967296333, -3337189588997, -671031825505, 1196718521271526),
        (-9223372036854775808, 9223372036854775807, 2147483648, -1),
        (24649316121, -10737418240, 4294967295, -10737418232),
        (12345, -302743759664, 4294967296333, -302743772020128),
        (-478330528170494661, -671031825505, 6442450944, 239164257537509073),
        (13493037705, -1, 4294967296333, -13479544669342),
        (2147483647, -4294967297, -30064771072, 47244640255),
        (2147483649, 9223372036854775807, 247580, 531676148931698),
        (-478330528170494661, -57862, 2147483647, -239165264196646267),
        (-302743759664, 241, 13493037705, 648353812407),
        (1352092485, 4611686018427387904, -4294967297, -4611686016796944758),
        (-2147483647, 466908701094, 12884901888, 1405021070576),
        (12345, 247580, -274358740097498, -15026592931),
        (-2147483649, 7211765186901912905, -2147483649, -3605882598351301857),
        (-4294967296, 4294967296, 4294967296, 4294967296),
        (9223372036854775807, 9223372036854775807, 4294967296, 9223372036854775807),
        (0, -9223372036854775808, 1, -2147483648),
        (-9223372032559808512, -323966328, 1352092485, -6319775531892703092),
        (2, -4294967297, 4294967296, -4294967297),
        (-30064771072, -4294967295, 6442450944, 8589934593),
        (2147483647, 4294967297, -2147483647, 1073741822),
        (9223372036854775806, -2147483649, 43, 9223371944512978920),
        (241, -478330528170494661, -4294967297, 478330528281865147),
        (-4294967296, 4294967296, 1, -4294967294), (-3, 3, 0, -3),
        (-10737418240, 199033079463936, -2147483648, -99532645859328),
        (3, 9223372036854775807, 4294967295, 9223372034707292159),
        (1, -10737418240, -869751, 2174378),
        (4713042415780199964, 4294967297, -57862, 4713105910107681185),
        (37359273344, 247580, 466908701094, -4023964827972),
        (-2, -9223372032559808512, 4294967295, -9223372030412324866),
        (-9223372036854775808, 4294967296, 0, -9223372036854775808),
        (-4294967296, 9223372036854775807, -1, -6442450945),
        (247580, 6442450944, 2147483649, 3221349263),
        (-30064771072, -4294967295, -11674931555, -100114360405),
        (-57862, -899305830393, -6442450944, 1348958600934),
        (1352092485, 3, -4294967296, 2704184967),
        (4294967296333, -4294967297, -4294967295, 8594229558961), (-869751, 241, 4294967297, 241),
        (9223372036854775807, 4294967296, 8589934592, -9223372028264841215),
        (2147483648, 241, -30064771072, 17179867497),
        (37437668627, 2147483648, 4294967297, 2147483639),
        (-2147483649, 9223372036854775806, -98765, -212098370027752),
        (-2147483647, -478330528170494661, -323966328, 36080129179780205),
        (-2147483649, 4294967296, -10737418240, -18253611012),
        (-10737418240, 241, -2147483649, -16106127484),
        (9223372036854775807, 9223372036854775807, 2147483648, 9223372036854775807),
        (2147483648, -3, -199028784496640, 99516539870988),
        (-4611686018427387904, 9223372034707292160, 12345, -4611646252398942237),
        (1352092485, 4294967295, -2147483649, -119344921), (-4294967296, 4294967296, 2147483648, 0),
        (-4294967296, 9223372036854775807, 1, -2147483648),
        (-9223372036854775808, -9223372036854775808, 8589934592, -9223372036854775808),
        (-4294967297, 12345, 4294967296333, 4290684675036),
        (-2147483649, -131892829986533, -2, -2147422233),
        (-2147483648, 12884901888, -941484277, -5442678618),
        (4611686018427387904, 4294967297, 4294967295, 5368709119),
        (-6442450944, -98765, 12884901888, 12884605593), (-57862, 0, 1352092485, -39647),
        (12884901888, -2147483647, -869751, 12887946016),
    ]
        .span();
    for case in cases {
        let (a, b, c, want) = *case;
        let got = f(a).lerp(f(b), f(c)).raw;
        assert!(got == want, "lerp({} {} {}) = {} expected {}", a, b, c, got, want);
    }
}

// trunc((c - a) * 2^32 / (b - a))
#[test]
fn test_inverse_lerp_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (-30064771072, -478330528170494661, -671031825505, 5755),
        (-9223372032559808512, -274358740097498, -4294967295, 4295095056),
        (4294967296, -302743759664, -323966328, 64611292),
        (2147483648, 4294967296, -2147483647, -8589934590),
        (1, 4294967295, -131892829986533, -131892830047951), (0, -9223372036854775808, 0, 0),
        (-6442450944, 2147483647, -10737418240, -2147483648),
        (-131892829986533, -24855183368564, 2, 5292300506),
        (208480453546914, -899305830393, -11674931555, 4276759491),
        (-98765, -899305830393, -2147483649, 10255631),
        (4294967296, -6442450944, -199028784496640, 79613231785574),
        (0, -9223372036854775808, 2147483648, -1),
        (-941484277, -2147483647, -131892829986533, 469711147299246),
        (2147483647, -4942304596022257876, 6442450944, -3),
        (2147483647, -478330528170494661, 6442450944, -38),
        (199033079463936, 12884901888, 4294967296333, 4202557558),
        (37437668627, -2147483647, 10737418240, 2896962512), (0, -1, 2, -8589934592),
        (4611686018427387904, -131892829986533, -869751, 4294844464),
        (-899305830393, -9223372036854775807, -302743759664, -277),
        (247580, -11674931555, -899305830393, 330829201790),
        (-4294967297, -131892829986533, -2147483649, -69933), (43, 12345, -3, -16059867),
        (-2147483649, -2147483648, -4294967295, -9223372028264841216),
        (-10737418240, 3, 13493037705, 9692182375), (2147483649, 1352092485, -2, 11596020256),
        (0, 4294967296, 1, 1), (37437668627, 4713042415780199964, 43, -34),
        (-4942304596022257876, 37359273344, -4294967297, 4294967259),
        (1352092485, -30064771072, -4294967296, 772003769),
        (-4942304596022257876, -6442450944, -2147483647, 4294967299),
        (466908701094, 43, 247580, 4294965018), (0, 4294967296, 8589934592, 8589934592),
        (1, 241, 13493037705, 241467315259895534), (2147483647, 37437668627, 4294967297, 261357996),
        (-4942304596022257876, 2147483648, -24855183368564, 4294945694),
        (7211765186901912905, -11674931555, 43, 4294967289),
        (0, 9223372036854775807, 8589934592, 4), (0, 4294967296, 4294967296, 4294967296),
        (13493037705, 241, 37437668627, -7621812879),
    ]
        .span();
    for case in cases {
        let (a, b, c, want) = *case;
        let got = FixedTrait::inverse_lerp(f(a), f(b), f(c)).raw;
        assert!(got == want, "inverse_lerp({} {} {}) = {} expected {}", a, b, c, got, want);
    }
}

// t = saturate((a - b) / (c - b)); floor(t^2 (3 - 2 t)) exact
#[test]
fn test_smoothstep_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (-4942304596022257876, -671031825505, -24855183368564, 4294967296),
        (9223372036854775807, 2147483649, -671031825505, 0),
        (0, 4611686018427387904, -899305830393, 4294967295),
        (-131892829986533, -899305830393, 10737418240, 0),
        (-98765, -199028784496640, -671031825505, 4294967296),
        (-57862, -131892829986533, 4294967296, 4294967282),
        (4294967297, 12884901888, -2147483649, 2604528270),
        (10737418240, 4294967295, -671031825505, 0),
        (0, 9223372036854775807, 2147483648, 4294967296), (-671031825505, -941484277, -98765, 0),
        (-2, -9223372036854775808, -2147483648, 4294967296), (2, -4294967297, -2, 4294967296),
        (12345, -2147483647, 12884901888, 237916231),
        (4713042415780199964, 13493037705, -2147483649, 0),
        (199033079463936, 4611686018427387904, -4294967295, 4294967271),
        (12884901888, 208480453546914, -2, 4294967246),
        (4611686018427387904, -3337189588997, 2, 4294967296),
        (9223372036854775807, 4294967296, -4294967296, 0),
        (208480453546914, -4294967295, -671031825505, 0),
        (-274358740097498, 3, -2147483648, 4294967296),
        (-4294967295, 4294967296333, -2147483648, 4294967296),
        (-4294967296, -9223372036854775808, -4294967296, 4294967296),
        (-4294967296, 4294967296, 0, 4294967296),
        (1352092485, 208480453546914, 13493037705, 4294967296),
        (37437668627, -4611686018427387904, 10737418240, 4294967296),
        (208480453546914, 37437668627, -274358740097498, 0),
        (-2147483647, 43, -671031825505, 131682),
        (-671031825505, 199033079463936, -2147483648, 4294967296),
        (2147483647, 4294967296333, 2147483647, 4294967296), (-2, -57862, -941484277, 0),
        (0, 4294967296, 0, 4294967296), (4294967295, -4611686018427387904, 43, 4294967296),
        (759070236955776737, 37359273344, -323966328, 0), (2, -274358740097498, 2, 4294967296),
        (-2147483649, 2147483647, 2, 4294967296), (0, 4294967296, -1, 4294967295),
        (199033079463936, -671031825505, 466908701094, 4294967296),
        (-3337189588997, 2147483649, -274358740097498, 1893297),
        (-323966328, -30064771072, 199033079463936, 287),
        (43, 7211765186901912905, 241, 4294967296), (10737418240, 4294967297, 4294967296333, 29020),
        (-6442450944, -199028784496640, 12884901888, 4294967174), (2147483647, 0, -4294967296, 0),
        (4611686018427387904, 7211765186901912905, -2147483647, 1272276793),
        (-899305830393, 7211765186901912905, 1352092485, 4294967296), (-57862, 0, 466908701094, 0),
        (-2147483647, -199028784496640, -6442450944, 4294967296),
        (208480453546914, -10737418240, 1, 4294967296),
        (7211765186901912905, 2147483647, -3337189588997, 0),
        (4294967295, 759070236955776737, -131892829986533, 4294966907),
        (2147483648, -478330528170494661, 1352092485, 4294967296),
        (-4294967297, 4294967297, -941484277, 4294967296),
        (-671031825505, 199033079463936, 466908701094, 4294967296),
        (-302743759664, -9223372036854775807, -2147483649, 4294967295),
        (-302743759664, -4611686018427387904, 37437668627, 4294967295),
        (-274358740097498, -24855183368564, -899305830393, 0),
    ]
        .span();
    for case in cases {
        let (a, b, c, want) = *case;
        let got = f(a).smoothstep(f(b), f(c)).raw;
        assert!(got == want, "smoothstep({} {} {}) = {} expected {}", a, b, c, got, want);
    }
}

//
#[test]
fn test_move_towards_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (-2147483647, 6442450944, 2147483649, 2),
        (-4611686018427387904, -98765, -2147483647, -4611686020574871551),
        (-4294967295, 466908701094, 12884901888, 8589934593), (241, -274358740097498, 0, 241),
        (-323966328, 6442450944, 2147483647, 1823517319),
        (2147483649, -2147483649, -4294967296, 6442450945),
        (0, 4294967296, -4294967296, -4294967296), (-10737418240, 241, -30064771072, -40802189312),
        (247580, 247580, 6442450944, 247580),
        (4611686018427387904, 4294967295, 4294967295, 4611686014132420609),
        (-24855183368564, 4713042415780199964, 241, -24855183368323),
        (-9223372036854775808, -9223372036854775808, 1, -9223372036854775808),
        (9223372032559808511, 9223372036854775807, 247580, 9223372032560056091),
        (9223372034707292159, 1352092485, 1, 9223372034707292158),
        (-9223372036854775808, -9223372036854775808, 4294967296, -9223372036854775808),
        (2, -1, -30064771072, 30064771074),
        (9223372034707292160, 199033079463936, 466908701094, 9223371567798591066),
        (9223372034707292160, 4294967296333, 12884901888, 9223372021822390272),
        (-3, -3, 13493037705, -3), (2147483648, -9223372032559808512, -57862, 2147541510),
        (9223372036854775807, 9223372036854775807, -1, 9223372036854775806),
        (4294967296, -98765, -869751, 4295837047), (-2147483649, -3, 2147483648, -3),
        (-899305830393, 24649316121, 4294967296, -895010863097),
        (-2147483648, 10737418240, -1, -2147483649), (-6442450944, -2, -4294967297, -10737418241),
        (247580, -4294967297, 4294967297, -4294719717), (0, 4294967296, 8589934592, 4294967296),
        (-2147483649, 2147483649, 247580, -2147236069),
        (-941484277, 247580, -274358740097498, -274359681581775), (-1, 9223372034707292160, -3, -4),
        (247580, -131892829986533, -199028784496640, 199028784744220),
        (7211765186901912905, -11674931555, -323966328, 7211765187225879233),
        (4294967296333, -2147483647, -199028784496640, 203323751792973),
        (4713042415780199964, 247580, 2147483648, 4713042413632716316),
        (-57862, -941484277, -3, -57859), (2, 4294967296333, -941484277, -941484275),
        (2147483648, -869751, 466908701094, -869751),
        (-671031825505, 2147483647, 2147483647, -668884341858),
        (9223372036854775807, 9223372036854775807, 4294967296, 9223372036854775807),
        (13493037705, 4294967296, 2147483647, 11345554058), (2, -131892829986533, -98765, 98767),
        (-4294967296, 4294967296, 8589934592, 4294967296),
        (-274358740097498, 4294967295, 199033079463936, -75325660633562),
        (-24855183368564, 2, 4294967296333, -20560216072231), (-4294967296, -2, 1, -4294967295),
        (9223372036854775807, 1, 2147483649, 9223372034707292158),
        (7211765186901912905, 9223372032559808511, -671031825505, 7211764515870087400),
    ]
        .span();
    for case in cases {
        let (a, b, c, want) = *case;
        let got = f(a).move_towards(f(b), f(c)).raw;
        assert!(got == want, "move_towards({} {} {}) = {} expected {}", a, b, c, got, want);
    }
}

// lerp(d, e, inverse_lerp(b, c, a))
#[test]
fn test_remap_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64)> = array![
        (10737418240, -2147483649, -3, 2147483647, -899305830393, -5406572406051),
        (2147483647, -24855183368564, -10737418240, 6442450944, -302743759664, -302904110685),
        (2147483647, -323966328, -3, 0, 2147483647, 16382562001),
        (-11674931555, -899305830393, 2147483648, -2147483649, -4294967297, -4262038902),
        (2147483647, 241, -98765, -11674931555, -2147483648, -206666183565495),
        (13493037705, -4294967295, -2147483649, 4294967297, 4294967295, 4294967280),
        (1352092485, 2147483649, 241, 2147483647, -4294967296, -238690111),
        (37437668627, -57862, -2147483647, 3, -323966328, 5647954393),
        (-24855183368564, -30064771072, -4294967297, -869751, 3, -838739779),
        (-11674931555, 2147483647, -4294967297, 1352092485, -302743759664, -651092010877),
        (-899305830393, 2147483648, 4294967296, 6442450944, -2147483648, 3612255707108),
        (2147483647, -2147483647, -671031825505, -10737418240, 2147483647, -10820153368),
        (-2, 0, 3, -941484277, 1352092485, -2470535452),
        (4294967296333, 466908701094, 2147483649, -24855183368564, 4294967297, -229613102369439),
        (-899305830393, 2147483648, 43, 2147483649, -2147483647, -1800759180533),
        (-4294967296, 6442450944, 4294967295, -941484277, -3337189588997, -16682182000110),
        (-2147483649, -24855183368564, -2147483647, -302743759664, -4294967296, -4294967366),
        (37359273344, -899305830393, -4294967297, -3, -4294967297, -4494857162),
        (-30064771072, -323966328, 247580, -2147483649, 4294967297, -593126682659),
        (2147483649, -6442450944, 4294967295, -6442450944, -869751, -1289185990),
        (-30064771072, 1, 37437668627, 37359273344, -3, 67361088137),
        (2, -4294967295, 241, -671031825505, -2147483648, -2147520870),
        (4294967297, -11674931555, -4294967295, 10737418240, 12884901888, 15384472810),
        (-6442450944, 4294967296, 2, -30064771072, 4294967297, 55834574890),
        (4294967295, 1, 4294967296333, -2147483647, -24855183368564, -27000517820),
        (37359273344, 37359273344, 12884901888, 4294967296333, -98765, 4294967296333),
        (-30064771072, -4294967296, 1, 1, 6442450944, -38654705649),
        (6442450944, -2147483647, 2147483648, 2147483647, -323966328, -2795416304),
        (0, -24855183368564, 6442450944, -6442450944, 24649316121, 24641259238),
        (37437668627, -2, -302743759664, 247580, 466908701094, -57738230576),
        (37437668627, -98765, 10737418240, 4294967296, -10737418240, -48117424950),
        (1, -1, 10737418240, -302743759664, -2147483649, -302743759664),
    ]
        .span();
    for case in cases {
        let (a, b, c, d, e, want) = *case;
        let got = f(a).remap(f(b), f(c), f(d), f(e)).raw;
        assert!(got == want, "remap({} {} {} {} {}) = {} expected {}", a, b, c, d, e, got, want);
    }
}

// n = 2, 3: floor of the exact power; 4: floor(floor(x^2)^2); otherwise binary exponentiation
// (least significant bit first, every product floored); n < 0: recip (truncated) of the power.
#[test]
fn test_powi_table() {
    let cases: Span<(i64, i32, i64)> = array![
        (-4294967297, 10, 4294967306), (-6442450944, -1, -2863311530),
        (-4294967297, -3, -4294967292), (8589934592, -3, 536870912), (4294967297, 1, 4294967297),
        (6442450944, -5, 565592401), (2147483648, 5, 134217728), (-4294967297, 3, -4294967300),
        (12345, 1, 12345), (2147483648, 31, 2), (-11674931555, 0, 4294967296), (12345, 6, 0),
        (-4294967296, -2, 4294967296), (6442450944, -1, 2863311530), (13493037705, -2, 435171170),
        (4294967296, 0, 4294967296), (2147483648, 6, 67108864), (0, 31, 0),
        (6442450944, 7, 73383542784), (13493037705, -5, 14034937), (12345, 5, 0),
        (-6442450944, 0, 4294967296), (6074001000, -2, 2147483648), (6442450944, 6, 48922361856),
        (6442450944, 0, 4294967296), (12345, 3, 0), (6074001000, -5, 759250124),
        (4294967296, 1, 4294967296), (12345, 4, 0), (-8589934592, 31, -9223372036854775808),
        (6074001000, 4, 17179869184), (6442450944, 13, 835884417024), (4294967296, -5, 4294967296),
        (2147483648, 3, 536870912), (-8589934592, -4, 268435456), (4294967296, 3, 4294967296),
        (-6442450944, 3, -14495514624), (4294967296, 31, 4294967296), (4294967296, -4, 4294967296),
        (6074001000, 7, 48592008000), (-4294967296, 2, 4294967296), (2147483648, -5, 137438953472),
        (-6442450944, -4, 848388601), (12345, 31, 0), (6442450944, 10, 247669456896),
        (4294967297, 0, 4294967296), (4294967297, -8, 4294967288), (-6442450944, 2, 9663676416),
        (-4294967296, 0, 4294967296), (-6442450944, 10, 247669456896),
        (12345, -1, 1494268454735484), (-4294967297, -1, -4294967295), (0, 5, 0),
        (-8589934592, 4, 68719476736), (-6442450944, 4, 21743271936), (2147483648, 4, 268435456),
        (6074001000, 6, 34359738368), (-4294967296, -3, -4294967296), (4294967297, 31, 4294967327),
        (6442450944, 5, 32614907904), (6442450944, -3, 1272582902), (4294967296, -3, 4294967296),
        (-8589934592, 5, -137438953472), (-4294967296, 13, -4294967296),
        (-11674931555, -4, 78665070), (2147483648, -1, 8589934592), (-11674931555, 1, -11674931555),
        (13493037705, 10, 402215301378625), (13493037705, 3, 133170944326),
        (-4294967297, 4, 4294967300), (-4294967296, -5, -4294967296), (-4294967296, -4, 4294967296),
    ]
        .span();
    for case in cases {
        let (a, n, e) = *case;
        let got = f(a).powi(n).raw;
        assert!(got == e, "powi({}, {}) = {} expected {}", a, n, got, e);
    }
}

// |a - b| <= c with an exact (non overflowing) difference
#[test]
fn test_abs_diff_eq_table() {
    let cases: Span<(i64, i64, i64, bool)> = array![
        (2147483648, 3, -1, false), (2147483649, -2147483649, 9223372036854775807, true),
        (-4294967295, 4294967296, -9223372036854775808, false),
        (-2147483647, -13493037705, 11345554057, false), (-4294967297, -3, 4294967295, true),
        (43, -9223372032559808512, -1, false), (2, -869751, 1, false),
        (-274358740097498, 199033079463936, 473391819561434, true),
        (-2147483647, -24855183368564, 0, false),
        (-9223372036854775808, -131892829986533, 9223372036854775807, true),
        (-4294967296, 208480453546914, -1, false), (-10737418240, -3, 0, false),
        (7211765186901912905, 37359273344, 7211765149542639562, true),
        (-899305830393, -6442450944, -1, false), (2147483649, -2147483649, 4294967297, false),
        (2147483648, 4294967296, 2147483648, true),
        (2147483649, -4294967296, 9223372036854775807, true), (-2, 4294967296, -1, false),
        (-98765, 4713042415780199964, 0, false), (12345, 4294967297, 4294954952, true),
        (-9223372036854775808, 9223372034707292159, 9223372036854775807, false),
        (2147483649, -9223372036854775807, -1, false), (4294967295, -2147483649, 6442450943, false),
        (-4294967297, 4294967296, 9223372036854775807, true),
        (-3, -13493037705, -9223372036854775808, false),
        (6442450944, 4294967296, 2147483647, false),
        (4611686018427387904, 199033079463936, 4611486985347923969, true),
        (-24855183368564, -6442450944, 9223372036854775807, true),
        (24649316121, 12345, 24649303777, true),
        (466908701094, -9223372032559808512, -9223372036854775808, false),
        (-869751, -10737418240, 9223372036854775807, true),
        (-4294967295, 3, -9223372036854775808, false), (4294967297, 4294967296, 0, false),
        (-2, 4294967296, 4294967298, true), (2147483647, 10737418240, 0, false),
        (-4294967295, -4294967296, -1, false), (4294967295, -4294967296, 8589934592, true),
        (-4294967295, -13493037705, 9198070410, true),
        (-4294967296, -13493037705, -9223372036854775808, false),
        (-3337189588997, 9223372036854775807, -1, false),
        (9223372036854775806, -2, -9223372036854775808, false),
        (4611686018427387904, 759070236955776737, 3852615781471611167, true),
        (2147483648, -30064771072, 32212254719, false),
        (759070236955776737, -941484277, 759070237897261014, true),
        (-869751, -10737418240, 10736548490, true), (2, 2, 9223372036854775807, true),
        (-941484277, -899305830393, 898364346117, true), (-3, 10737418240, 10737418244, true),
        (-9223372036854775808, 9223372036854775807, 9223372036854775807, false),
        (9223372036854775807, -9223372036854775808, 9223372036854775807, false),
        (-9223372036854775808, -9223372036854775808, 0, true),
    ]
        .span();
    for case in cases {
        let (a, b, c, e) = *case;
        assert!(f(a).abs_diff_eq(f(b), f(c)) == e, "abs_diff_eq({} {} {})", a, b, c);
    }
}

// from_ratio(num, den) = trunc(num * 2^32 / den), plain integers
#[test]
fn test_from_ratio_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (1, 3, 1431655765), (-1, 3, -1431655765), (1, -3, -1431655765), (-1, -3, 1431655765),
        (22, 7, 13498468644), (-355, 113, -13493038850), (0, 5, 0), (7, 1, 30064771072),
        (2147483647, 1, 9223372032559808512), (-2147483648, 1, -9223372036854775808),
        (1, 4294967296, 1), (1, 4294967297, 0), (-1, 8589934592, 0),
        (123456789, 1000, 530242871224172), (-123456789, 1000, -530242871224172),
        (1099511627776, 1048576, 4503599627370496),
    ]
        .span();
    for case in cases {
        let (a, b, e) = *case;
        let got = FixedTrait::from_ratio(a, b).raw;
        assert!(got == e, "from_ratio({}, {}) = {} expected {}", a, b, got, e);
    }
}
