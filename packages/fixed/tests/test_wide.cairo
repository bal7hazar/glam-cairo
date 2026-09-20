//! Tests of `fixed::wide`.
//!
//! The expected values of the `*_table` tests were computed offline with Python big integers
//! (exact sums of products, then the single rounding stated above each table). The fuzz
//! properties use an independent `i128` / `u128` reference written with the stable corelib.
use fixed::fixed::{EPSILON, HALF, MAX, MIN, NEG_ONE, TWO};
use fixed::wide::{
    NormTrait, RecipTrait, WideAdd, WideLift, WideMul, WideNarrow, WideNeg, WideSqrt, WideSub, det3,
    distance2, distance2_squared, distance3, distance3_squared, distance4, distance4_squared, dot2,
    dot2_add, dot3, dot3_add, dot4, mul_add, mul_sub, norm2, norm2_squared, norm2_wide, norm3,
    norm3_squared, norm3_wide, norm4, norm4_squared, norm4_wide, normalize2, normalize3, normalize4,
    wide_from, wide_mul,
};
use fixed::{Fixed, FixedTrait, ONE, ONE_RAW, ZERO};

const I64_MIN: i64 = -0x8000000000000000;
const I64_MAX: i64 = 0x7fffffffffffffff;
const ONE_I128: i128 = 0x100000000;

fn f(raw: i64) -> Fixed {
    FixedTrait::from_raw(raw)
}

/// Hides a value from the constant folder (the exhaustive tests must reach Sierra).
#[inline(never)]
fn opaque(x: Fixed) -> Fixed {
    x
}

fn int(v: i32) -> Fixed {
    FixedTrait::from_int(v)
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

// ------------------------------------------------------------------ accumulator API

#[test]
fn test_wide_mul_narrow_is_mul() {
    assert_eq!(wide_mul(f(-1), HALF).narrow().raw, -1); // floor
    assert_eq!(wide_mul(int(3), int(-7)).narrow(), int(-21));
    assert_eq!(wide_mul(MIN, ONE).narrow(), MIN);
    assert_eq!(wide_mul(MAX, ONE).narrow(), MAX);
    assert_eq!(wide_from(MIN).narrow(), MIN);
    assert_eq!(wide_from(MAX).narrow(), MAX);
}

#[test]
fn test_wide_add_sub_neg() {
    let p = wide_mul(int(3), int(5));
    let q = wide_mul(int(2), HALF);
    assert_eq!(p.add(q).narrow(), int(16));
    assert_eq!(p.sub(q).narrow(), int(14));
    assert_eq!(q.sub(p).narrow(), int(-14));
    assert_eq!(p.neg().narrow(), int(-15));
    assert_eq!(p.add(q).neg().narrow(), int(-16));
    assert_eq!(p.add(q.neg()).narrow(), p.sub(q).narrow());
    assert_eq!(p.add(wide_from(f(7))).narrow().raw, 15 * ONE_RAW + 7);
    // neg is exact, the floor happens once at the end: -(1/2 ULP) -> -1 ULP, +(1/2 ULP) -> 0
    assert_eq!(wide_mul(f(1), HALF).neg().narrow().raw, -1);
    assert_eq!(wide_mul(f(1), HALF).narrow().raw, 0);
    // two halves of an ULP add up before the rescale (two separate `*` would give 0)
    assert_eq!(wide_mul(f(1), HALF).add(wide_mul(f(1), HALF)).narrow().raw, 1);
}

#[test]
fn test_wide_sums_are_exact_up_to_16_products() {
    // Each product is +-2^126, far outside the Fixed range: the intermediate sums cannot
    // overflow, only the final narrow is range-checked.
    let p = wide_mul(MIN, MIN); // 2^126
    let s2 = p.add(p);
    let s4 = s2.add(s2);
    let s8 = s4.add(s4);
    assert_eq!(s8.sub(s8).narrow(), ZERO); // a W16 worth 0
    assert_eq!(s8.sub(s4).sub(s2).sub(p).sub(p).narrow(), ZERO);
    let n = wide_mul(MIN, MAX); // -(2^126 - 2^63)
    let n8 = n.add(n).add(n.add(n)).add(n.add(n).add(n.add(n)));
    // 8 * 2^126 - 8 * (2^126 - 2^63) = 2^66 -> 2^34 raw
    assert_eq!(s8.add(n8).narrow().raw, 0x400000000);
    // mixed widths: W3 + W5 + W7 + W1 = W16
    let w3 = p.add(p).add(n);
    let w5 = s4.add(n);
    let w7 = w5.add(s2);
    assert_eq!(w7.sub(w5).sub(p).add(n).narrow().raw, 0x80000000); // p + n = 2^63 -> 2^31
    assert_eq!(w3.add(w5).sub(w7).sub(n).narrow(), ZERO); // W3 + W5 + W7 + W1 = W16
}

#[test]
fn test_wide_narrow_boundaries() {
    // MAX * 2^32 + (2^32 - 1) is the largest Q64.64 value that narrows into range.
    let top = wide_from(MAX).add(wide_mul(f(0xffffffff), f(1)));
    assert_eq!(top.narrow(), MAX);
    assert_eq!(wide_from(MIN).narrow(), MIN);
    assert_eq!(wide_from(MIN).add(wide_mul(f(1), f(1))).narrow(), MIN);
}

#[test]
fn test_triple_products() {
    // (3 * 5 - 2 * 4) * -6 = -42
    assert_eq!(
        wide_mul(int(3), int(5)).sub(wide_mul(int(2), int(4))).mul(int(-6)).narrow(), int(-42),
    );
    // exact: (1/2 ULP-scale products) accumulate before the single rescale
    assert_eq!(wide_mul(f(1), f(1)).mul(f(1)).narrow().raw, 0);
    assert_eq!(wide_mul(f(-1), f(1)).mul(f(1)).narrow().raw, -1);
    assert_eq!(wide_mul(HALF, HALF).mul(HALF).narrow().raw, ONE_RAW / 8);
    // x * y * z with one rescale keeps the bits that two rescales lose: 3 ULP * 1/2 * 2
    assert_eq!(wide_mul(f(3), HALF).mul(TWO).narrow().raw, 3);
    assert_eq!((f(3) * HALF * TWO).raw, 2);
}

#[test]
fn test_triple_lift_and_sums() {
    // a*b*c + d*e: the Q64.64 term is lifted to Q96.96
    let t = wide_mul(int(2), int(3)).mul(int(4)).add(wide_mul(int(5), int(6)).lift());
    assert_eq!(t.narrow(), int(54));
    assert_eq!(wide_mul(f(-1), HALF).lift().narrow().raw, -1); // lift is exact, floor at the end
    assert_eq!(wide_from(MAX).lift().narrow(), MAX);
    assert_eq!(wide_from(MIN).lift().narrow(), MIN);
    // largest Q96.96 value that narrows into range: MAX * 2^64 + (2^64 - 1)
    let frac = wide_mul(f(0xffffffff), f(0x100000001)).mul(f(1)); // 2^64 - 1
    assert_eq!(wide_from(MAX).lift().add(frac).narrow(), MAX);
    // 16 extreme triple products cancel exactly
    let t1 = wide_mul(MIN, MIN).mul(MIN); // -2^189
    let t2 = t1.add(t1);
    let t4 = t2.add(t2);
    let t8 = t4.add(t4);
    assert_eq!(t8.sub(t8).narrow(), ZERO);
    assert_eq!(t8.add(t8.neg()).narrow(), ZERO);
    assert_eq!(t4.sub(t2).sub(t1).sub(t1).narrow(), ZERO);
}

#[test]
fn test_wide_sqrt() {
    assert_eq!(wide_mul(int(-5), int(-5)).sqrt(), int(5));
    assert_eq!(wide_mul(int(3), int(3)).add(wide_mul(int(4), int(4))).sqrt(), int(5));
    assert_eq!(
        wide_mul(int(2), int(2)).add(wide_mul(int(3), int(3))).add(wide_mul(int(6), int(6))).sqrt(),
        int(7),
    );
    // discriminant b^2 - 4ac = 25 - 16 = 9
    assert_eq!(wide_mul(int(5), int(5)).sub(wide_mul(int(4), int(4))).sqrt(), int(3));
    assert_eq!(wide_mul(ZERO, ONE).sqrt(), ZERO);
    assert_eq!(wide_mul(f(1), f(1)).sqrt().raw, 1); // sqrt(2^-64) = 2^-32: no underflow
    assert_eq!(wide_mul(TWO, ONE).sqrt().raw, 6074000999); // floor(sqrt(2) * 2^32)
    assert_eq!(wide_mul(MAX, MAX).sqrt(), MAX);
}

// ------------------------------------------------------------------ named kernels

#[test]
fn test_named_kernels_small_integers() {
    assert_eq!(dot2(int(1), int(2), int(3), int(4)), int(14));
    assert_eq!(dot3(int(1), int(2), int(3), int(4), int(5), int(-6)), int(-16));
    assert_eq!(dot4(int(1), int(2), int(3), int(4), int(5), int(6), int(7), int(8)), int(100));
    assert_eq!(dot2_add(int(1), int(2), int(3), int(4), int(-4)), int(10));
    assert_eq!(dot3_add(int(1), int(2), int(3), int(4), int(5), int(6), int(1)), int(45));
    assert_eq!(mul_add(int(3), int(4), int(5)), int(17));
    assert_eq!(mul_sub(int(3), int(4), int(5), int(6)), int(-18));
    // det of [[2,0,0],[0,3,0],[0,0,4]] and of a singular matrix
    assert_eq!(det3(int(2), ZERO, ZERO, ZERO, int(3), ZERO, ZERO, ZERO, int(4)), int(24));
    assert_eq!(det3(int(1), int(2), int(3), int(4), int(5), int(6), int(7), int(8), int(9)), ZERO);
    assert_eq!(
        det3(int(2), int(-1), ZERO, int(1), int(3), int(1), ZERO, int(5), int(-4)), int(-38),
    );
    assert_eq!(norm2_squared(int(3), int(4)), int(25));
    assert_eq!(norm3_squared(int(1), int(2), int(2)), int(9));
    assert_eq!(norm4_squared(int(1), int(1), int(1), int(1)), int(4));
    assert_eq!(norm2(int(3), int(-4)), int(5));
    assert_eq!(norm3(int(2), int(3), int(6)), int(7));
    assert_eq!(norm4(int(2), int(4), int(5), int(6)), int(9));
    assert_eq!(distance2(int(1), int(1), int(4), int(5)), int(5));
    assert_eq!(distance3(int(1), int(2), int(3), int(3), int(5), int(9)), int(7));
    assert_eq!(distance4(int(1), int(1), int(1), int(1), int(3), int(5), int(6), int(7)), int(9));
    assert_eq!(distance2_squared(int(1), int(1), int(4), int(5)), int(25));
    assert_eq!(distance3_squared(int(1), int(2), int(3), int(3), int(5), int(9)), int(49));
    assert_eq!(
        distance4_squared(int(1), int(1), int(1), int(1), int(3), int(5), int(6), int(7)), int(81),
    );
}

#[test]
fn test_norm_of_tiny_vectors_does_not_underflow() {
    // length_squared of (3, 4) ULP underflows to 0; the length is still exact.
    assert_eq!(norm2_squared(f(3), f(4)), ZERO);
    assert_eq!(norm2(f(3), f(4)).raw, 5);
    assert_eq!(norm3(f(2), f(3), f(6)).raw, 7);
    assert_eq!(norm4(f(2), f(4), f(5), f(6)).raw, 9);
    assert_eq!(distance2(f(1), f(1), f(4), f(5)).raw, 5);
    assert_eq!(norm3(ZERO, ZERO, ZERO), ZERO);
}

#[test]
fn test_distance_differences_cannot_overflow() {
    // MAX - MIN overflows a Fixed; the kernel computes it on 65 bits.
    assert_eq!(distance2_squared(f(1), ZERO, f(-1), ZERO).raw, 0);
    assert_eq!(distance2(f(0x4000000000000000), ZERO, f(-0x3fffffffffffffff), ZERO), MAX);
    assert_eq!(distance3(MAX, ZERO, ZERO, ZERO, ZERO, ZERO), MAX);
}

#[test]
fn test_norm_type() {
    let zero = norm3_wide(ZERO, ZERO, ZERO);
    assert!(zero.is_zero());
    assert!(zero.try_recip().is_none());
    assert_eq!(zero.to_fixed(), ZERO);
    let n = norm3_wide(int(2), int(3), int(6));
    assert!(!n.is_zero());
    assert_eq!(n.to_fixed(), int(7));
    assert_eq!(n.recip().mul(int(14)), int(2));
    assert_eq!(n.try_recip().unwrap().mul(int(-21)), int(-3));
    assert_eq!(norm2_wide(int(3), int(4)).to_fixed(), int(5));
    assert_eq!(norm4_wide(int(2), int(4), int(5), int(6)).to_fixed(), int(9));
    assert!(!norm2_wide(f(1), ZERO).is_zero());
}

#[test]
fn test_normalize_axis_aligned_is_exact() {
    assert_eq!(normalize3(int(3), ZERO, ZERO), (ONE, ZERO, ZERO));
    assert_eq!(normalize3(ZERO, int(-3), ZERO), (ZERO, NEG_ONE, ZERO));
    assert_eq!(normalize2(ZERO, f(1)), (ZERO, ONE));
    assert_eq!(normalize2(f(-1), ZERO), (NEG_ONE, ZERO));
    assert_eq!(normalize4(ZERO, ZERO, ZERO, MAX), (ZERO, ZERO, ZERO, ONE));
    assert_eq!(normalize3(MIN, ZERO, ZERO), (NEG_ONE, ZERO, ZERO));
    // 3-4-5: 0.6 and 0.8 rounded to nearest
    assert_eq!(normalize2(int(3), int(4)), (f(2576980378), f(3435973837)));
    assert_eq!(normalize3(int(-3), ZERO, int(4)), (f(-2576980378), ZERO, f(3435973837)));
}

#[test]
fn test_normalize_works_beyond_the_length_range() {
    // |(MIN, MIN)| = 2^31.5 does not fit a Fixed, the normalized vector does.
    let (x, y) = normalize2(MIN, MIN);
    assert_eq!(x.raw, -3037000499); // -1/sqrt(2) = -3037000499.97: within 1 ULP
    assert_eq!(y.raw, -3037000499);
    let (a, b, c) = normalize3(MAX, MIN, MAX);
    assert_eq!((a.raw, b.raw, c.raw), (2479700524, -2479700524, 2479700524)); // 1/sqrt(3)
    let (p, q, r, s) = normalize4(MAX, MAX, MAX, MAX);
    assert_eq!((p.raw, q.raw, r.raw, s.raw), (2147483648, 2147483648, 2147483648, 2147483648));
}

#[test]
fn test_recip_is_exact_on_representable_quotients() {
    assert_eq!(RecipTrait::new(int(3)).mul(int(3)), ONE);
    assert_eq!(RecipTrait::new(int(3)).mul(int(-9)), int(-3));
    assert_eq!(RecipTrait::new(int(-3)).mul(int(9)), int(-3));
    assert_eq!(RecipTrait::new(int(-7)).mul(int(-7)), ONE);
    assert_eq!(RecipTrait::new(f(7)).mul(f(21)), int(3));
    assert_eq!(RecipTrait::new(MIN).mul(MIN), ONE);
    assert_eq!(RecipTrait::new(MAX).mul(MAX), ONE);
    assert_eq!(RecipTrait::new(f(1)).mul(f(0x7fffffff)).raw, 0x7fffffff00000000);
    // Truncated division and Q32.32 reciprocal both miss 1: they give 1 - 1 ULP or 1 + ...
    assert_eq!((int(3) * (ONE / int(3))).raw, ONE_RAW - 1);
    // Rounds to nearest: 1/3 -> 0x55555555, 2/3 -> 0xaaaaaaab
    assert_eq!(RecipTrait::new(int(3)).mul(ONE).raw, 0x55555555);
    assert_eq!(RecipTrait::new(int(3)).mul(TWO).raw, 0xaaaaaaab);
    assert_eq!(RecipTrait::new(int(-3)).mul(TWO).raw, -0xaaaaaaab);
    // ties round toward +infinity: 1 ULP / 2 -> 1, -1 ULP / 2 -> 0
    assert_eq!(RecipTrait::new(TWO).mul(f(1)).raw, 1);
    assert_eq!(RecipTrait::new(TWO).mul(f(-1)).raw, 0);
}

// ------------------------------------------------------------------ panics

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_overflow_panics() {
    let _ = wide_from(MAX).add(wide_mul(f(0xffffffff), f(1))).add(wide_mul(f(1), f(1))).narrow();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_underflow_panics() {
    let _ = wide_from(MIN).sub(wide_mul(f(1), f(1))).narrow();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_w16_positive_extreme_panics() {
    let p = wide_mul(MIN, MIN);
    let s4 = p.add(p).add(p.add(p));
    let s8 = s4.add(s4);
    let _ = s8.add(s8).narrow(); // 2^130
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_w16_negative_extreme_panics() {
    let p = wide_mul(MIN, MIN);
    let s4 = p.add(p).add(p.add(p));
    let s8 = s4.add(s4);
    let _ = s8.neg().sub(s8).narrow(); // -2^130
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_triple_overflow_panics() {
    let frac = wide_mul(f(0xffffffff), f(0x100000001)).mul(f(1)); // 2^64 - 1
    let one = wide_mul(f(1), f(1)).mul(f(1));
    let _ = wide_from(MAX).lift().add(frac).add(one).narrow();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_triple_underflow_panics() {
    let one = wide_mul(f(1), f(1)).mul(f(1));
    let _ = wide_from(MIN).lift().sub(one).narrow();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_t16_positive_extreme_panics() {
    let t = wide_mul(MIN, MIN).mul(MIN).neg(); // 2^189
    let t4 = t.add(t).add(t.add(t));
    let t8 = t4.add(t4);
    let _ = t8.add(t8).narrow(); // 2^193
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_t16_negative_extreme_panics() {
    let t = wide_mul(MIN, MIN).mul(MIN); // -2^189
    let t4 = t.add(t).add(t.add(t));
    let t8 = t4.add(t4);
    let _ = t8.add(t8).narrow(); // -2^193
}

#[test]
#[should_panic(expected: 'Fixed: sqrt negative')]
fn test_wide_sqrt_negative_panics() {
    let _ = wide_mul(ONE, NEG_ONE).sqrt();
}

#[test]
#[should_panic(expected: 'Fixed: sqrt negative')]
fn test_wide_sqrt_negative_discriminant_panics() {
    let _ = wide_mul(int(2), int(2)).sub(wide_mul(int(4), int(4))).sqrt();
}

#[test]
#[should_panic(expected: 'Fixed: sqrt negative')]
fn test_wide_sqrt_w3_negative_panics() {
    let _ = wide_mul(f(1), f(1)).sub(wide_mul(f(1), f(1))).sub(wide_mul(f(1), f(1))).sqrt();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_wide_sqrt_overflow_panics() {
    let _ = wide_mul(MIN, MIN).sqrt(); // 2^63
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot2_overflow_panics() {
    let _ = dot2(MAX, ONE, f(1), ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot3_overflow_panics() {
    let _ = dot3(MIN, ONE, ZERO, ZERO, f(-1), ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot4_overflow_panics() {
    let _ = dot4(MIN, MIN, MIN, MIN, MIN, MIN, MIN, MIN);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot2_add_overflow_panics() {
    let _ = dot2_add(MAX, ONE, ZERO, ZERO, f(1));
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot3_add_overflow_panics() {
    let _ = dot3_add(MIN, ONE, ZERO, ZERO, ZERO, ZERO, f(-1));
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_add_overflow_panics() {
    let _ = mul_add(MAX, ONE, f(1));
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_sub_overflow_panics() {
    let _ = mul_sub(MAX, ONE, MIN, ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_det3_overflow_panics() {
    let big = int(2048);
    let _ = det3(big, ZERO, ZERO, ZERO, big, ZERO, ZERO, ZERO, big); // 2^33
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm_squared_overflow_panics() {
    let _ = norm3_squared(int(40000), int(40000), ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm2_overflow_panics() {
    let _ = norm2(MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm3_overflow_panics() {
    let _ = norm3(MIN, ZERO, ZERO); // 2^31 exactly
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm4_overflow_panics() {
    let _ = norm4(MAX, MAX, MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm4_sum_of_squares_2_pow_128_panics() {
    let _ = norm4(MIN, MIN, MIN, MIN);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm4_wide_sum_of_squares_2_pow_128_panics() {
    let _ = norm4_wide(MIN, MIN, MIN, MIN);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm_to_fixed_overflow_panics() {
    let _ = norm2_wide(MIN, MIN).to_fixed();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance_overflow_panics() {
    let _ = distance2(MIN, ZERO, MAX, ZERO); // 2^64 - 1
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance3_sum_above_2_pow_128_panics() {
    let _ = distance3(MIN, MIN, MIN, MAX, MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance4_overflow_panics() {
    let _ = distance4(MIN, MIN, MIN, MIN, MAX, MAX, MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance_squared_overflow_panics() {
    let _ = distance2_squared(int(-30000), ZERO, int(30000), ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance3_squared_overflow_panics() {
    let _ = distance3_squared(MIN, MIN, MIN, MAX, MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance4_squared_overflow_panics() {
    let _ = distance4_squared(MIN, MIN, MIN, MIN, MAX, MAX, MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_normalize2_zero_panics() {
    let _ = normalize2(ZERO, ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_normalize3_zero_panics() {
    let _ = normalize3(ZERO, ZERO, ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_normalize4_zero_panics() {
    let _ = normalize4(ZERO, ZERO, ZERO, ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_normalize4_sum_of_squares_2_pow_128_panics() {
    let _ = normalize4(MIN, MIN, MIN, MIN);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_norm_recip_zero_panics() {
    let _ = norm2_wide(ZERO, ZERO).recip();
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_recip_new_zero_panics() {
    let _ = RecipTrait::new(ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_recip_mul_overflow_panics() {
    let _ = RecipTrait::new(HALF).mul(MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_recip_mul_negative_overflow_panics() {
    let _ = RecipTrait::new(f(-1)).mul(MAX);
}

// ------------------------------------------------------------------ properties (seeded fuzzing)

fn sq(v: i64) -> u128 {
    let w: i128 = v.into();
    (w * w).try_into().unwrap()
}

/// Keeps 46 bits: three or four products of such values fit an `i128` with room to spare.
fn small(x: i64) -> i64 {
    x % 0x400000000000
}

#[test]
#[fuzzer(runs: 256, seed: 201)]
fn fuzz_dot_is_floor_of_exact_sum(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64) {
    let (a, b, c, d, e, g) = (small(a), small(b), small(c), small(d), small(e), small(g));
    let (a_, b_, c_): (i128, i128, i128) = (a.into(), b.into(), c.into());
    let (d_, e_, g_): (i128, i128, i128) = (d.into(), e.into(), g.into());
    let want2: i64 = floor_shift(a_ * b_ + c_ * d_).try_into().unwrap();
    let want3: i64 = floor_shift(a_ * b_ + c_ * d_ + e_ * g_).try_into().unwrap();
    let want4: i64 = floor_shift(a_ * b_ + c_ * d_ + e_ * g_ + a_ * g_).try_into().unwrap();
    let wantsub: i64 = floor_shift(a_ * b_ - c_ * d_).try_into().unwrap();
    let wantadd: i64 = floor_shift(a_ * b_ + c_ * d_ + e_ * ONE_I128).try_into().unwrap();
    assert_eq!(dot2(f(a), f(b), f(c), f(d)).raw, want2);
    assert_eq!(dot3(f(a), f(b), f(c), f(d), f(e), f(g)).raw, want3);
    assert_eq!(dot4(f(a), f(b), f(c), f(d), f(e), f(g), f(a), f(g)).raw, want4);
    assert_eq!(mul_sub(f(a), f(b), f(c), f(d)).raw, wantsub);
    assert_eq!(dot2_add(f(a), f(b), f(c), f(d), f(e)).raw, wantadd);
    // the accumulator API composes to the same values
    assert_eq!(wide_mul(f(a), f(b)).add(wide_mul(f(c), f(d))).narrow().raw, want2);
    assert_eq!(wide_mul(f(a), f(b)).sub(wide_mul(f(c), f(d))).narrow().raw, wantsub);
    assert_eq!(wide_mul(f(c), f(d)).neg().add(wide_mul(f(a), f(b))).narrow().raw, wantsub);
    assert_eq!(wide_mul(f(a), f(b)).narrow(), f(a) * f(b));
    assert_eq!(mul_add(f(a), f(b), f(c)), f(a).mul_add(f(b), f(c)));
}

#[test]
#[fuzzer(runs: 256, seed: 202)]
fn fuzz_lift_and_unit_mul_are_neutral(a: i64, b: i64, c: i64, d: i64) {
    let (a, b, c, d) = (small(a), small(b), small(c), small(d));
    let w = wide_mul(f(a), f(b)).sub(wide_mul(f(c), f(d)));
    assert_eq!(w.lift().narrow(), w.narrow());
    assert_eq!(w.mul(ONE).narrow(), w.narrow());
    assert_eq!(w.mul(NEG_ONE).narrow(), w.neg().narrow());
}

#[test]
#[fuzzer(runs: 256, seed: 203)]
fn fuzz_det3_is_floor_of_exact_determinant(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64) {
    // 9 entries of 38 bits: six triple products stay below 2^117.
    let m = 0x4000000000_i64;
    let (a, b, c, d, e, g) = (a % m, b % m, c % m, d % m, e % m, g % m);
    let (h, i, j) = ((a + d) % m, (b - e) % m, (c + g) % m);
    let (a_, b_, c_): (i128, i128, i128) = (a.into(), b.into(), c.into());
    let (d_, e_, g_): (i128, i128, i128) = (d.into(), e.into(), g.into());
    let (h_, i_, j_): (i128, i128, i128) = (h.into(), i.into(), j.into());
    let exact = a_ * (e_ * j_ - i_ * g_) + b_ * (g_ * h_ - j_ * d_) + c_ * (d_ * i_ - h_ * e_);
    let want: i64 = floor_shift(floor_shift(exact)).try_into().unwrap();
    assert_eq!(det3(f(a), f(b), f(c), f(d), f(e), f(g), f(h), f(i), f(j)).raw, want);
    // swapping two columns flips the sign of the exact determinant
    let swapped = det3(f(d), f(e), f(g), f(a), f(b), f(c), f(h), f(i), f(j)).raw;
    let want_swapped: i64 = floor_shift(floor_shift(-exact)).try_into().unwrap();
    assert_eq!(swapped, want_swapped);
}

#[test]
#[fuzzer(runs: 256, seed: 204)]
fn fuzz_norm_is_integer_root_of_sum_of_squares(x: i64, y: i64, z: i64, sel: u8) {
    let m: i64 = if sel % 2 == 0 {
        0x1000000000000
    } else {
        0x2000000000000000
    };
    let (x, y, z) = (x % m, y % m, z % m);
    let s3 = sq(x) + sq(y) + sq(z);
    let r3: u128 = norm3(f(x), f(y), f(z)).raw.try_into().unwrap();
    assert!(r3 * r3 <= s3 && s3 < (r3 + 1) * (r3 + 1));
    let s2 = sq(x) + sq(y);
    let r2: u128 = norm2(f(x), f(y)).raw.try_into().unwrap();
    assert!(r2 * r2 <= s2 && s2 < (r2 + 1) * (r2 + 1));
    let s4 = s3 + sq(x / 2);
    let r4: u128 = norm4(f(x), f(y), f(z), f(x / 2)).raw.try_into().unwrap();
    assert!(r4 * r4 <= s4 && s4 < (r4 + 1) * (r4 + 1));
    assert_eq!(norm3_wide(f(x), f(y), f(z)).to_fixed(), norm3(f(x), f(y), f(z)));
    assert_eq!(wide_mul(f(x), f(x)).sqrt(), f(x).abs());
    assert_eq!(wide_mul(f(x), f(x)).add(wide_mul(f(y), f(y))).sqrt(), norm2(f(x), f(y)));
}

#[test]
#[fuzzer(runs: 256, seed: 205)]
fn fuzz_distance_is_norm_of_difference(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64) {
    let (a, b, c, d, e, g) = (a / 8, b / 8, c / 8, d / 8, e / 8, g / 8);
    assert_eq!(distance2(f(a), f(b), f(c), f(d)), norm2(f(a - c), f(b - d)));
    assert_eq!(distance3(f(a), f(b), f(c), f(d), f(e), f(g)), norm3(f(a - d), f(b - e), f(c - g)));
    assert_eq!(
        distance4(f(a), f(b), f(c), f(d), f(e), f(g), f(a), f(b)),
        norm4(f(a - e), f(b - g), f(c - a), f(d - b)),
    );
    // 40 bits: the squared differences fit the scalar range
    let m = 0x10000000000_i64;
    let (a, b, c, d) = (a % m, b % m, c % m, d % m);
    assert_eq!(distance2_squared(f(a), f(b), f(c), f(d)), norm2_squared(f(a - c), f(b - d)));
    assert_eq!(
        distance3_squared(f(a), f(b), f(c), f(d), f(a), f(b)),
        norm3_squared(f(a - d), f(b - a), f(c - b)),
    );
    assert_eq!(
        distance4_squared(f(a), f(b), f(c), f(d), f(d), f(c), f(b), f(a)),
        norm4_squared(f(a - d), f(b - c), f(c - b), f(d - a)),
    );
}

#[test]
#[fuzzer(runs: 256, seed: 206)]
fn fuzz_recip_mul_is_within_one_ulp_of_the_quotient(x: i64, d: i64, sel: u8) {
    let d = if sel % 2 == 0 {
        d % 0x1000000000000
    } else {
        d
    };
    let x = small(x);
    if d != 0 {
        // exact on representable quotients
        assert_eq!(RecipTrait::new(f(d)).mul(f(d)), ONE);
        let num: i128 = x.into() * ONE_I128;
        let trunc: i128 = num / d.into();
        let fits: Option<i64> = trunc.try_into();
        if let Some(t) = fits {
            if t > I64_MIN + 1 && t < I64_MAX - 1 {
                // |round-to-nearest - trunc| <= 1
                assert!(RecipTrait::new(f(d)).mul(f(x)).abs_diff_eq(f(t), EPSILON));
            }
        }
    }
}

#[test]
#[fuzzer(runs: 256, seed: 207)]
fn fuzz_normalize_has_unit_length(x: i64, y: i64, z: i64, w: i64, sel: u8) {
    // lengths >= 1.0 (raw 2^32): the floor of the length costs at most 2^-32 relative
    let m: i64 = if sel % 2 == 0 {
        0x100000000000
    } else {
        0x4000000000000000
    };
    let (x, y, z, w) = (x % m + ONE_RAW, y % m, z % m, w % m);
    let (x, y, z, w) = (f(x), f(y), f(z), f(w));
    if norm2_wide(x, y).to_fixed() >= ONE {
        let (nx, ny) = normalize2(x, y);
        assert!(norm2(nx, ny).abs_diff_eq(ONE, f(6)));
        assert!(nx.abs() <= f(ONE_RAW + 1) && ny.abs() <= f(ONE_RAW + 1));
        let (nx, ny, nz) = normalize3(x, y, z);
        assert!(norm3(nx, ny, nz).abs_diff_eq(ONE, f(6)));
        assert_eq!(nx.is_negative(), x.is_negative() && nx != ZERO);
        let (nx, ny, nz, nw) = normalize4(x, y, z, w);
        assert!(norm4(nx, ny, nz, nw).abs_diff_eq(ONE, f(6)));
        // composing Norm + Recip by hand gives the same bits as the fused kernel
        let r = norm4_wide(x, y, z, w).recip();
        assert_eq!((r.mul(x), r.mul(y), r.mul(z), r.mul(w)), (nx, ny, nz, nw));
    }
}

// floor((a0 a1 + a2 a3) / 2^32)
#[test]
fn test_dot2_table() {
    let cases: Span<(i64, i64, i64, i64, i64)> = array![
        (12345, 4737066750222434685, -4294967296, -4294967296, 13620018906791),
        (9223372036854775807, 215, -35309099456, -24082056807885257, 197980022514157543),
        (-4294967296, -4611686018427387904, -25, -4294967297, 4611686018427387929),
        (1074265560228235993, 1846664441, 38331192898, 2147483647, 461891315081165444),
        (-3102711014359486207, 76, -735800975, 7, -54902871395),
        (-7708719475, 382301273995, -443413125, 0, -686164311172),
        (-199028784496640, -42773742230, -7160793523, 7687900903, 1982122397268774),
        (-7287679207429718163, 1079442164, 4294967296, -10737418240, -1831592121236631656),
        (308838168, -2147483649, 91046662, -129001878010125, -2734794656157),
        (446741, -3, -207, 4374410145, -211),
        (41, -406833062910792646, 4294967296333, -10737418240, -10741301892193),
        (-166662944, 2147483648, -65214391528, 170, -83334054),
        (0, 271349949, 2147483648, 9223372036854775807, 4611686018427387903),
        (319344, 12345, 6888746424, -847817, -1359823),
        (8759513866048863804, -3541973774, -1, 1688271588461295319, -7223796189814502417),
        (4611686018427387904, -1004737747, -1, 387594680089, -1078828941105430619),
        (-40456437505736, 2147483648, 188711185619145, -93960722585477, -4128442667488693248),
        (447756, -6882891337, 7569117355321631413, 687615981, 1211801091111387894),
        (-9223372036854775807, 77364769, 204647241898, 199033079463936, -156656018522002094),
        (3, -35093008289353281, -9223372036854775807, -2147483648, 4611686018402875720),
        (199033079463936, -227216640, 198, -663213, -10529446314241),
        (-30, 5837159629474836612, 159901, 28081438134, -40771043542),
        (291530919437, 29187875707118, 1, -9223372036854775807, 1981192971099389),
        (12345, -1023792586, -6789876614, 20526379973749409, -32449976390658805),
        (1750709188, 1950723894, 13493037705, -4294967297, -12697886079),
        (3, 716636143319648922, -1592863293, 195, 500564491),
        (60010875542419641, -7859578942, 4611686018427387904, -207, -109817173407224485),
        (6442450944, -4485063673, -70312818931458185, -53000876917, 867676230375356978),
        (989425, -43557214291, -2147483648, 2486152858904084076, -1243076429462076247),
        (-700796, 137, 979615521241, -2147483649, -489807760849),
        (-60724164834, 4294967296, -638395, 343946364588, -60775288306),
        (31323433598, -40462465662563068, -54, -4611686018427387904, -295094937868789849),
        (-61025038, 62065342709455827, -4457045171034054295, -329144, -540290545102380),
        (199033079463936, -2147483649, 32951, 4611686018427387904, -64135672935685),
        (-99861790988, 6877684135, -4294967296, -11106454529681504, 11106294617438118),
        (3, -206367631, 890748273882, 1753579222, 363680921753), (-3, 761817, 3, -1004140825, -1),
        (-9223372036854775808, -2147483649, 13493037705, 12345, 4611686020574910334),
        (65432875154551200, -10112352752, -14957883080076, -24285126628, -153974876984886776),
        (2147483647, -2147483648, 55776179627, 189, -1073739370),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, w0) = *case;
        let g0 = dot2(f(a0), f(a1), f(a2), f(a3));
        assert!(g0.raw == w0, "dot2 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// floor(sum / 2^32)
#[test]
fn test_dot3_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64, i64)> = array![
        (-628864, 776634178715, 741802, 4611686018427387904, -145203775192072, 0, 796503718812995),
        (4294967296333, 3, -125, 3, -3337189588997, -47371722162, 36807828122929),
        (-708280, 3, -3337189588997, -184, -1, 3848662005377461057, -895943484),
        (6442450944, 4294967296, 51608242369, -45858007570, -1, 975917854498, -544586464320),
        (
            -4287718002,
            4038101537109327111,
            137281794671,
            13493037705,
            -3927363283659558967,
            1577853303,
            -5474091025866163484,
        ),
        (
            6442450944,
            4294967296333,
            130119454484607,
            -2147483649,
            3,
            -236617835436505,
            -58617276493376,
        ),
        (
            1,
            -199028784496640,
            2150626792,
            -2674032838095577377,
            0,
            -2147483649,
            -1338973330402827355,
        ),
        (1614092682753399235, 3, -84, 47, -18859040801751050, 1579147428, -6933976182330908),
        (
            3,
            2607937323349329031,
            -28157350065689109,
            -390809551740,
            -2147483648,
            -63129769728274742,
            2593670858390514651,
        ),
        (161344, 1, 12345, -4294967296, 8525879099011545107, 0, -12345),
        (
            1028343,
            -22050231102,
            2627213282849197975,
            -2147483649,
            -732331626642,
            355863,
            -1313606642102252160,
        ),
        (
            -4294967296,
            -98765,
            -1143167265,
            3224319657546542849,
            41955,
            2147483647,
            -858199010696891628,
        ),
        (
            -2147483648,
            -438692915379,
            -1,
            -733438181712,
            2147483648,
            -2299586608881077140,
            -1149793085094080710,
        ),
        (
            -1605861104,
            31,
            4244175419,
            -4294967296,
            2147483647,
            -3733038980797127929,
            -1866519493773573527,
        ),
        (
            -5918262925,
            -106080941188814,
            2018244788013947261,
            -4868926829,
            3460213734505458163,
            2147483647,
            -557700630969826027,
        ),
        (
            -4294967296,
            65065850759,
            -20513337629,
            1073105193028102384,
            485616808121,
            -2147483648,
            -5125294080546250758,
        ),
        (0, 87, 2147483648, -215, -32013246025307709, -2098018621, 15637927288131171),
        (
            6442450944,
            -10670556134,
            -57878037395312219,
            -558878649868,
            60853532055205957,
            -800819464257,
            -3815138156255482865,
        ),
        (
            1376346756,
            199033079463936,
            65528632,
            2305473242309117572,
            16,
            -809912,
            35238556148106668,
        ),
        (
            42948091120,
            21,
            683881606,
            199033079463936,
            -4234292176930514701,
            3665629109,
            -3613812975749708977,
        ),
        (
            63106077507331777,
            3325468300,
            61861361893572034,
            7727216690,
            33043632843,
            -4337453237989725,
            126787507000449275,
        ),
        (5086439033, -4294967296, 1, -199028784496640, -1420543284, 13493037705, -9549253719),
        (-52737268585, 0, -4294967296, 168181582, -7899507305597684890, -475044, 873723259695328),
        (
            -57206406195,
            -1047598,
            13493037705,
            -2147483648,
            -3337189588997,
            21712191962,
            -16877105719971,
        ),
        (-998098, 25965948729, -186291107145068780, -1, 3, -173152301950390, 37219163),
        (
            1,
            685764592546,
            -11304579192948,
            118663034122240,
            -582579271716923253,
            39,
            -312327334943912867,
        ),
        (-2147483649, -432771441356, 670305724459, -74, -9223372036854775808, 232, -281830497107),
        (2670031059700993346, -112, -7591487411, 162, 4013960012322603114, 117, 39718542603),
        (
            2807640190,
            -808248,
            -10737418240,
            24261420517944048,
            -55324448681548,
            49235383473,
            -61287763446155066,
        ),
        (
            -124,
            9223372036854775806,
            6442450944,
            0,
            309843347687,
            199033079463936,
            14358184287190915,
        ),
        (
            254237900,
            -43056279815,
            1240985487,
            4232165987911660295,
            3750841842292783329,
            2147483647,
            3098260629324697630,
        ),
        (
            4294967297,
            213592737346667,
            0,
            112847229601,
            -4294967296,
            3994999083683960740,
            -3994785490946564343,
        ),
        (
            4037771368397679802,
            1719043696,
            1477838208,
            18267036538,
            -97,
            -7421731756,
            1616102048132813150,
        ),
        (
            -62966469092133709,
            52424962371,
            -65,
            163658762931,
            1,
            2230729670488680573,
            -768577393740211892,
        ),
        (
            0,
            878377511165,
            -9223372036854775808,
            0,
            -48415159548398930,
            323417230482,
            -3645731325840423764,
        ),
        (4294967297, 2147483648, -4222510393, 861284265, 206596765402259, -134, 1294283734),
        (
            -2147483648,
            1040607,
            4294967296,
            -1930282315213850079,
            239720265568874,
            -139250205,
            -1930290087356466601,
        ),
        (47488868822779, 8271, 4294967296, 107, 8639895031623710891, 588048, 1182936454735964),
        (13493037705, -2147483649, 0, -98765, -587752916, -7038560815, -5783313700),
        (
            199033079463936,
            -7050521645,
            397843427,
            1467675265222,
            -2147483648,
            937284781,
            -326592741226309,
        ),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, a4, a5, w0) = *case;
        let g0 = dot3(f(a0), f(a1), f(a2), f(a3), f(a4), f(a5));
        assert!(g0.raw == w0, "dot3 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// floor(sum / 2^32)
#[test]
fn test_dot4_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64, i64, i64, i64)> = array![
        (
            177234479304197,
            -3337189588997,
            4428974304445841937,
            -1521171297,
            2147483647,
            2147483648,
            8334128522,
            4294967297,
            -1706344449383283330,
        ),
        (
            13493037705,
            -218,
            231826960716343,
            13493037705,
            4855387539621298031,
            -228,
            -4611686018427387904,
            12345,
            714792783772970,
        ),
        (
            -699714375027,
            -138128061573031,
            1050955077,
            4294967296333,
            -196,
            106,
            5216149501,
            496054607,
            22504177569049639,
        ),
        (
            0,
            28479008869,
            4294967297,
            2147483648,
            -4611686018427387904,
            -3,
            9223372036854775806,
            -273032,
            -586326386671616,
        ),
        (
            -3452736964413419403,
            -565344,
            -54555557628818747,
            6442450944,
            4611686018427387904,
            252,
            7812549,
            -98765,
            -81378584139734630,
        ),
        (
            51519632142,
            2147483647,
            99871,
            18,
            -29419283434,
            -151132,
            2920525096673004880,
            4294967297,
            2920525123113843887,
        ),
        (
            45361383824,
            -855677670,
            1,
            -252,
            1,
            -30051697839113227,
            -54201938400137239,
            1735056045,
            -21896194600651661,
        ),
        (
            -30878247666934265,
            542933757394,
            881435963146,
            4294967296,
            -939578246033,
            -449037,
            -199028784496640,
            -3208903280,
            -3903219610748628258,
        ),
        (
            -1,
            1960520977560321251,
            4611686018427387904,
            36,
            8583236093,
            -24464581752,
            13493037705,
            1169132226,
            -7019834640,
        ),
        (
            6442450944,
            9223372036854775806,
            395645643676,
            -40950552556833954,
            -512599327352,
            0,
            1357586324,
            -5155869893277033620,
            8433050407335528985,
        ),
        (
            6442450944,
            12345,
            -10737418240,
            -1627023412502857465,
            28492878299730856,
            -846428173067,
            -4294967297,
            4294967296,
            -1547658833859720368,
        ),
        (
            -1593872588,
            4370647252093485521,
            20716133831,
            -3,
            -199846360001721178,
            -1723994862,
            3,
            -1078538836,
            -1541739504108429568,
        ),
        (
            -689870,
            -384707902608,
            6442450944,
            -1047389550982231237,
            4294967296333,
            1058289017,
            -667275118283,
            199033079463936,
            -1602005464378889387,
        ),
        (
            598273,
            -9223372036854775808,
            -539524714525231597,
            -3,
            -10737418240,
            4294967296,
            4294967297,
            6442450944,
            -1284785402653539,
        ),
        (
            3590924983,
            4292001530,
            2147483647,
            4611686018427387904,
            -193,
            -606925815,
            -11674931555,
            -29478123102,
            2305843091858243896,
        ),
        (
            191235082797066,
            -11674931555,
            -134340125522242,
            -2147483649,
            2147483648,
            -9223372036854775807,
            -138628994,
            -2147483648,
            -4612138679145832495,
        ),
        (
            0,
            -562901674864,
            150,
            199033079463936,
            880893693,
            4388106766516138166,
            0,
            -1427977235743641208,
            899996509511150572,
        ),
        (
            -961700,
            -830034118214,
            -1124784825,
            -1353001352,
            1932444605488491138,
            3,
            976293665,
            -243624753191582,
            -55376716369091,
        ),
        (
            -1957720940,
            -4611686018427387904,
            -2147483649,
            -594959741,
            4294967297,
            46129672166,
            -2147483648,
            2147483648,
            2102086898352004783,
        ),
        (
            5878127075667719198,
            1,
            879983,
            4294967296333,
            8859578227,
            -2080536437,
            -9223372036854775807,
            -199084,
            427527591477884,
        ),
        (
            -1000350559,
            -11,
            101735988896192,
            -2147483649,
            -122,
            -98765,
            143,
            -551079,
            -50867994471781,
        ),
        (
            153289870448248,
            1200205253,
            1018017245,
            -6011738430970749391,
            -3,
            -160,
            -714763,
            9223372036854775806,
            -1426428077024617169,
        ),
        (
            -51788026088,
            -10737418240,
            5989400221,
            -13418285871,
            3974904097206760865,
            2137942115,
            -4411389384,
            2633433489697053543,
            -726195329733438765,
        ),
        (
            9035944564513852,
            497086178078,
            -4802395888,
            -4294967297,
            2147483647,
            -11674931555,
            -181816429186,
            583068,
            1045792164361864827,
        ),
        (
            -6714356769512107609,
            -4294967297,
            3,
            -4611686018427387904,
            199033079463936,
            -1810576414,
            141,
            4294967296,
            6714272863932589112,
        ),
        (
            -55032184249993,
            3,
            4294967297,
            18680836647881079,
            -145,
            -212214668468252,
            93089285730022,
            -371269095,
            18672789758766812,
        ),
        (
            2147483648,
            199033079463936,
            -224795037,
            9223372036854775806,
            -1,
            -1529412789,
            -169373643943743,
            -1,
            -482644149569283573,
        ),
        (
            -130,
            -60070600494810419,
            -4611686018427387904,
            12345,
            -298489,
            -163739,
            2147483647,
            -418935,
            -13253524810781,
        ),
        (
            -16787635874,
            2147483647,
            0,
            -39334877283966,
            1462085794,
            2147483647,
            788278081973,
            -201,
            -7662811928,
        ),
        (
            -481597616250,
            59013740658,
            -4294967297,
            -4893300450655304937,
            -555742,
            3,
            -467064949,
            9223372036854775806,
            3890279494012116466,
        ),
        (
            -4741742917978785634,
            584022,
            -4294967297,
            -319501086450,
            1,
            -749395,
            943136234877,
            12345,
            -644454249200209,
        ),
        (
            117442351917739,
            683462,
            159,
            -49098801135350242,
            -580822958,
            1416389720039288629,
            129792408,
            -38510062354807,
            -191544320603614071,
        ),
        (
            -50727362779,
            -36274390713,
            -3337189588997,
            1,
            1869712043,
            -4294967297,
            -1,
            -2040106064391980853,
            427037926375,
        ),
        (
            -4611686018427387904,
            -4294967296,
            -49,
            4611686018427387904,
            -32,
            739583,
            47078008532,
            -1,
            4611685965814038517,
        ),
        (
            577932476,
            -9223372036854775808,
            -33,
            9223372036854775807,
            874534,
            41952091283523815,
            6442450944,
            -128,
            -1241092070511012183,
        ),
        (
            0,
            16635724092,
            455524,
            -6898292361714548747,
            1493815199,
            -763248,
            -60,
            -983686298428,
            -731632516453692,
        ),
        (
            850220852,
            4294967296,
            -17127370457188652,
            2147483647,
            185,
            -36982303387,
            -604051384,
            -7393284065222342337,
            1031240152097643009,
        ),
        (
            -248676,
            200794395515827,
            -4294967296,
            -17204868973507270,
            5280359120850909252,
            -2836133059,
            -897672000304,
            859083610,
            -3469620723643412544,
        ),
        (
            190,
            4611686018427387904,
            -2364811909,
            -4611686018427387904,
            700653706878210865,
            -1705398995,
            3,
            86134440851,
            2260989687781105453,
        ),
        (
            -326306,
            12345,
            4294967296333,
            -565288,
            -2147483649,
            -7152840171197648996,
            55196006220,
            -1044050,
            3576420086685519455,
        ),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, a4, a5, a6, a7, w0) = *case;
        let g0 = dot4(f(a0), f(a1), f(a2), f(a3), f(a4), f(a5), f(a6), f(a7));
        assert!(g0.raw == w0, "dot4 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// floor((a0 a1 + a2 a3 + a4 2^32) / 2^32)
#[test]
fn test_dot2_add_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64)> = array![
        (
            925238,
            -3337189588997,
            -224,
            -6488726508549540723,
            -3098099950912981593,
            -3098099613218432756,
        ),
        (
            -629165839778187996,
            2147483647,
            13493037705,
            19055130851588888,
            58873319991053,
            -254660587323949367,
        ),
        (12345, -2147483648, -2147483649, -2652237595209578887, -211, 1326118798222305246),
        (
            823813473015,
            -23863996118,
            -4294967297,
            2147483648,
            -4611686018427387904,
            -4611690597904608218,
        ),
        (-10737418240, 947392, 965212828464, -824977794, 4294967296, -181105588199),
        (171046869511044, -4294967297, -189, 2147483648, -567788, -171046870118752),
        (14, 199033079463936, -3262362825, 649361, 6442450944, 6442606477),
        (6442450944, -509588050, 4294967296, -648812192116, -247536240033565, -248185816607756),
        (
            -529567305068085426,
            -61846838055,
            -27292248649,
            6442450944,
            -75937989510,
            7625683875239571917,
        ),
        (-236973093621538, -635952, -2147483648, 6442450944, -4294967297, 27572203125),
        (-1999793063, -4294967297, -20153648873, -11674931555, 0, 56783090574),
        (7171727065, -1545249047, -2147483649, -4294967297, 1, -432769853),
        (
            359415987,
            -254664865973,
            199033079463936,
            -549988826851,
            -935286112872,
            -25487988822349200,
        ),
        (-833057, -1385715108, -3337189588997, -43391167843, -1, 33714937682835),
        (4114452587, -1402492255, 71663760636278, -11674931555, 7895614938445019, 7700811296594346),
        (
            -4046143140731009154,
            -4294967296,
            -4294967296,
            9223372036854775806,
            5981738997975287792,
            804510101851521140,
        ),
        (-134, 55, 9223372036854775807, -767645, -4294967297, -1648509379936257),
        (2558834223299021726, 8031221765, -67, 13493037705, -2147483649, 4784801299209380625),
        (
            1795879029,
            -2147483648,
            -3337189588997,
            6442450944,
            -60627312842816008,
            -60632319525139018,
        ),
        (222574687914764, 262353764952, -11674931555, 4513566774, -32028066170, 13595707039901716),
        (60775442822, 601457, -2147483649, -28661177376, 4294967296333, 4309306395876),
        (
            -4611686018427387904,
            2147483647,
            240014639,
            -23944079405,
            -21955286358723773,
            -2327798295836737213,
        ),
        (6442450944, -4294967296, -839649375, 1973061257, 4794646580164157007, 4794646573335980273),
        (-4853433004, -1, -1967973499949009920, 187, -7498987255, -93183235615),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, a4, w0) = *case;
        let g0 = dot2_add(f(a0), f(a1), f(a2), f(a3), f(a4));
        assert!(g0.raw == w0, "dot2_add #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// floor((a0 a1 + a2 a3 + a4 a5 + a6 2^32) / 2^32)
#[test]
fn test_dot3_add_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64, i64, i64)> = array![
        (
            3073292588822568964,
            184,
            8045663185824195046,
            -4637869689,
            1866794883,
            20304583393171506,
            1094971259,
            -8679188870561469172,
        ),
        (
            -32209304594,
            39637575207102,
            -628809976,
            -2147483648,
            -3,
            275072509136,
            1711630022,
            -297252561771276,
        ),
        (
            -67308969282,
            -2147483649,
            -10737418240,
            1621477259,
            -4611686018427387904,
            -1,
            -2478311954,
            28196221379,
        ),
        (
            -844239377,
            -5911375240,
            7795413441,
            -6334260119,
            39988310083,
            9707122098,
            -721267,
            80042693281,
        ),
        (
            590399220878,
            7398869814357048,
            -4294967297,
            -59500159307753741,
            -721596241491,
            -3337189588997,
            363239,
            1077131907370260298,
        ),
        (
            -4611686018427387904,
            -207677841,
            -98765,
            2086047689616439150,
            1794310356,
            4294967296333,
            -3337189588997,
            222942871172207958,
        ),
        (
            -7654233166116072,
            677541695,
            51707985260,
            1783791473,
            1,
            142316651706589146,
            -23877643930,
            -1207476548947264,
        ),
        (-1, 160408728, 9223372036854775806, -139, 1130022341, 3, -290703, -298500517775),
        (
            2004395641,
            -11490569546112928,
            -5594448989063521620,
            -268898667,
            256138052547401,
            -546092999,
            4301304958237834926,
            4646166339238340875,
        ),
        (147, -146, -4278280318247648, 288028093, 12345, 4294967297, -114, -286909034785762),
        (
            6463935465,
            -2147483649,
            -3337189588997,
            199033079463936,
            230882363810409,
            -214230954,
            -466619563,
            -154660222746299623,
        ),
        (-2147483649, 236, -1, -629556418738, 0, 3688949174234268633, -4294967296, -4294967268),
        (
            0,
            -4368054887279671045,
            9223372036854775807,
            12345,
            -2001401360,
            -725076499752,
            2853414530920577,
            2880263093189042,
        ),
        (
            -1675658461,
            -10737418240,
            906259028949,
            3,
            148,
            -48237011123609330,
            -524933173464,
            -522406222722,
        ),
        (395902106, 199033079463936, 4294967297, 0, 692673423813, 937797458137, 0, 169590346397441),
        (
            -6232410616513104428,
            1262831044,
            11419908987068,
            12345,
            -263874879031870,
            197036,
            -11674931555,
            -1832489321819331592,
        ),
        (
            -229019,
            32540977841,
            87008304378745,
            -4294967297,
            -3337189588997,
            8010652275,
            607890673143,
            -92624692278716,
        ),
        (
            -120,
            -1222809769,
            -287836,
            1296338994273857454,
            -4294967297,
            -10737418240,
            -184039746795952,
            -270905813097070,
        ),
        (
            1015927306371,
            232874374905304,
            -241833,
            4611686018427387904,
            213767630,
            -4294967296,
            7065483453488104901,
            7120307660847414339,
        ),
        (
            498681,
            199033079463936,
            984092510,
            6442450944,
            -1380882590,
            -660085135715,
            -131926220232110533,
            -131925983421447134,
        ),
        (
            -1,
            -8016191931589755713,
            172035232359703,
            1219356689,
            -2147483649,
            -10737418240,
            6188189061431963858,
            6188237910089353846,
        ),
        (
            -2147483649,
            -257954792,
            117446034120873,
            276724036611083,
            -9223372036854775807,
            -981707,
            -849864728,
            7569136864432822994,
        ),
        (
            -41,
            -11674931555,
            232031544364,
            -4294967297,
            -29,
            9223372036854775807,
            -11674931555,
            -305983501654,
        ),
        (
            -527300,
            -9223372036854775807,
            -4294967296,
            -2147483648,
            -870720,
            -39504216959389795,
            -25294080682,
            1140353682671470,
        ),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, a4, a5, a6, w0) = *case;
        let g0 = dot3_add(f(a0), f(a1), f(a2), f(a3), f(a4), f(a5), f(a6));
        assert!(g0.raw == w0, "dot3_add #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// floor((a0 a1 + a2 2^32) / 2^32)
#[test]
fn test_mul_add_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (921105, -34402571775, -5762038467323456399, -5762038467330834426),
        (-4294967296, -57392821801, -3337189588997, -3279796767196),
        (223319782387702, 45315732, -214509043873246647, -214506687650553542),
        (-3337189588997, 1282140846, 0, -996223437344),
        (5344585270, 658137001, 2177349730737064579, 2177349731556039225),
        (-11674931555, 99097902733512524, -185, -269376028249460952),
        (2147483648, 1995787884, -4294967296, -3297073354),
        (1778494416, 18860707402381392, -254, 7809992599520850),
        (-688310, -522726, -3337189588997, -3337189588914),
        (-1202681838272372540, 2147483648, 81, -601340919136186189),
        (4031045978, 930156, -4294967297, -4294094299),
        (-7051648793, -13219363239099963, 6722252274672563415, 6743956353051936440),
        (-505838, 196777979, -2655337368, -2655360544),
        (250, -11674931555, -10661165587974559, -10661165587975239),
        (3, -4294967297, -4255594962, -4255594966), (771125252, 202104077, 12345, 36298432),
        (-1100647942, -98765, -4294967297, -4294941988),
        (5529058556420833, -2682101126, 174718918102271, -3278041756864287),
        (-4294967296, 6442450944, -11674931555, -18117382499),
        (-4294967296, 67264852689, 2147483648, -65117369041),
        (-6371435247, 63950786588265, -528699249, -94869305958932),
        (-70689411822, 4294967296, -4611686018427387904, -4611686089116799726),
        (-2147483648, -702425, -622178449, -621827237),
        (-32680979527165224, 23, -4294967297, -4469977368),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, w0) = *case;
        let g0 = mul_add(f(a0), f(a1), f(a2));
        assert!(g0.raw == w0, "mul_add #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// floor((a0 a1 - a2 a3) / 2^32)
#[test]
fn test_mul_sub_table() {
    let cases: Span<(i64, i64, i64, i64, i64)> = array![
        (-64239783816209891, 6442450944, 12345, -190252994253197, -96359675177471741),
        (13493037705, -1, -106, 0, -4), (2268333222920637092, 72, 0, -684264, 38025898870),
        (-4294967296, 12345, 4294967296, -11674931555, 11674919210),
        (-3337189588997, -799506, 669678681709, 199033079463936, -31033579167860607),
        (61, 959589193, -2147483649, 9223372036854775806, 4611686020574871564),
        (2873753384404244631, -2147483648, -1, 6409195950, -1436876692202122315),
        (200918400, -1150346426, -17555843868, -18223959258056667, -74491133825472028),
        (12345, -11674931555, -10737418240, 0, -33558),
        (2147483647, 2703985280633257806, 51, 4611686018427387904, 1351992584926225245),
        (-150238431111945, 184, 2147483647, 182, -6436432),
        (9128242474671269302, 275544, -2438095687, 12345, 585623188985259),
        (-641740245883, -48043816280, -2660444047, 1193912497771663794, 739555859236511492),
        (-185, -10737418240, 6442450944, 71503896107553283, -107255844161329462),
        (13493037705, -3337189588997, 2147483647, -62276823720642284, 31127927755524388),
        (5585122647869563788, -371671, -61043878941, -2147483649, -483346919153870),
        (-961086964, 2147483647, -2759336780927389741, 3, 1446830994),
        (224, -3025136139321238124, -36207578900, -199028784496640, -1678016979370359),
        (244880, 61832814941, 384630067045263796, -98765, 8844771355703),
        (-199028784496640, -806384301705, -2051197282, 548254704760, 37368110377359721),
        (-4294967296, 4611686018427387904, 60815078, 340812, -4611686018427392730),
        (-3337189588997, -209696134337589, -1509366947004794628, -6668004054, -2180381949347736175),
        (59521104398, -1132753826, -43317482494, -964799279635, -9746313715482),
        (3, 9223372036854775807, 4294967297, 2147483647, 4294967296),
        (-6766058457, 31, -188, 0, -49),
        (-32, 35042455924, -5962069709348005, -3337189588997, -4632528164170340909),
        (-51344130716862697, 83445449534, -8356097860, 5902790913, -997547530400745317),
        (178174, 4711201265, -95644051192, -300628671700, -6694659410614),
        (-61391972644559458, -2147483649, 6442450944, 3, 30695986336573657),
        (472792, 29551856287904, -842258900338764111, 6442450944, 1263388353761228268),
        (-5155678710, 32, 8381811625816718, -165, 322004489),
        (-4294967296, 450979, -2147483648, -245, -451102),
        (-98765, -210067382884497, 415540, -188, 4830608393),
        (-1752782311, 49780726963, -4294967297, 479052, -20315106991),
        (237, -24810899796720222, 5136318954869087, 408779752932, -488856620907671074),
        (-31024856876872579, 36834211625, -2099567608, 1538885151, -266073304369828601),
        (2147483648, -9223372036854775808, -405295, -6510801121, -4611686018428002297),
        (5897460955936425821, 4294967297, 6442450944, 110849843496, 5897460791034770207),
        (1930346440, 639382189, 2036607133, 1030694848, -201373210),
        (-11674931555, 3, 1, -7512295712, -7),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, w0) = *case;
        let g0 = mul_sub(f(a0), f(a1), f(a2), f(a3));
        assert!(g0.raw == w0, "mul_sub #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// floor(a . (b x c) / 2^64): exact triple products
#[test]
fn test_det3_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)> = array![
        (
            -16591,
            -509767121465,
            0,
            1257607535,
            -3228915215,
            342421,
            724748375,
            7132683892454,
            135287,
            -2154157,
        ),
        (
            229,
            165,
            9223372036854775807,
            2105354331,
            36935,
            -2147483649,
            114560,
            6442450944,
            20079983140506,
            6781820996486704472,
        ),
        (
            294448298300,
            -119015,
            -176,
            33633088852,
            25179827983,
            -734901248691,
            -157719927794864,
            -224234621309642,
            7327173779,
            -2630392855733140127,
        ),
        (
            280167042549275,
            814957,
            -19,
            -492834152,
            -62755458786,
            5483678376,
            -1098996803,
            182,
            2147483647,
            -2046815517335191,
        ),
        (
            -85316,
            38109182955046,
            62,
            -574174248,
            202829470687246,
            -2633405207,
            53932600479522,
            -832533,
            -446983,
            -293412776951886526,
        ),
        (
            1328456315,
            -66,
            35511515142,
            -950937,
            -897278192,
            -272724935231577,
            -188,
            84624844130664,
            -5726287868,
            1662073571268861310,
        ),
        (
            22803667630631,
            43,
            -44833877941,
            15998489014,
            -233177028699371,
            1668754681,
            -216,
            78,
            1889000231,
            -544506106703061650,
        ),
        (
            -122730219357838,
            -956883,
            4492173185,
            -198821738,
            160,
            -6822709931,
            164,
            -2147483649,
            -6525710439,
            97480793510109,
        ),
        (
            -8446695170,
            208453292186625,
            -65857162771,
            -4294967297,
            2052575498,
            -1213802938,
            -107731420487813,
            0,
            -1032890,
            1476887816059151190,
        ),
        (
            1081441242740,
            -300032,
            -739247,
            565277381,
            -795266,
            5087941273,
            14168765614,
            -1157347111,
            12345,
            345213271899,
        ),
        (
            131,
            -873232996,
            2147483648,
            768598,
            2147483648,
            624598459,
            2147483647,
            -22594752801,
            0,
            -602387756,
        ),
        (
            -13098153568,
            13493037705,
            3,
            -1015735885296,
            1078047298574,
            4294967296,
            98,
            -1002192733,
            12345,
            -3056615897,
        ),
        (
            -9223372036854775807,
            2147483647,
            4294967297,
            -201860563753004,
            6442450944,
            347588,
            -1156198008,
            -976539841,
            -936893094,
            3017798063944683172,
        ),
        (
            1040250,
            -123,
            -1242771717,
            1344073041,
            51138061999327,
            2147483648,
            247,
            199033079463936,
            -2147483649,
            -18052991716181,
        ),
        (
            9416223936,
            -872308723568,
            70968,
            -4258639714,
            -1006848125,
            221,
            13493037705,
            96675961698,
            -174,
            -1648438,
        ),
        (
            23811844489,
            -224,
            1805491093,
            100406257292,
            821173,
            3,
            4294967296333,
            64878756046,
            4294967296333,
            641798942394,
        ),
        (
            246,
            174341440281048,
            -1,
            1050760059,
            -16,
            -2127223111,
            -6369981334,
            20541545084246,
            -4294967297,
            170717972370467,
        ),
        (
            61199299206,
            -16,
            10620907248,
            220380862804,
            124,
            47188407477,
            -2147483649,
            -260960046529827,
            -297212134,
            7741805626518652,
        ),
        (
            -132137,
            153,
            -451171621360,
            -30633335786,
            21,
            6442450944,
            -9223372036854775807,
            0,
            -1758211076,
            -5230149521943,
        ),
        (
            -116608690482026,
            -3574612888721,
            -125,
            -20829436,
            2147483648,
            2006558206,
            -62013473122,
            1332007224,
            291670987500,
            -3919613875026304,
        ),
        (
            -267421,
            451699393,
            -929551,
            -7788113157,
            37546008345,
            644073517353,
            628831,
            264569,
            962638882612,
            183065985585,
        ),
        (
            6442450944,
            1503143115,
            38239040632,
            -5676026720,
            3009139250,
            237,
            -10173354664433,
            -32759874408,
            -500959,
            63844529061186,
        ),
        (
            -1363758925,
            6629127160,
            -153896392720184,
            -7566954263,
            -98765,
            238186374761,
            -140008775494794,
            946822181,
            -199028784496640,
            -12350262445132420,
        ),
        (815475, 211, 0, -221, 4294967296, 1022802, -3, -7031709859, -3, 317),
        (
            -3046588140,
            68682305715,
            0,
            245,
            -3337189588997,
            -21406818478,
            -199028784496640,
            134892727500314,
            200495313206565,
            125890665707314153,
        ),
        (
            971127,
            -95056092630880,
            -705298958,
            -11674931555,
            20750445004,
            -803932977947,
            1,
            27083802309,
            1162881222,
            -69946780437473,
        ),
        (
            -34154786951,
            -590307393793,
            498678902963,
            26,
            -145096,
            254787993493227,
            5758848077,
            -1038764,
            5375437646,
            -46954542461557125,
        ),
        (
            -16535062253,
            -211382212320223,
            -1923821448,
            -180,
            -2147483648,
            -1013518349339,
            -232564906032,
            21906125238,
            -139561726611172,
            -2701287763874856942,
        ),
        (
            -648299,
            -169,
            -109,
            2564771428,
            -225558492004388,
            12345,
            -66913511411,
            -11459865161,
            -4569836531,
            -36136408179,
        ),
        (
            -2147483649,
            984036,
            755573309949,
            -174785490,
            355014,
            251,
            9223372036854775806,
            -133,
            2838766694,
            -134119551405710529,
        ),
        (
            12329563382,
            65322,
            323027,
            254,
            1040424112941,
            3479600395,
            -238364672130071,
            -252703502296,
            -138959523825597,
            -96628347996064162,
        ),
        (
            914790,
            6442450944,
            9223372036854775806,
            -101,
            194,
            -2147483648,
            -246,
            -239527676,
            -575563,
            12096146175,
        ),
        (
            -106814464290477,
            229,
            -67579941908570,
            -1681666727,
            240,
            901775,
            13493037705,
            1321100891,
            -1476478121,
            8145967727946,
        ),
        (
            796005738513,
            -1065751799,
            -182953158771,
            25024299259,
            -11674931555,
            675371079360,
            -5278299793,
            1137468908,
            519401,
            -32615046992252,
        ),
        (
            -1853453059,
            -233031947071,
            5346728266,
            705267928850,
            -2147483648,
            -6987486080,
            2159784565,
            -839599817712,
            199033079463936,
            1773143208599896387,
        ),
        (
            83,
            -526591127,
            848530410,
            442947,
            -20,
            2053439705,
            -728666,
            5930399352,
            -7337805915,
            70707,
        ),
        (
            419710997369,
            -20600161937387,
            -424395455,
            -175459110106,
            -752568047,
            -580717428346,
            942433481821,
            4294967297,
            751794796941,
            463912202263234468,
        ),
        (
            -917836172367,
            252,
            118865530,
            4294967296,
            95,
            429981,
            -948401,
            28603656049934,
            -1593554561,
            1403572024953,
        ),
        (
            -13194152400,
            13493037705,
            -745788,
            2041963979,
            0,
            -785308,
            1037670441489,
            -145947,
            565149,
            -596903335,
        ),
        (
            -259719147396578,
            -11674931555,
            -9223372036854775808,
            160,
            -895290758,
            605381289,
            -4739669233,
            7262121262,
            -281011,
            2121752345462052761,
        ),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, a4, a5, a6, a7, a8, w0) = *case;
        let g0 = det3(f(a0), f(a1), f(a2), f(a3), f(a4), f(a5), f(a6), f(a7), f(a8));
        assert!(g0.raw == w0, "det3 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// floor((x^2 + y^2) / 2^32)
#[test]
fn test_norm2_squared_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (-8507221956, -25860609235, 172561019522), (-3, -358760300999, 29967388504392),
        (5287314823, 329761, 6508943193), (2107196778, -29073972858, 197844620796),
        (-120428701375852, -844951, 3376759615511199951), (183189, 249, 7),
        (-11674931555, 605222334435, 85316220793352), (172158627, -41933037742, 409411567464),
        (-3252322999551, -149747308876176, 5223516868555515038), (17, -1249684587, 363614309),
        (1044138351425, -14496502006, 253886693503457), (12345, -1936349290, 872986524),
        (953914022174, 144664976807030, 4872881217519805764),
        (-4160792291, -982150795021, 224597169168496), (-59973378778, 130, 837446693808),
        (12345, -4294967297, 4294967298), (1793266240, 172704672627672, 6944617245031325604),
        (6774770626, 200, 10686348433), (3, -201, 0), (972137191, -6314447165, 9503516768),
    ]
        .span();
    for case in cases {
        let (a0, a1, w0) = *case;
        let g0 = norm2_squared(f(a0), f(a1));
        assert!(
            g0.raw == w0, "norm2_squared #0: got {} expected {} (first input {})", g0.raw, w0, a0,
        );
    }
}

// floor(sum of squares / 2^32)
#[test]
fn test_norm3_squared_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (-681353005, -4294967297, 13493037705, 46792685172), (178, 681998, 176, 108),
        (844528996755, -62736177813927, -18858038045, 916547512531426094),
        (32594866180, -4294967297, -1466054091, 252160560333),
        (13493037705, 56854983001, -705386, 795012144150),
        (-2311667590, -2147483648, 3559585600, 5268059370),
        (-85238762060307, 4294967296, 789345, 1691665168856358327),
        (12345, 2147483647, 163442782689374, 6219731461689253171),
        (582857715610, -2147483648, -12978301214, 79138242787338),
        (2147483647, 113, -1, 1073741823),
        (424625165395, 122340215820972, 299669, 3484848121566021459),
        (3, 253015, 274632216, 17560766), (690566, 463298912, -11674931555, 31785730545),
        (-937127095580, -2907215247, -540135306186, 272402957584555),
        (-10737418240, -57014661767548, -426630080800, 756898379182883889),
        (-402421258077, -743087852, -46101369194, 38200234382737),
        (-3, -4294967296, 387975, 4294967331), (-1, -4294967297, 84932135870, 1683811295666),
        (854614, -4294967296, -23681214587, 134866374805),
        (1862127950, -210084400363, -1351734998, 10277319230113),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, w0) = *case;
        let g0 = norm3_squared(f(a0), f(a1), f(a2));
        assert!(
            g0.raw == w0, "norm3_squared #0: got {} expected {} (first input {})", g0.raw, w0, a0,
        );
    }
}

// floor(sum of squares / 2^32)
#[test]
fn test_norm4_squared_table() {
    let cases: Span<(i64, i64, i64, i64, i64)> = array![
        (-21753879473, 12345, 1, 1741625157, 110888977142),
        (5241645219, -638450345097, -63, 8814759555013, 18185850309834830),
        (-3337189588997, 732361603855, 21705796174, -4294967297, 2717989836829403),
        (978810882997, 46, 943557, -559682544554, 296001158503977),
        (-1022622, 977857, 9073103031, 44816939210, 486820759430),
        (-61, -3337189588997, 33499308171, -770947008778, 2731642650184605),
        (-1, -98765, 850323, 260439007515, 15792547873251),
        (48575278125, -99, 0, -11905854857, 582380924559),
        (-123594873314834, 2766604707, -151013586825, -152405438926195, 8964709317487088754),
        (4294967296333, 2147483648, 0, 320803, 4294968370407847),
        (-524943, -3102795817, -8814960866, -706008803924, 116074402373149),
        (10435682514, 199145, -2147483648, 17258509020, 95779842041),
        (-2064880635, 12345, 610731, -206, 992727561),
        (746579195689, -54385602148492, 4294967296, 2755183487, 688794797190295858),
        (3, 1, 1023398689576, -277710, 243853982031799),
        (-3337189588997, -3337189588997, 47989676, -297795357, 5185992642493223),
        (-31872771678, 481049869, -145, -990122565, 236808631128),
        (1, -27, -210, 2147483648, 1073741824),
        (2147483647, -3337189588997, -695729, -978027, 2592997384396712),
        (32327556717, 16698962402, 1557849931, -4294967297, 313110628417),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, w0) = *case;
        let g0 = norm4_squared(f(a0), f(a1), f(a2), f(a3));
        assert!(
            g0.raw == w0, "norm4_squared #0: got {} expected {} (first input {})", g0.raw, w0, a0,
        );
    }
}

// isqrt(x^2 + y^2) on the raw Q64.64 sum
#[test]
fn test_norm2_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (4294967297, -3337189588997, 3337192352810), (586129484130, -2147483649, 586133418133),
        (2147483647, 2985460169068739138, 2985460169068739138), (12345, -4294967296, 4294967296),
        (4611686018427387904, 1686391736, 4611686018427387904), (80, 297451866330, 297451866330),
        (8315053678, -941399064693, 941435785979), (4294967296333, 6442450944, 4294972128168),
        (168909330234, -59276034559, 179008407939),
        (-199028784496640, 199033079463936, 281472243354664),
        (834259476685, 14412669853666690, 14412669877811726),
        (22632734068, 4611686018427387904, 4611686018427387959),
        (1, -276568197156383880, 276568197156383880), (2147483648, -639593974763, 639597579919),
        (-31002759755, 3822447371024130476, 3822447371024130601),
        (-1545486600, -6587323291039581854, 6587323291039581854),
        (8568973490163442608, -149414, 8568973490163442608),
        (1688622917, -791622674548, 791624475560), (4294967297, 0, 4294967297),
        (-113, 882137587259, 882137587259), (-4591774851201085043, 12345, 4591774851201085043),
        (-102366561830034, -2147483649, 102366561852559),
        (-3337189588997, 54577488127566731, 54577488229594460), (13493037705, 1, 13493037705),
        (-27674419347283890, -2147483649, 27674419347283973),
        (4611686018427387904, 664264976734, 4611686018427435744), (-8876310985, -98765, 8876310985),
        (-2758868073, -199028784496640, 199028784515761),
        (-812471956574, 212719012379153, 212720563975941), (-98765, -71336, 121833),
        (1524346081821390032, 54278106935280327, 1525312128731920114),
        (2147483647, -4294967296, 4801919417), (-199028784496640, 98, 199028784496640),
        (115, 1, 115), (-5249350004, -239965395713, 240022804781),
        (6442450944, 57687532903, 58046159447),
        (-191003229441962, -199028784496640, 275852661244130),
        (2425458609782239, -2211410126293360867, 2211411456405678935),
        (-2569986851084675274, 4496196985506942014, 5178862785132450042),
        (-2147483649, -1, 2147483649),
    ]
        .span();
    for case in cases {
        let (a0, a1, w0) = *case;
        let g0 = norm2(f(a0), f(a1));
        assert!(g0.raw == w0, "norm2 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// isqrt of the raw sum of squares
#[test]
fn test_norm3_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (-1, 199033079463936, -8529042540, 199033079646680),
        (-3881203474806754685, -227980277279619990, 242, 3887893442428755565),
        (193963824921652, 4611686018427387904, -1785838630, 4611686022506369562),
        (4294967296, -746252, -6167415916, 7515568089),
        (-47305423665, -199028784496640, 1492089501, 199028790124040),
        (1954346062, 28035931, -4197361406304700242, 4197361406304700242),
        (12345, -4294967297, 80728912243403, 80728912357654),
        (3780423039414337753, 2147483648, 2801929073574114839, 4705571685807648701),
        (6442450944, 63710219710, -4900924478, 64222397420),
        (843139, 13493037705, 4294967297, 14160113392),
        (218, -234467674468871012, 4611686018427387904, 4617642582847820892),
        (6799315311124532837, 0, 162084778700317, 6799315313056453499),
        (-3337189588997, -4611686018427387904, 48698981114, 4611686018428595619),
        (-186136654021407, 7217234286, -666662078, 186136654162520),
        (-479607078, 6560735012, 2147483648, 6919895437),
        (67162934844, 52984, -4294967296, 67300123038),
        (114036050596210, 758711827204, 2532064333, 114038574551023),
        (176010655, -10737418240, 6442450944, 12523110810),
        (-2211290045398552, 166, -38208167, 2211290045398552),
        (7303277217, 4030238525744109669, 12345, 4030238525744109675),
        (-4294967297, -98765, -2147483648, 4801919419),
        (4294967296333, -199028784496640, 1303305637900, 199079387199861),
        (1742253268, 982527689962, 42826510862638295, 42826510873908927),
        (-4294967296, 2147483647, 9223372036854775806, 9223372036854775807),
        (-1046922, 199033079463936, -899613337727136553, 899613359744465873),
        (-115124, 1586995787, -1043243, 1586996134),
        (6660578466670727669, 13493037705, -12982392927, 6660578466670727695),
        (904373339602, 6442450944, 57676269111470647, 57676269118561367),
        (-2147483649, 91836445, -927834919, 2341153047),
        (2147483648, -11674931555, 4294967297, 12623884382),
        (-4417782747688705698, 2147483648, 35, 4417782747688705698),
        (6442450944, 8, 291440, 6442450950), (4294967296, 198184, 1623101442, 4591427055),
        (1890681450856937362, 16749179955, 4294967296, 1890681450856937441),
        (-3, 368219225, 176, 368219225), (4294967296333, 7182261569, 12345, 4294973301599),
        (-3670973443011013091, 2147483648, -3003035661, 3670973443011013092),
        (-1, 3615790810076816604, 11935438690974021, 3615810508991408366),
        (2147483648, -837200373, -21015727642751699, 21015727642751825),
        (139244558407837, -1, -925894, 139244558407837),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, w0) = *case;
        let g0 = norm3(f(a0), f(a1), f(a2));
        assert!(g0.raw == w0, "norm3 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// isqrt of the raw sum of squares
#[test]
fn test_norm4_table() {
    let cases: Span<(i64, i64, i64, i64, i64)> = array![
        (67167941349958605, -4611686018427387904, 203301112886459, 6442450944, 4612175138287268898),
        (-48997775750, -57310029447, 18023115902, 2845956668, 77576759920),
        (-639514012850, -153484, -5238041438127623137, -4294967296, 5238041438127662177),
        (4190161959147248, 4294967296, 4294967297, 98477208153516, 4191319005330816),
        (38602420051741499, -53424731686202496, -3309108824, 4294967296333, 65911674292499793),
        (-162367294461086786, -4189927447, -3, 41806105870, 162367294461092222),
        (-8583351542, 6926932718, -1015788613478, -837963985, 1015848840022),
        (49694736501, 7075972781, -98765, 1, 50195978192),
        (4294967296, -66786871953, -3337189588997, 1106597943, 3337860768587),
        (-100, 879210, -21690822352129178, 5911379758885595792, 5911419554179574240),
        (4611686018427387904, -413591, -33489687327585142, -1280603487, 4611807616511767870),
        (-98765, 356160923131, 203434015513438, 884462589522, 203436249947243),
        (278494871128561938, 28797629894, 4294967296333, -560188, 278494871161682069),
        (-3337189588997, -862568679072, 2147483647, -130, 3446862876691),
        (5724976934, 13493037705, -49252978955139316, -5897895719184370742, 5898101369958749818),
        (-2147483649, -4611686018427387904, -435469, 1419118398, 4611686018427387904),
        (-2147483648, 13493037705, 2468186841, -4294967296, 14533149792),
        (-70539430165581575, -35902697078924372, 13493037705, -248226795466, 79150583482926789),
        (199033079463936, -933430514, -776502937, 12775320391895031, 12776870715566131),
        (
            -6600885391,
            -222154663498588,
            -199028784496640,
            -2720983552670656974,
            2720983569018633657,
        ),
        (-349839360051, -6385719183835927, -1217154619, -2147483648, 6385719193419316),
        (9111962972973318460, 12345, -577780903, -537864, 9111962972973318460),
        (12345, -1987685265, -4611686018427387904, -3135549193828373347, 5576676131843807906),
        (-199028784496640, -149030293, -1935178241210300456, -1433485740, 1935178251445134672),
        (-199028784496640, -98765, 616521085, 211777875, 199028784497707),
        (530655935, 789589932, -946384, -609255, 951340763),
        (-3337189588997, 192822132930, -199028784496640, -3236345407052429, 3242461291183333),
        (13493037705, -2819024528, 12345, -35894228561, 38450027435),
        (5216960057, 64591201423895728, -3, 822672, 64591201423895938),
        (-37525523197276711, 4294967296333, -4294967297, -13980184, 37525523443066254),
        (695490329565, -5938392993, -2147483648, 4294967296333, 4350918380214),
        (24932049120431, -6620138628, 2147483647, 2864408844111677462, 2864408844220182768),
        (1324839631, -105531588, -27098113399, 7359303748, 28111091021),
        (13493037705, 3921654031, -35041982794, -6872049120608902092, 6872049120608902195),
        (0, -75, -427240114, 9223372036854775807, 9223372036854775807),
        (69656460585031923, 2147483647, -168171877913009, -4294967296, 69656663593762870),
        (-7015091622, -2147483648, -77241295131216, -27668348918312271, 27668456734758431),
        (1, 276193902277699, 1580703931, 4106252455401480803, 4106252464690129321),
        (276243869483096, 54181148306, -44733581442, 25434212035, 276243879589364),
        (-1037038247, -52949063190368616, 13493037705, 63636427878, 52949063190408585),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, w0) = *case;
        let g0 = norm4(f(a0), f(a1), f(a2), f(a3));
        assert!(g0.raw == w0, "norm4 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// isqrt((a0 - a2)^2 + (a1 - a3)^2), exact differences
#[test]
fn test_distance2_table() {
    let cases: Span<(i64, i64, i64, i64, i64)> = array![
        (-1366344912, 4294967296, -3566572188, 94, 4825737594),
        (-8061877706, -957690318846217728, 4097660211, 2147483647, 957690320993701452),
        (285765, -2147483648, 4294967296333, -4611686018427387904, 4611686016281904255),
        (-3337189588997, 991673, -58249241903, -3416706171747526395, 3416706171750091432),
        (
            8582966890485686744,
            -9223372036854775807,
            17928214128,
            -9223372036854775808,
            8582966872557472616,
        ),
        (-1949841604, -1475129884, -278464473939859, 494829759783, 278462966381015),
        (-47471701242, -60283524111, -25522998912, -1, 64154881443),
        (391186953220, -199028784496640, -199028784496640, -598476, 281745952647141),
        (4294967296, 801294, 26600276068, 2147483647, 22408369966),
        (-1, -1790280879, 4294967296, -10737418240, 9924616417),
        (-23598824479337869, -656539294, -98765, -28782207312190328, 37219886307866893),
        (-702798761003, 0, 8290930323183595780, 4294967296333, 8290931025983469248),
        (-183, 182805489361025, -191, -98765, 182805489459790),
        (-116793, -983648, -25, 985905241193, 985906224841),
        (-316804, 642239109753576341, -1056848505, -4294967296, 642239114048543637),
        (0, -775430279, -3458170333047786690, 1991070029632359520, 3990401222729353178),
        (-4327189407677682465, 0, -28957137897614385, 46621167881789745, 4298485102716232279),
        (150948942132618, -2147483648, -4294967296, -10737418240, 150953237344317),
        (-98765, -761106, 64255379857308307, -464570539, 64255379857407073),
        (-103021, -3878072928, 4530092692613267572, -2147483649, 4530092692613370593),
        (4293352897, -98765, 12345, 253153376405969, 253153376541140),
        (-153, 1, -266405026898270, 29309328726, 266405028510392),
        (-2009643149113464751, -49247406389952, -177, -24211187904, 2009643149716288748),
        (3233395779, -86255, 4294967297, 1617015540701110004, 1617015540701196259),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, w0) = *case;
        let g0 = distance2(f(a0), f(a1), f(a2), f(a3));
        assert!(g0.raw == w0, "distance2 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// isqrt of the sum of squared exact differences
#[test]
fn test_distance3_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64, i64)> = array![
        (
            843804347228,
            -1,
            1778373443375827211,
            4396221549,
            -25505804926202924,
            -234,
            1778556338773117264,
        ),
        (21430474092, -3, 199033079463936, -3, -35, 2147483647, 199030933134042),
        (-22814836477828, 39988181933939, -3, -111655435620299, -354651, 0, 97425390831849),
        (-159, 3, -3069765687, -1424899890518718250, -4294967297, 215, 1424899890518718100),
        (
            3938534799781427565,
            -6315424198,
            -52898799596730176,
            -837085812,
            4294967296333,
            879799619973382967,
            4047466209564966926,
        ),
        (
            1,
            418153013057,
            272664670846305,
            -160454402851322,
            1506244299,
            -375527976866728294,
            375800675792156643,
        ),
        (4294967297, -98765, -186632821377122, -76076026668, 1, 218534, 186632838901016),
        (79, 6442450944, 18878175454353569, -498055682785, 625140, -159396, 18878175461084070),
        (-216910353, -3337189588997, -98765, -416306289, 3, -234974632104680, 234998328761520),
        (
            -49152230187476026,
            -55318653212,
            906428757082555848,
            -2147483649,
            4611686018427387904,
            2147483648,
            4700178451088598483,
        ),
        (
            681706128479387207,
            -7798229837,
            -295863,
            -1210959462,
            -1,
            199033079463936,
            681706158745510125,
        ),
        (
            1,
            -199028784496640,
            6442450944,
            -3832511382087004763,
            4077635834007066176,
            682572247813,
            5596148734801924875,
        ),
        (
            -47059366250845145,
            -70987144424327307,
            -164,
            -16986426326163,
            818898672,
            405012,
            85159616540571454,
        ),
        (-1, -321261, 3, -4294967297, -199028784496640, -505186, 199028784221720),
        (
            394753771969912238,
            -2147483648,
            -441650,
            12345,
            -2147483649,
            740324995393032308,
            838994421488492949,
        ),
        (
            -37759650485,
            6219510187663845562,
            -745005292,
            912841,
            15669700460911583,
            40326417203369095,
            6203971551405026038,
        ),
        (
            354245463,
            -31320916585817,
            -5895063792716270839,
            4294967296333,
            3384039289178435055,
            2317545061,
            6797331170514338437,
        ),
        (
            -6943190643,
            -2457247426289644684,
            -42917223022541627,
            257469665631,
            5088074245,
            787688516,
            2457622189660576123,
        ),
        (-2147483649, 2147483647, -184188978789890, 4294967296, -84, -98765, 184188978816313),
        (
            -3906305916,
            -983573,
            50650216905808981,
            1025170115911,
            247,
            3971138175419751549,
            3920487958514077627,
        ),
        (-98765, -38704589006, 1, 8446893124, 637366955, 97159688675837327, 97159688675845658),
        (
            371718151,
            3753287244688955781,
            39590110975844300,
            -11674931555,
            97994491603399,
            898383935294,
            3753398040915806159,
        ),
        (
            -20051452731,
            768948288430,
            -814913985770,
            23277442746,
            199033079463936,
            395195794431,
            198267828842330,
        ),
        (
            -2081620750,
            -98765,
            -5823765823516511784,
            -2608051145,
            -12025531347280982,
            -11674931555,
            5823778227626718454,
        ),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, a4, a5, w0) = *case;
        let g0 = distance3(f(a0), f(a1), f(a2), f(a3), f(a4), f(a5));
        assert!(g0.raw == w0, "distance3 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// isqrt of the sum of squared exact differences
#[test]
fn test_distance4_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64, i64, i64, i64)> = array![
        (
            -1999305680582050409,
            607650541249772253,
            1287046452,
            4611686018427387904,
            -4294967296,
            553089813617,
            -2863153087865431492,
            -757524270,
            5816507134596630759,
        ),
        (
            610974999,
            -1,
            2147483647,
            83904507769701,
            275900367298827,
            -27,
            -4981539613450215,
            8,
            4989881657704084,
        ),
        (
            -2147483649,
            704286659,
            -3337189588997,
            340589317632766828,
            6442450944,
            -146444333,
            -10377885,
            251543395030822,
            340337774254097456,
        ),
        (
            13493037705,
            -53876987294706399,
            -98765,
            8515337524911325344,
            -2147483648,
            239696669721370,
            1354961555197476032,
            -527193977901104589,
            9143643989728709853,
        ),
        (
            -1412254393,
            -98765,
            6463678310,
            -203483247,
            -3213592040072145359,
            -4294967297,
            68576956589171872,
            -31639450633028412,
            3214479373685610110,
        ),
        (
            -711566465359,
            -25905723076,
            -11674931555,
            -2147483649,
            -4294967296,
            8500768310,
            -37082581155,
            -1868295209,
            708563621156,
        ),
        (
            611940361158643269,
            -4611686018427387904,
            -4294967296,
            6442450944,
            167664193853,
            -848763,
            1178423640,
            6442450944,
            4652109062883720671,
        ),
        (
            3822455145,
            64976481173,
            2147483648,
            -6134787855,
            199033079463936,
            -406384977132,
            4294967296,
            -4157368688895597828,
            4157368687524985384,
        ),
        (
            65250675557,
            -2509010825810312480,
            -58472389291,
            -41010568317605071,
            6659483665,
            5711430923547282537,
            -10737418240,
            6442450944,
            8220544046583748636,
        ),
        (
            -11674931555,
            5,
            999494,
            -98765,
            227,
            13493037705,
            4629236559927233835,
            -29859381785956002,
            4629332858030227029,
        ),
        (
            -160,
            -208,
            -1603014776,
            2819040452484378716,
            328493038124995,
            -686280987352,
            243,
            289416761927068208,
            2529623711886203621,
        ),
        (
            532214353244,
            -11674931555,
            -1,
            -88442824768861,
            -889545404123,
            12345,
            -11674931555,
            -66818945496046166,
            66730502686425350,
        ),
        (
            13493037705,
            -3337189588997,
            -8050277369,
            103410637667156,
            -5431240056086719632,
            4294967296,
            255139607545946,
            -3337189588997,
            5431240076622954692,
        ),
        (
            519391901,
            958606936303,
            8125087199,
            -2643906235417822719,
            -216176258450328,
            5838894926,
            -1335965198078177212,
            -1384466628,
            2962269949427209335,
        ),
        (
            -23860360067029994,
            928581,
            -2147483649,
            -341924,
            -23290679082,
            -5159646197726058,
            182,
            -23035123269,
            24411833605378976,
        ),
        (
            3386354108774103952,
            -199028784496640,
            -162,
            -1280542403390744243,
            -4294967296,
            2147483648,
            62,
            -4249238029672200509,
            4503392936466434516,
        ),
        (
            -4003761970,
            -15760303036910,
            -3824022092249228496,
            787591313880,
            1096193189,
            -3337189588997,
            1,
            -39899181402,
            3824022092269497537,
        ),
        (
            -11674931555,
            -2147483648,
            -844959,
            13493037705,
            -199028784496640,
            40542402321906,
            354933275,
            21,
            203105072809038,
        ),
        (
            -4294967297,
            -547123806,
            -9223372036854775808,
            6836278608,
            -663916320318,
            -4071259319412310208,
            -4611686018427387904,
            6443707947920814935,
            8908657160537811653,
        ),
        (
            714166,
            -146,
            740339,
            -482007,
            4611686018427387904,
            -3,
            57884670034137803,
            119559,
            4612049280696916214,
        ),
        (
            0,
            -4611686018427387904,
            -5070621486,
            4294967296333,
            -126,
            136943647528341514,
            52902313878497096,
            14950861692,
            4748924337127654760,
        ),
        (
            -19866190892,
            -15638918304294586,
            1243098604,
            636722,
            69381975848199,
            -2115774472,
            7601732566,
            -1689198091,
            15639070182311932,
        ),
        (
            -1,
            246092030840,
            -23205,
            680046771727,
            4611686018427387904,
            -1,
            12345,
            13493037705,
            4611686018427442641,
        ),
        (
            -2147483648,
            118,
            51654253974880061,
            -19897235110150299,
            0,
            -2147483648,
            -10737418240,
            -4294967297,
            55353977789142333,
        ),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, a4, a5, a6, a7, w0) = *case;
        let g0 = distance4(f(a0), f(a1), f(a2), f(a3), f(a4), f(a5), f(a6), f(a7));
        assert!(g0.raw == w0, "distance4 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// floor(sum of squared exact differences / 2^32)
#[test]
fn test_distance2_squared_table() {
    let cases: Span<(i64, i64, i64, i64, i64)> = array![
        (481829786, -301273148852, 106, -135194, 21133027253303),
        (718619816760, 938504, 254133742, 1, 120152080091368),
        (0, -199, 36366431992840, 1043246, 307922571871862230),
        (1315544906, -1740212219, -460619611595, -130518345805607, 3966222917593273187),
        (-334615, -4294967297, 613539678063, 2053040307, 87654135273178),
        (116, -4294967297, -29017185829673, -10317261535434, 220805954401385734),
        (-134163, 2147483647, -30980547476616, -87727, 223469528893482509),
        (-95374205941, -450594195, 325246, 938535775, 2118346952184),
        (-302555015, 47, -248827, 4294967297, 4316245370),
        (9711554838, -398166906906, 244, -1046288857, 36740465921408),
        (49791523620, -719161, -116, -918047302250, 196809117812044),
        (-29396387838, -2113453601, -42964992112, 1690348649, 46234562411),
        (399137478, -93821655594806, 4006035613, 61, 2049492455919168982),
        (-23083058969, 12345, -3337189588997, 12345, 2557249295612385),
        (-71, -10737418240, 4934142399, 105939749916885, 2613641738634613561),
        (3112610024, -1818128265, 541454419534, -8012793755, 67486026731094),
        (4294967296333, 1, -1111159238, 764178837316, 4433155849534416),
        (13493037705, 2149994939, -99, 5007445170, 44290696038),
        (115558520695234, -5427395055, -55202585598, 879351615619, 3112320752058765957),
        (1077312160452, -245, 96, 3, 270223592140458),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, w0) = *case;
        let g0 = distance2_squared(f(a0), f(a1), f(a2), f(a3));
        assert!(
            g0.raw == w0,
            "distance2_squared #0: got {} expected {} (first input {})",
            g0.raw,
            w0,
            a0,
        );
    }
}

// floor(sum of squared exact differences / 2^32)
#[test]
fn test_distance3_squared_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64, i64)> = array![
        (-8255795691293, -1, 2147483648, 4294967296, -74328502, 6442450944, 15885829026898848),
        (-98765, 649508640, 529983390, 62783, -3337189588997, 496320914, 2594005745567234),
        (
            -3337189588997,
            13493037705,
            -182287311488,
            1068775728419,
            4294967296,
            63656632467349,
            953399644585223366,
        ),
        (
            -1087095238343,
            4294967296,
            28726924162,
            -1036626,
            -34788060035,
            199033079463936,
            9221005167593501173,
        ),
        (-3337189588997, -189, 865719314, -1018965869720, 2430523022, -438085794, 1251271185458015),
        (-1966757306, -395707, -2221480028, -971941, 89094103, 54703804170, 755386497255),
        (66837675976, 526701439567, 177095240358014, 0, 516141, -37144551670, 7305332381494835884),
        (
            -165290038564,
            1202278250,
            -209,
            -11674931555,
            143466792596669,
            46984401130,
            4792213768360090925,
        ),
        (0, 4134363116, -643771290359, -632940098985, 194456823216823, 0, 8803946724412911616),
        (
            -2869408949,
            50117,
            371235165564,
            695293577879,
            34216697398,
            909237064223,
            181153504664179,
        ),
        (-3, -372744, -98765, 4294967296, -1443995612, 4502724096, 9500934929),
        (1087547766672, 13493037705, -241, -148, -769974, 59030976707, 276236535096606),
        (
            50424322670186,
            -77664974395113,
            -1031205,
            602515053,
            12345,
            -4294967296,
            1996383029602505081,
        ),
        (356286, 899045151, 948254545, -98765, 12345, -112, 397546004),
        (
            4588905717,
            4294967296333,
            -481957135781,
            6442450944,
            604759896436,
            -421811,
            3224684941588259,
        ),
        (
            -5043317669,
            234515636607,
            4294967297,
            4179285399,
            -1707545067,
            -159060348856,
            19225153905103,
        ),
        (1011940029, 201690, 171, 2147483648, -1176330735, -162155065572, 6122733241406),
        (-4294967296, 4294967296333, -3, 0, 108253046, -785582, 4294755088269900),
        (
            -58980700273,
            -10737418240,
            -4294967296,
            -1319835807,
            4294967296333,
            -3654867853,
            4317243181661335,
        ),
        (180204561895476, -147271, -1, 192144794485, -550671394, -2147483649, 7544753680810313636),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, a4, a5, w0) = *case;
        let g0 = distance3_squared(f(a0), f(a1), f(a2), f(a3), f(a4), f(a5));
        assert!(
            g0.raw == w0,
            "distance3_squared #0: got {} expected {} (first input {})",
            g0.raw,
            w0,
            a0,
        );
    }
}

// floor(sum of squared exact differences / 2^32)
#[test]
fn test_distance4_squared_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64, i64, i64, i64)> = array![
        (
            -4294967297,
            -380984,
            -171236,
            -1,
            -4294967296,
            -65116463886,
            54714857068,
            -1000766397,
            1684492479122,
        ),
        (
            863369992639,
            602543696329,
            -4524501705,
            -399659,
            4294967296,
            55685096575,
            -292746667010,
            1446018761,
            260802529750468,
        ),
        (
            -268252,
            762355779433,
            -4294967297,
            40,
            12345,
            148212283319,
            -4566734910,
            155,
            87817271164814,
        ),
        (
            -514104,
            246,
            -11779680892,
            -376698,
            130,
            -185933861751375,
            4294967297,
            6442450944,
            8049281604070042569,
        ),
        (
            -472275,
            19489848233,
            -6887912733,
            -2147483648,
            34732608943,
            868231600532,
            1078128159218,
            979855205,
            442107814752206,
        ),
        (
            -131,
            399364732690,
            105644011834,
            -98765,
            -116,
            4294967297,
            -5914921205,
            -25535152,
            39237904296137,
        ),
        (
            1011897,
            31117073690,
            2147483648,
            127376679464283,
            12345,
            1252450680,
            13493037705,
            -2147483649,
            3777762543235093556,
        ),
        (
            640922221249,
            -1138892207,
            4294967296,
            -3337189588997,
            177278257,
            4294967297,
            -141,
            -954068849954,
            1417907539848487,
        ),
        (
            -2147483649,
            795935160,
            -4588843686,
            -1271527897,
            -4294967297,
            -687965947,
            -20179785,
            8566376818,
            28980594951,
        ),
        (
            -2147483649,
            -154039,
            -10737418240,
            584162312,
            -199028784496640,
            13493037705,
            -98765,
            2743538895,
            9222794916182765564,
        ),
        (
            185,
            -10737418240,
            -796102877,
            19656429675,
            4294967296333,
            139,
            13493037705,
            0,
            4295131639088608,
        ),
        (
            4971832946,
            -212960894905,
            24773008937,
            454030003,
            -967324434087,
            -1,
            37142488651094,
            4924772291000,
            326653112937058222,
        ),
        (
            129962475169074,
            -21044209570274,
            -37810,
            2073006606,
            429802,
            3,
            -661174,
            -97938212,
            4035677668057999707,
        ),
        (
            820641026173,
            9678163729,
            -270489,
            2147483648,
            76596349215617,
            -722325653957,
            -114638386491404,
            0,
            4396879435784238744,
        ),
        (
            -188232,
            1735022908,
            2768916382,
            -41957062113257,
            -18019037681,
            12345,
            -3337189588997,
            12345,
            412471292707714359,
        ),
        (
            -114,
            809420283263,
            -21263919210085,
            -408836,
            -451496,
            2147483647,
            -36,
            -4294967296,
            105427104976895105,
        ),
        (
            0,
            -154,
            615286028362,
            -10737418240,
            4294967297,
            35253452786,
            -1508614699,
            -4294967296,
            88880394951251,
        ),
        (-101, 205, 4294967297, 46, 7936368847, -240, -2147483648, -98765, 24328736184),
        (
            63041458586,
            4294967296,
            -24399929301190,
            95,
            39266515666,
            9813950428,
            507800,
            42417166733812,
            557530020388465502,
        ),
        (-1615722245, -49329643, 3, 4294967296, -1037172862, 247, -228, 6442450944, 1152241333),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, a4, a5, a6, a7, w0) = *case;
        let g0 = distance4_squared(f(a0), f(a1), f(a2), f(a3), f(a4), f(a5), f(a6), f(a7));
        assert!(
            g0.raw == w0,
            "distance4_squared #0: got {} expected {} (first input {})",
            g0.raw,
            w0,
            a0,
        );
    }
}

// len = isqrt(sum); r = 2^96 div len; floor((x r + 2^63) / 2^64)
#[test]
fn test_normalize2_table() {
    let cases: Span<(i64, i64, i64, i64)> = array![
        (-66841075931685734, 2147483648, -4294967296, 138),
        (-3337189588997, -1236647445267698992, -11590, -4294967296),
        (-4294967297, -98765, -4294967295, -98765),
        (-643277225727014706, 2381213394971405379, -1120118700, 4146333099),
        (-9223372036854775807, 153, -4294967296, 0), (36332946975, 235, 4294967296, 28),
        (-187484587399751, 4294967296333, -4293840754, 98364916),
        (-4294967297, 1205670399, -4135128228, 1160800853),
        (4294967296, -46332740128078158, 398, -4294967296), (0, 4294967296333, 0, 4294967296),
        (-246261, -553412, -1746129367, -3924003172), (662306, -79538201006622, 36, -4294967296),
        (83, -2012171184, 177, -4294967296), (-11674931555, -9223372036854775807, -5, -4294967295),
        (13493037705, 23894957348278066, 2425, 4294967296),
        (4294967296, 425803221808595, 43322, 4294967296),
        (-199028784496640, -128427174296554, -3608868962, -2328692528),
        (-3207294174742023737, 6279749241, -4294967296, 8), (2147483648, 175, 4294967296, 350),
        (-3500614571, 222, -4294967296, 272), (-4294967297, 62, -4294967296, 62),
        (962493319, 446215801, 3896587769, 1806473872),
        (-3337189588997, -2412106600415793288, -5942, -4294967296),
        (-5519622640, 2011341700441525838, -12, 4294967296),
        (-4611686018427387904, 6442450944, -4294967296, 6),
        (198608149907530, -546134851, 4294967296, -11810),
        (689696999075760769, -251407489238174468, 4035237229, -1470919638),
        (1716331028, 493121, 4294967121, 1233992),
        (-214379566971095034, -829612726, -4294967296, -17),
        (-171731274100209, -199028784496640, -2805804354, -3251800425),
        (-1601961919, 772220, -4294966797, 2070373), (3, 2491263461, 5, 4294967296),
    ]
        .span();
    for case in cases {
        let (a0, a1, w0, w1) = *case;
        let (g0, g1) = normalize2(f(a0), f(a1));
        assert!(g0.raw == w0, "normalize2 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
        assert!(g1.raw == w1, "normalize2 #1: got {} expected {} (first input {})", g1.raw, w1, a0);
    }
}

// len = isqrt(sum); r = 2^96 div len; floor((x r + 2^63) / 2^64)
#[test]
fn test_normalize3_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64)> = array![
        (188158955763, 0, 4611686018427387904, 175, 0, 4294967296),
        (
            8951980532770523252,
            9223372036854775806,
            -199028784496640,
            2991319032,
            3082004950,
            -66506,
        ),
        (209732297655, 2147483648, -9223372036854775807, 98, 1, -4294967295),
        (820537, 508117, -560084589135, 6292, 3896, -4294967296),
        (-64, -154, -2495009259647701362, 0, 0, -4294967296),
        (559884618518, -50493, 745423, 4294967296, -387, 5718),
        (-2904114022586636, -5, 4878479942, -4294967296, 0, 7215),
        (6442450944, 30586790693, 12345, 885219648, 4202752699, 1696),
        (4611686018427387904, -3, 7929199528, 4294967296, 0, 7),
        (31964614791, 250, -9223372036854775807, 15, 0, -4294967295),
        (66120402905095617, 4056056973922434042, -923787, 70005733, 4294396730, 0),
        (-3337189588997, 4611686018427387904, 62475219907, -3108, 4294967296, 58),
        (249177349475219, 152415374182846, -98765, 3663899178, 2241112868, -1),
        (-47, -9223372036854775808, 220228773378551, 0, -4294967294, 102552),
        (8062509238, 26927715545904072, -9223372036854775808, 4, 12539141, -4294948991),
        (1, -35940089361152583, 2147483648, 0, -4294967296, 257),
        (-1790555756017836306, 230647026327395, 4294967297, -4294967260, 553248, 10),
        (760915, -98765, 1059649307655, 3084, -400, 4294967296),
        (0, 6612945384, 25015217876, 0, 1097695909, 4152325585),
        (1169511051, -9223372036854775808, 12345, 1, -4294967296, 0),
        (-5381941117, 4132130829110101938, 56194961058, -6, 4294967296, 58),
        (0, 1028705939934, 4447276617453877694, 0, 993, 4294967296),
        (6442450944, 1924044916371678475, 247294615363261, 14, 4294967260, 552026),
        (-10737418240, 654065423513635333, 1, -71, 4294967296, 0),
        (-199028784496640, -416693, 3, -4294967296, -9, 0),
        (4294967297, 2147483648, -11674931555, 1461257369, 730628684, -3972109352),
        (-186546911581564, -3940440982, 8554501626776597457, -93660, -2, 4294967295),
        (
            199033079463936,
            -8551668739337183547,
            -3753489600061714483,
            91533,
            -3932813759,
            -1726186548,
        ),
        (-4105998408795125291, 2189975512725580422, -208, -3789634986, 2021239902, 0),
        (
            -1377725105026434806,
            199033079463936,
            -4611686018427387904,
            -1229416456,
            177608,
            -4115249594,
        ),
        (9223372036854775807, 52522649229280198, -64, 4294897660, 24457368, 0),
        (246, 1807764472630329990, -68182067424, 0, 4294967296, -162),
        (-7370138589, -108457, 93159993170, -338728094, -4985, 4281589349),
        (7906614413524262561, 6442450944, 65870018937, 4294967296, 3, 36),
        (-20201409, 2147483648, 307886, -40401030, 4294777230, 615745),
        (175918153, -4611686018427387904, -1802417611, 0, -4294967296, -2),
        (-3986092425, -4294967296, 9223372036854775806, -2, -2, 4294967296),
        (-3, 297163, -67399328895, 0, 18936, -4294967296),
        (-718254, -1716437617, -2147483648, -1122119, -2681568562, -3354986269),
        (4294967297, -1998266751, -3337189588997, 5527623, -2571769, -4294962969),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, w0, w1, w2) = *case;
        let (g0, g1, g2) = normalize3(f(a0), f(a1), f(a2));
        assert!(g0.raw == w0, "normalize3 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
        assert!(g1.raw == w1, "normalize3 #1: got {} expected {} (first input {})", g1.raw, w1, a0);
        assert!(g2.raw == w2, "normalize3 #2: got {} expected {} (first input {})", g2.raw, w2, a0);
    }
}

// len = isqrt(sum); r = 2^96 div len; floor((x r + 2^63) / 2^64)
#[test]
fn test_normalize4_table() {
    let cases: Span<(i64, i64, i64, i64, i64, i64, i64, i64)> = array![
        (-11027338155292280, 1038879540364, 232, 487042496566, -4294967273, 404627, 0, 189695),
        (
            -4294967297,
            -28133836623272942,
            4294967297,
            19331092125471778,
            -540,
            -3539874460,
            540,
            2432289638,
        ),
        (
            9223372036854775807,
            -1806780822980796211,
            -10355319482368654,
            4294967296333,
            4214856548,
            -825654864,
            -4732129,
            1963,
        ),
        (534401602, -56061881508, -812612, 5435982312, 40748189, -4274725500, -61962, 414494333),
        (
            -33958514885,
            60556330102,
            -1034903151665,
            862488,
            -140615677,
            250752112,
            -4285334839,
            3571,
        ),
        (714605366694, -2147483648, 1200352450, 6229840229521791112, 493, -1, 1, 4294967296),
        (-269216608054162, -37895, 3, -3, -4294967296, -1, 0, 0),
        (-50300008436, -2713338727231380872, 526864794, 1964027100, -80, -4294967296, 1, 3),
        (
            -1624395276402052910,
            4294967297,
            1388803138,
            -2591126812405368902,
            -2281315974,
            6,
            2,
            -3639002817,
        ),
        (
            -168058649266714,
            -12292164233003393,
            -132221978444323,
            154612328508302,
            -58707330,
            -4293977996,
            -46188633,
            54010175,
        ),
        (
            -141353987144,
            -766444,
            4334333069250562827,
            -2945125829439104087,
            -116,
            0,
            3552468380,
            -2413858422,
        ),
        (-2147483648, -432019571639, -4294967296, 4489, -21348112, -4294702011, -42696225, 45),
        (4611686018427387904, -276210936, -1134463581, -428786, 4294967296, 0, -1, 0),
        (-18202945367060, -50273090394997965, -98765, -66, -1555127, -4294967014, 0, 0),
        (
            -1583116818,
            -10737418240,
            2147483648,
            3706868033,
            -582723403,
            -3952295135,
            790459027,
            1364446850,
        ),
        (
            238737293227746,
            -171265054854326,
            -9223372036854775808,
            -4611686018427387904,
            99434,
            -71332,
            -3841535532,
            -1920767766,
        ),
        (264554601, 6699963326686765368, 4611686018427387904, -98765, 0, 3537886300, 2435180610, 0),
        (
            -2173432069497247048,
            6227232736,
            62415206906211565,
            -3850778824,
            -4293197391,
            12,
            123289247,
            -8,
        ),
        (-98765, -223005290133365, -19410709353, 3, -2, -4294967280, -373840, 0),
        (
            -565519354350,
            -9223372036854775807,
            -5966392036877226990,
            38288545679,
            -221,
            -3606224543,
            -2332785592,
            15,
        ),
        (
            4611686018427387904,
            -199028784496640,
            -60038547841390228,
            771509082730752360,
            4235748494,
            -182804,
            -55144298,
            708616853,
        ),
        (690328963639, -396592, 1, 54822238702, 4281487513, -2460, 0, 340012867),
        (9117809603, 3441634761, -5741466452387232091, 72603, 7, 3, -4294967296, 0),
        (
            -582154254975,
            -46327,
            -195283382835589,
            46852953448430,
            -12450239,
            -1,
            -4176427185,
            1002020477,
        ),
        (6442450944, 2147483648, 168, 3, 4074563740, 1358187913, 106, 2),
        (42822731846792857, -3, -61074816505, 2147483647, 4294967296, 0, -6126, 215),
        (-18391865395, 1, 13397522792, -55513528273, -1316631317, 0, 959097824, -3974085733),
        (2476088468, -64897410711, 3, -10737418240, 161557383, -4234362367, 0, -700584495),
        (
            -2147483649,
            631683576,
            -7320973122846303345,
            2037022717326603801,
            -1,
            0,
            -4137779184,
            1151315550,
        ),
        (
            -922678950246,
            199033079463936,
            4294967297,
            -2061348244184967273,
            -1922,
            414700,
            9,
            -4294967276,
        ),
        (-244, -43321618248143940, 8979339118770511836, 4294967296, 0, -20721210, 4294917311, 2),
        (-94631, -184178125, -4294967297, 4363632655375821672, 0, 0, -4, 4294967296),
    ]
        .span();
    for case in cases {
        let (a0, a1, a2, a3, w0, w1, w2, w3) = *case;
        let (g0, g1, g2, g3) = normalize4(f(a0), f(a1), f(a2), f(a3));
        assert!(g0.raw == w0, "normalize4 #0: got {} expected {} (first input {})", g0.raw, w0, a0);
        assert!(g1.raw == w1, "normalize4 #1: got {} expected {} (first input {})", g1.raw, w1, a0);
        assert!(g2.raw == w2, "normalize4 #2: got {} expected {} (first input {})", g2.raw, w2, a0);
        assert!(g3.raw == w3, "normalize4 #3: got {} expected {} (first input {})", g3.raw, w3, a0);
    }
}

// r = trunc(2^96 / a0); floor((a1 r + 2^63) / 2^64): a1 / a0 rounded to nearest
#[test]
fn test_recip_mul_table() {
    let cases: Span<(i64, i64, i64)> = array![
        (-2147483648, 2027039009019215439, -4054078018038430878),
        (-199028784496640, -9223372036854775807, 199036945119870),
        (-4294967297, 1411681583, -1411681583), (-12, 2147483647, -768614336046650709),
        (-199028784496640, -173073, 4), (-3337189588997, 4294967296, -5527628),
        (-51417685964, -4294967296, 358762627),
        (-2578721729634264245, -9223372036854775808, 15361906173),
        (-615469331, -7819392338, 54566544058),
        (-11674931555, -28707851656766483, 10561028424310232),
        (-1895476140, 353884278215963, -801867862871714), (-3266649236038689508, -11674931555, 15),
        (-22878227463, -432370405, 81169608), (-3687745931, -199028784496640, 231800708717452),
        (6442450944, -2147483648, -1431655765), (-53393978618, 360711, -29015),
        (38000368089041, 1, 0), (245691183306257, -4294967296, -75081),
        (4294967296333, -3801294828216225730, -3801294827921501), (3, 12345, 17673790423040),
        (2147483648, -1935457883091117620, -3870915766182235240),
        (-10737418240, -6253080414, 2501232166), (6060535936, 115, 81),
        (-331111, -45860116046, 594869088034933),
        (-790983211525, 5330208195738724517, -28942548398001522),
        (-4294967297, -62674128988, 62674128973), (-1444070401157848962, 6442450944, -19),
        (-3337189588997, -495790210, 638083), (-1861814704, 377573, -871012),
        (-4294967297, 9223372036854775807, -9223372034707292159), (-4611686018427387904, 286405, 0),
        (23208888813431186, 1316600154, 244), (-11808055972, -10737418240, 3905542140),
        (-226478798629580, 4294967296333, -81450203), (-683783845586, 12345, -78),
        (-96, -19116440749, 855255081592466091), (-98765, 3, -130460),
        (-974683, 332925233, -1467044144351), (-28523713509, 63877607723, -9618391239),
        (7243376452, 351886, 208651), (6442450944, -4927075626, -3284717084),
        (3677101609604545749, -403475503156, -471),
        (6442450944, 9223372036854775807, 6148914691236517204),
        (5842680899218797845, -9223372036854775808, -6780120622), (36, 384992, 45931334700601),
        (4294967296333, -9223372036854775808, -9223372036139663),
        (4471748639932452703, 9223372036854775807, 8858745078),
        (-2147483649, -555794026829, 1111588053140), (-2147483649, -902637, 1805274),
        (39304666018677950, -9223372036854775807, -1007872226628),
        (4294967296, -6796294033, -6796294033), (4611686018427387904, 2147483648, 2),
        (1, -779009701, -3345821189061738496),
        (-2147483649, 2198308117225831939, -4396616232404329903),
        (-226959072860794, 844572856953, -15982674),
        (-530270092, 40296949928627618, -326388541769776360),
    ]
        .span();
    for case in cases {
        let (a0, a1, w0) = *case;
        let g0 = RecipTrait::new(f(a0)).mul(f(a1));
        assert!(g0.raw == w0, "recip_mul #0: got {} expected {} (first input {})", g0.raw, w0, a0);
    }
}

// Every `Wn (+|-) Wm`, `neg`, `narrow` , `mul`, `lift` impl generated by scripts/gen_bounded.py.
#[test]
fn test_every_w_impl_compiles_and_is_exact() {
    let x1 = wide_mul(opaque(ONE), opaque(ONE));
    let x2 = x1.add(x1);
    let x3 = x2.add(x1);
    let x4 = x3.add(x1);
    let x5 = x4.add(x1);
    let x6 = x5.add(x1);
    let x7 = x6.add(x1);
    let x8 = x7.add(x1);
    let x9 = x8.add(x1);
    let x10 = x9.add(x1);
    let x11 = x10.add(x1);
    let x12 = x11.add(x1);
    let x13 = x12.add(x1);
    let x14 = x13.add(x1);
    let x15 = x14.add(x1);
    let x16 = x15.add(x1);
    assert_eq!(x1.narrow(), int(1));
    assert_eq!(x1.neg().narrow(), int(-1));
    assert_eq!(x1.mul(int(-3)).narrow(), int(-3));
    assert_eq!(x1.lift().narrow(), int(1));
    assert_eq!(x1.add(x1).narrow(), int(2));
    assert_eq!(x1.sub(x1).narrow(), int(0));
    assert_eq!(x1.add(x2).narrow(), int(3));
    assert_eq!(x1.sub(x2).narrow(), int(-1));
    assert_eq!(x1.add(x3).narrow(), int(4));
    assert_eq!(x1.sub(x3).narrow(), int(-2));
    assert_eq!(x1.add(x4).narrow(), int(5));
    assert_eq!(x1.sub(x4).narrow(), int(-3));
    assert_eq!(x1.add(x5).narrow(), int(6));
    assert_eq!(x1.sub(x5).narrow(), int(-4));
    assert_eq!(x1.add(x6).narrow(), int(7));
    assert_eq!(x1.sub(x6).narrow(), int(-5));
    assert_eq!(x1.add(x7).narrow(), int(8));
    assert_eq!(x1.sub(x7).narrow(), int(-6));
    assert_eq!(x1.add(x8).narrow(), int(9));
    assert_eq!(x1.sub(x8).narrow(), int(-7));
    assert_eq!(x1.add(x9).narrow(), int(10));
    assert_eq!(x1.sub(x9).narrow(), int(-8));
    assert_eq!(x1.add(x10).narrow(), int(11));
    assert_eq!(x1.sub(x10).narrow(), int(-9));
    assert_eq!(x1.add(x11).narrow(), int(12));
    assert_eq!(x1.sub(x11).narrow(), int(-10));
    assert_eq!(x1.add(x12).narrow(), int(13));
    assert_eq!(x1.sub(x12).narrow(), int(-11));
    assert_eq!(x1.add(x13).narrow(), int(14));
    assert_eq!(x1.sub(x13).narrow(), int(-12));
    assert_eq!(x1.add(x14).narrow(), int(15));
    assert_eq!(x1.sub(x14).narrow(), int(-13));
    assert_eq!(x1.add(x15).narrow(), int(16));
    assert_eq!(x1.sub(x15).narrow(), int(-14));
    assert_eq!(x2.narrow(), int(2));
    assert_eq!(x2.neg().narrow(), int(-2));
    assert_eq!(x2.mul(int(-3)).narrow(), int(-6));
    assert_eq!(x2.lift().narrow(), int(2));
    assert_eq!(x2.add(x1).narrow(), int(3));
    assert_eq!(x2.sub(x1).narrow(), int(1));
    assert_eq!(x2.add(x2).narrow(), int(4));
    assert_eq!(x2.sub(x2).narrow(), int(0));
    assert_eq!(x2.add(x3).narrow(), int(5));
    assert_eq!(x2.sub(x3).narrow(), int(-1));
    assert_eq!(x2.add(x4).narrow(), int(6));
    assert_eq!(x2.sub(x4).narrow(), int(-2));
    assert_eq!(x2.add(x5).narrow(), int(7));
    assert_eq!(x2.sub(x5).narrow(), int(-3));
    assert_eq!(x2.add(x6).narrow(), int(8));
    assert_eq!(x2.sub(x6).narrow(), int(-4));
    assert_eq!(x2.add(x7).narrow(), int(9));
    assert_eq!(x2.sub(x7).narrow(), int(-5));
    assert_eq!(x2.add(x8).narrow(), int(10));
    assert_eq!(x2.sub(x8).narrow(), int(-6));
    assert_eq!(x2.add(x9).narrow(), int(11));
    assert_eq!(x2.sub(x9).narrow(), int(-7));
    assert_eq!(x2.add(x10).narrow(), int(12));
    assert_eq!(x2.sub(x10).narrow(), int(-8));
    assert_eq!(x2.add(x11).narrow(), int(13));
    assert_eq!(x2.sub(x11).narrow(), int(-9));
    assert_eq!(x2.add(x12).narrow(), int(14));
    assert_eq!(x2.sub(x12).narrow(), int(-10));
    assert_eq!(x2.add(x13).narrow(), int(15));
    assert_eq!(x2.sub(x13).narrow(), int(-11));
    assert_eq!(x2.add(x14).narrow(), int(16));
    assert_eq!(x2.sub(x14).narrow(), int(-12));
    assert_eq!(x3.narrow(), int(3));
    assert_eq!(x3.neg().narrow(), int(-3));
    assert_eq!(x3.mul(int(-3)).narrow(), int(-9));
    assert_eq!(x3.lift().narrow(), int(3));
    assert_eq!(x3.add(x1).narrow(), int(4));
    assert_eq!(x3.sub(x1).narrow(), int(2));
    assert_eq!(x3.add(x2).narrow(), int(5));
    assert_eq!(x3.sub(x2).narrow(), int(1));
    assert_eq!(x3.add(x3).narrow(), int(6));
    assert_eq!(x3.sub(x3).narrow(), int(0));
    assert_eq!(x3.add(x4).narrow(), int(7));
    assert_eq!(x3.sub(x4).narrow(), int(-1));
    assert_eq!(x3.add(x5).narrow(), int(8));
    assert_eq!(x3.sub(x5).narrow(), int(-2));
    assert_eq!(x3.add(x6).narrow(), int(9));
    assert_eq!(x3.sub(x6).narrow(), int(-3));
    assert_eq!(x3.add(x7).narrow(), int(10));
    assert_eq!(x3.sub(x7).narrow(), int(-4));
    assert_eq!(x3.add(x8).narrow(), int(11));
    assert_eq!(x3.sub(x8).narrow(), int(-5));
    assert_eq!(x3.add(x9).narrow(), int(12));
    assert_eq!(x3.sub(x9).narrow(), int(-6));
    assert_eq!(x3.add(x10).narrow(), int(13));
    assert_eq!(x3.sub(x10).narrow(), int(-7));
    assert_eq!(x3.add(x11).narrow(), int(14));
    assert_eq!(x3.sub(x11).narrow(), int(-8));
    assert_eq!(x3.add(x12).narrow(), int(15));
    assert_eq!(x3.sub(x12).narrow(), int(-9));
    assert_eq!(x3.add(x13).narrow(), int(16));
    assert_eq!(x3.sub(x13).narrow(), int(-10));
    assert_eq!(x4.narrow(), int(4));
    assert_eq!(x4.neg().narrow(), int(-4));
    assert_eq!(x4.mul(int(-3)).narrow(), int(-12));
    assert_eq!(x4.lift().narrow(), int(4));
    assert_eq!(x4.add(x1).narrow(), int(5));
    assert_eq!(x4.sub(x1).narrow(), int(3));
    assert_eq!(x4.add(x2).narrow(), int(6));
    assert_eq!(x4.sub(x2).narrow(), int(2));
    assert_eq!(x4.add(x3).narrow(), int(7));
    assert_eq!(x4.sub(x3).narrow(), int(1));
    assert_eq!(x4.add(x4).narrow(), int(8));
    assert_eq!(x4.sub(x4).narrow(), int(0));
    assert_eq!(x4.add(x5).narrow(), int(9));
    assert_eq!(x4.sub(x5).narrow(), int(-1));
    assert_eq!(x4.add(x6).narrow(), int(10));
    assert_eq!(x4.sub(x6).narrow(), int(-2));
    assert_eq!(x4.add(x7).narrow(), int(11));
    assert_eq!(x4.sub(x7).narrow(), int(-3));
    assert_eq!(x4.add(x8).narrow(), int(12));
    assert_eq!(x4.sub(x8).narrow(), int(-4));
    assert_eq!(x4.add(x9).narrow(), int(13));
    assert_eq!(x4.sub(x9).narrow(), int(-5));
    assert_eq!(x4.add(x10).narrow(), int(14));
    assert_eq!(x4.sub(x10).narrow(), int(-6));
    assert_eq!(x4.add(x11).narrow(), int(15));
    assert_eq!(x4.sub(x11).narrow(), int(-7));
    assert_eq!(x4.add(x12).narrow(), int(16));
    assert_eq!(x4.sub(x12).narrow(), int(-8));
    assert_eq!(x5.narrow(), int(5));
    assert_eq!(x5.neg().narrow(), int(-5));
    assert_eq!(x5.mul(int(-3)).narrow(), int(-15));
    assert_eq!(x5.lift().narrow(), int(5));
    assert_eq!(x5.add(x1).narrow(), int(6));
    assert_eq!(x5.sub(x1).narrow(), int(4));
    assert_eq!(x5.add(x2).narrow(), int(7));
    assert_eq!(x5.sub(x2).narrow(), int(3));
    assert_eq!(x5.add(x3).narrow(), int(8));
    assert_eq!(x5.sub(x3).narrow(), int(2));
    assert_eq!(x5.add(x4).narrow(), int(9));
    assert_eq!(x5.sub(x4).narrow(), int(1));
    assert_eq!(x5.add(x5).narrow(), int(10));
    assert_eq!(x5.sub(x5).narrow(), int(0));
    assert_eq!(x5.add(x6).narrow(), int(11));
    assert_eq!(x5.sub(x6).narrow(), int(-1));
    assert_eq!(x5.add(x7).narrow(), int(12));
    assert_eq!(x5.sub(x7).narrow(), int(-2));
    assert_eq!(x5.add(x8).narrow(), int(13));
    assert_eq!(x5.sub(x8).narrow(), int(-3));
    assert_eq!(x5.add(x9).narrow(), int(14));
    assert_eq!(x5.sub(x9).narrow(), int(-4));
    assert_eq!(x5.add(x10).narrow(), int(15));
    assert_eq!(x5.sub(x10).narrow(), int(-5));
    assert_eq!(x5.add(x11).narrow(), int(16));
    assert_eq!(x5.sub(x11).narrow(), int(-6));
    assert_eq!(x6.narrow(), int(6));
    assert_eq!(x6.neg().narrow(), int(-6));
    assert_eq!(x6.mul(int(-3)).narrow(), int(-18));
    assert_eq!(x6.lift().narrow(), int(6));
    assert_eq!(x6.add(x1).narrow(), int(7));
    assert_eq!(x6.sub(x1).narrow(), int(5));
    assert_eq!(x6.add(x2).narrow(), int(8));
    assert_eq!(x6.sub(x2).narrow(), int(4));
    assert_eq!(x6.add(x3).narrow(), int(9));
    assert_eq!(x6.sub(x3).narrow(), int(3));
    assert_eq!(x6.add(x4).narrow(), int(10));
    assert_eq!(x6.sub(x4).narrow(), int(2));
    assert_eq!(x6.add(x5).narrow(), int(11));
    assert_eq!(x6.sub(x5).narrow(), int(1));
    assert_eq!(x6.add(x6).narrow(), int(12));
    assert_eq!(x6.sub(x6).narrow(), int(0));
    assert_eq!(x6.add(x7).narrow(), int(13));
    assert_eq!(x6.sub(x7).narrow(), int(-1));
    assert_eq!(x6.add(x8).narrow(), int(14));
    assert_eq!(x6.sub(x8).narrow(), int(-2));
    assert_eq!(x6.add(x9).narrow(), int(15));
    assert_eq!(x6.sub(x9).narrow(), int(-3));
    assert_eq!(x6.add(x10).narrow(), int(16));
    assert_eq!(x6.sub(x10).narrow(), int(-4));
    assert_eq!(x7.narrow(), int(7));
    assert_eq!(x7.neg().narrow(), int(-7));
    assert_eq!(x7.mul(int(-3)).narrow(), int(-21));
    assert_eq!(x7.lift().narrow(), int(7));
    assert_eq!(x7.add(x1).narrow(), int(8));
    assert_eq!(x7.sub(x1).narrow(), int(6));
    assert_eq!(x7.add(x2).narrow(), int(9));
    assert_eq!(x7.sub(x2).narrow(), int(5));
    assert_eq!(x7.add(x3).narrow(), int(10));
    assert_eq!(x7.sub(x3).narrow(), int(4));
    assert_eq!(x7.add(x4).narrow(), int(11));
    assert_eq!(x7.sub(x4).narrow(), int(3));
    assert_eq!(x7.add(x5).narrow(), int(12));
    assert_eq!(x7.sub(x5).narrow(), int(2));
    assert_eq!(x7.add(x6).narrow(), int(13));
    assert_eq!(x7.sub(x6).narrow(), int(1));
    assert_eq!(x7.add(x7).narrow(), int(14));
    assert_eq!(x7.sub(x7).narrow(), int(0));
    assert_eq!(x7.add(x8).narrow(), int(15));
    assert_eq!(x7.sub(x8).narrow(), int(-1));
    assert_eq!(x7.add(x9).narrow(), int(16));
    assert_eq!(x7.sub(x9).narrow(), int(-2));
    assert_eq!(x8.narrow(), int(8));
    assert_eq!(x8.neg().narrow(), int(-8));
    assert_eq!(x8.mul(int(-3)).narrow(), int(-24));
    assert_eq!(x8.lift().narrow(), int(8));
    assert_eq!(x8.add(x1).narrow(), int(9));
    assert_eq!(x8.sub(x1).narrow(), int(7));
    assert_eq!(x8.add(x2).narrow(), int(10));
    assert_eq!(x8.sub(x2).narrow(), int(6));
    assert_eq!(x8.add(x3).narrow(), int(11));
    assert_eq!(x8.sub(x3).narrow(), int(5));
    assert_eq!(x8.add(x4).narrow(), int(12));
    assert_eq!(x8.sub(x4).narrow(), int(4));
    assert_eq!(x8.add(x5).narrow(), int(13));
    assert_eq!(x8.sub(x5).narrow(), int(3));
    assert_eq!(x8.add(x6).narrow(), int(14));
    assert_eq!(x8.sub(x6).narrow(), int(2));
    assert_eq!(x8.add(x7).narrow(), int(15));
    assert_eq!(x8.sub(x7).narrow(), int(1));
    assert_eq!(x8.add(x8).narrow(), int(16));
    assert_eq!(x8.sub(x8).narrow(), int(0));
    assert_eq!(x9.narrow(), int(9));
    assert_eq!(x9.neg().narrow(), int(-9));
    assert_eq!(x9.mul(int(-3)).narrow(), int(-27));
    assert_eq!(x9.lift().narrow(), int(9));
    assert_eq!(x9.add(x1).narrow(), int(10));
    assert_eq!(x9.sub(x1).narrow(), int(8));
    assert_eq!(x9.add(x2).narrow(), int(11));
    assert_eq!(x9.sub(x2).narrow(), int(7));
    assert_eq!(x9.add(x3).narrow(), int(12));
    assert_eq!(x9.sub(x3).narrow(), int(6));
    assert_eq!(x9.add(x4).narrow(), int(13));
    assert_eq!(x9.sub(x4).narrow(), int(5));
    assert_eq!(x9.add(x5).narrow(), int(14));
    assert_eq!(x9.sub(x5).narrow(), int(4));
    assert_eq!(x9.add(x6).narrow(), int(15));
    assert_eq!(x9.sub(x6).narrow(), int(3));
    assert_eq!(x9.add(x7).narrow(), int(16));
    assert_eq!(x9.sub(x7).narrow(), int(2));
    assert_eq!(x10.narrow(), int(10));
    assert_eq!(x10.neg().narrow(), int(-10));
    assert_eq!(x10.mul(int(-3)).narrow(), int(-30));
    assert_eq!(x10.lift().narrow(), int(10));
    assert_eq!(x10.add(x1).narrow(), int(11));
    assert_eq!(x10.sub(x1).narrow(), int(9));
    assert_eq!(x10.add(x2).narrow(), int(12));
    assert_eq!(x10.sub(x2).narrow(), int(8));
    assert_eq!(x10.add(x3).narrow(), int(13));
    assert_eq!(x10.sub(x3).narrow(), int(7));
    assert_eq!(x10.add(x4).narrow(), int(14));
    assert_eq!(x10.sub(x4).narrow(), int(6));
    assert_eq!(x10.add(x5).narrow(), int(15));
    assert_eq!(x10.sub(x5).narrow(), int(5));
    assert_eq!(x10.add(x6).narrow(), int(16));
    assert_eq!(x10.sub(x6).narrow(), int(4));
    assert_eq!(x11.narrow(), int(11));
    assert_eq!(x11.neg().narrow(), int(-11));
    assert_eq!(x11.mul(int(-3)).narrow(), int(-33));
    assert_eq!(x11.lift().narrow(), int(11));
    assert_eq!(x11.add(x1).narrow(), int(12));
    assert_eq!(x11.sub(x1).narrow(), int(10));
    assert_eq!(x11.add(x2).narrow(), int(13));
    assert_eq!(x11.sub(x2).narrow(), int(9));
    assert_eq!(x11.add(x3).narrow(), int(14));
    assert_eq!(x11.sub(x3).narrow(), int(8));
    assert_eq!(x11.add(x4).narrow(), int(15));
    assert_eq!(x11.sub(x4).narrow(), int(7));
    assert_eq!(x11.add(x5).narrow(), int(16));
    assert_eq!(x11.sub(x5).narrow(), int(6));
    assert_eq!(x12.narrow(), int(12));
    assert_eq!(x12.neg().narrow(), int(-12));
    assert_eq!(x12.mul(int(-3)).narrow(), int(-36));
    assert_eq!(x12.lift().narrow(), int(12));
    assert_eq!(x12.add(x1).narrow(), int(13));
    assert_eq!(x12.sub(x1).narrow(), int(11));
    assert_eq!(x12.add(x2).narrow(), int(14));
    assert_eq!(x12.sub(x2).narrow(), int(10));
    assert_eq!(x12.add(x3).narrow(), int(15));
    assert_eq!(x12.sub(x3).narrow(), int(9));
    assert_eq!(x12.add(x4).narrow(), int(16));
    assert_eq!(x12.sub(x4).narrow(), int(8));
    assert_eq!(x13.narrow(), int(13));
    assert_eq!(x13.neg().narrow(), int(-13));
    assert_eq!(x13.mul(int(-3)).narrow(), int(-39));
    assert_eq!(x13.lift().narrow(), int(13));
    assert_eq!(x13.add(x1).narrow(), int(14));
    assert_eq!(x13.sub(x1).narrow(), int(12));
    assert_eq!(x13.add(x2).narrow(), int(15));
    assert_eq!(x13.sub(x2).narrow(), int(11));
    assert_eq!(x13.add(x3).narrow(), int(16));
    assert_eq!(x13.sub(x3).narrow(), int(10));
    assert_eq!(x14.narrow(), int(14));
    assert_eq!(x14.neg().narrow(), int(-14));
    assert_eq!(x14.mul(int(-3)).narrow(), int(-42));
    assert_eq!(x14.lift().narrow(), int(14));
    assert_eq!(x14.add(x1).narrow(), int(15));
    assert_eq!(x14.sub(x1).narrow(), int(13));
    assert_eq!(x14.add(x2).narrow(), int(16));
    assert_eq!(x14.sub(x2).narrow(), int(12));
    assert_eq!(x15.narrow(), int(15));
    assert_eq!(x15.neg().narrow(), int(-15));
    assert_eq!(x15.mul(int(-3)).narrow(), int(-45));
    assert_eq!(x15.lift().narrow(), int(15));
    assert_eq!(x15.add(x1).narrow(), int(16));
    assert_eq!(x15.sub(x1).narrow(), int(14));
    assert_eq!(x16.narrow(), int(16));
    assert_eq!(x16.neg().narrow(), int(-16));
    assert_eq!(x16.mul(int(-3)).narrow(), int(-48));
    assert_eq!(x16.lift().narrow(), int(16));
}

// Every `Tn (+|-) Tm`, `neg`, `narrow` impl generated by scripts/gen_bounded.py.
#[test]
fn test_every_t_impl_compiles_and_is_exact() {
    let x1 = wide_mul(opaque(ONE), opaque(ONE)).mul(opaque(ONE));
    let x2 = x1.add(x1);
    let x3 = x2.add(x1);
    let x4 = x3.add(x1);
    let x5 = x4.add(x1);
    let x6 = x5.add(x1);
    let x7 = x6.add(x1);
    let x8 = x7.add(x1);
    let x9 = x8.add(x1);
    let x10 = x9.add(x1);
    let x11 = x10.add(x1);
    let x12 = x11.add(x1);
    let x13 = x12.add(x1);
    let x14 = x13.add(x1);
    let x15 = x14.add(x1);
    let x16 = x15.add(x1);
    assert_eq!(x1.narrow(), int(1));
    assert_eq!(x1.neg().narrow(), int(-1));
    assert_eq!(x1.add(x1).narrow(), int(2));
    assert_eq!(x1.sub(x1).narrow(), int(0));
    assert_eq!(x1.add(x2).narrow(), int(3));
    assert_eq!(x1.sub(x2).narrow(), int(-1));
    assert_eq!(x1.add(x3).narrow(), int(4));
    assert_eq!(x1.sub(x3).narrow(), int(-2));
    assert_eq!(x1.add(x4).narrow(), int(5));
    assert_eq!(x1.sub(x4).narrow(), int(-3));
    assert_eq!(x1.add(x5).narrow(), int(6));
    assert_eq!(x1.sub(x5).narrow(), int(-4));
    assert_eq!(x1.add(x6).narrow(), int(7));
    assert_eq!(x1.sub(x6).narrow(), int(-5));
    assert_eq!(x1.add(x7).narrow(), int(8));
    assert_eq!(x1.sub(x7).narrow(), int(-6));
    assert_eq!(x1.add(x8).narrow(), int(9));
    assert_eq!(x1.sub(x8).narrow(), int(-7));
    assert_eq!(x1.add(x9).narrow(), int(10));
    assert_eq!(x1.sub(x9).narrow(), int(-8));
    assert_eq!(x1.add(x10).narrow(), int(11));
    assert_eq!(x1.sub(x10).narrow(), int(-9));
    assert_eq!(x1.add(x11).narrow(), int(12));
    assert_eq!(x1.sub(x11).narrow(), int(-10));
    assert_eq!(x1.add(x12).narrow(), int(13));
    assert_eq!(x1.sub(x12).narrow(), int(-11));
    assert_eq!(x1.add(x13).narrow(), int(14));
    assert_eq!(x1.sub(x13).narrow(), int(-12));
    assert_eq!(x1.add(x14).narrow(), int(15));
    assert_eq!(x1.sub(x14).narrow(), int(-13));
    assert_eq!(x1.add(x15).narrow(), int(16));
    assert_eq!(x1.sub(x15).narrow(), int(-14));
    assert_eq!(x2.narrow(), int(2));
    assert_eq!(x2.neg().narrow(), int(-2));
    assert_eq!(x2.add(x1).narrow(), int(3));
    assert_eq!(x2.sub(x1).narrow(), int(1));
    assert_eq!(x2.add(x2).narrow(), int(4));
    assert_eq!(x2.sub(x2).narrow(), int(0));
    assert_eq!(x2.add(x3).narrow(), int(5));
    assert_eq!(x2.sub(x3).narrow(), int(-1));
    assert_eq!(x2.add(x4).narrow(), int(6));
    assert_eq!(x2.sub(x4).narrow(), int(-2));
    assert_eq!(x2.add(x5).narrow(), int(7));
    assert_eq!(x2.sub(x5).narrow(), int(-3));
    assert_eq!(x2.add(x6).narrow(), int(8));
    assert_eq!(x2.sub(x6).narrow(), int(-4));
    assert_eq!(x2.add(x7).narrow(), int(9));
    assert_eq!(x2.sub(x7).narrow(), int(-5));
    assert_eq!(x2.add(x8).narrow(), int(10));
    assert_eq!(x2.sub(x8).narrow(), int(-6));
    assert_eq!(x2.add(x9).narrow(), int(11));
    assert_eq!(x2.sub(x9).narrow(), int(-7));
    assert_eq!(x2.add(x10).narrow(), int(12));
    assert_eq!(x2.sub(x10).narrow(), int(-8));
    assert_eq!(x2.add(x11).narrow(), int(13));
    assert_eq!(x2.sub(x11).narrow(), int(-9));
    assert_eq!(x2.add(x12).narrow(), int(14));
    assert_eq!(x2.sub(x12).narrow(), int(-10));
    assert_eq!(x2.add(x13).narrow(), int(15));
    assert_eq!(x2.sub(x13).narrow(), int(-11));
    assert_eq!(x2.add(x14).narrow(), int(16));
    assert_eq!(x2.sub(x14).narrow(), int(-12));
    assert_eq!(x3.narrow(), int(3));
    assert_eq!(x3.neg().narrow(), int(-3));
    assert_eq!(x3.add(x1).narrow(), int(4));
    assert_eq!(x3.sub(x1).narrow(), int(2));
    assert_eq!(x3.add(x2).narrow(), int(5));
    assert_eq!(x3.sub(x2).narrow(), int(1));
    assert_eq!(x3.add(x3).narrow(), int(6));
    assert_eq!(x3.sub(x3).narrow(), int(0));
    assert_eq!(x3.add(x4).narrow(), int(7));
    assert_eq!(x3.sub(x4).narrow(), int(-1));
    assert_eq!(x3.add(x5).narrow(), int(8));
    assert_eq!(x3.sub(x5).narrow(), int(-2));
    assert_eq!(x3.add(x6).narrow(), int(9));
    assert_eq!(x3.sub(x6).narrow(), int(-3));
    assert_eq!(x3.add(x7).narrow(), int(10));
    assert_eq!(x3.sub(x7).narrow(), int(-4));
    assert_eq!(x3.add(x8).narrow(), int(11));
    assert_eq!(x3.sub(x8).narrow(), int(-5));
    assert_eq!(x3.add(x9).narrow(), int(12));
    assert_eq!(x3.sub(x9).narrow(), int(-6));
    assert_eq!(x3.add(x10).narrow(), int(13));
    assert_eq!(x3.sub(x10).narrow(), int(-7));
    assert_eq!(x3.add(x11).narrow(), int(14));
    assert_eq!(x3.sub(x11).narrow(), int(-8));
    assert_eq!(x3.add(x12).narrow(), int(15));
    assert_eq!(x3.sub(x12).narrow(), int(-9));
    assert_eq!(x3.add(x13).narrow(), int(16));
    assert_eq!(x3.sub(x13).narrow(), int(-10));
    assert_eq!(x4.narrow(), int(4));
    assert_eq!(x4.neg().narrow(), int(-4));
    assert_eq!(x4.add(x1).narrow(), int(5));
    assert_eq!(x4.sub(x1).narrow(), int(3));
    assert_eq!(x4.add(x2).narrow(), int(6));
    assert_eq!(x4.sub(x2).narrow(), int(2));
    assert_eq!(x4.add(x3).narrow(), int(7));
    assert_eq!(x4.sub(x3).narrow(), int(1));
    assert_eq!(x4.add(x4).narrow(), int(8));
    assert_eq!(x4.sub(x4).narrow(), int(0));
    assert_eq!(x4.add(x5).narrow(), int(9));
    assert_eq!(x4.sub(x5).narrow(), int(-1));
    assert_eq!(x4.add(x6).narrow(), int(10));
    assert_eq!(x4.sub(x6).narrow(), int(-2));
    assert_eq!(x4.add(x7).narrow(), int(11));
    assert_eq!(x4.sub(x7).narrow(), int(-3));
    assert_eq!(x4.add(x8).narrow(), int(12));
    assert_eq!(x4.sub(x8).narrow(), int(-4));
    assert_eq!(x4.add(x9).narrow(), int(13));
    assert_eq!(x4.sub(x9).narrow(), int(-5));
    assert_eq!(x4.add(x10).narrow(), int(14));
    assert_eq!(x4.sub(x10).narrow(), int(-6));
    assert_eq!(x4.add(x11).narrow(), int(15));
    assert_eq!(x4.sub(x11).narrow(), int(-7));
    assert_eq!(x4.add(x12).narrow(), int(16));
    assert_eq!(x4.sub(x12).narrow(), int(-8));
    assert_eq!(x5.narrow(), int(5));
    assert_eq!(x5.neg().narrow(), int(-5));
    assert_eq!(x5.add(x1).narrow(), int(6));
    assert_eq!(x5.sub(x1).narrow(), int(4));
    assert_eq!(x5.add(x2).narrow(), int(7));
    assert_eq!(x5.sub(x2).narrow(), int(3));
    assert_eq!(x5.add(x3).narrow(), int(8));
    assert_eq!(x5.sub(x3).narrow(), int(2));
    assert_eq!(x5.add(x4).narrow(), int(9));
    assert_eq!(x5.sub(x4).narrow(), int(1));
    assert_eq!(x5.add(x5).narrow(), int(10));
    assert_eq!(x5.sub(x5).narrow(), int(0));
    assert_eq!(x5.add(x6).narrow(), int(11));
    assert_eq!(x5.sub(x6).narrow(), int(-1));
    assert_eq!(x5.add(x7).narrow(), int(12));
    assert_eq!(x5.sub(x7).narrow(), int(-2));
    assert_eq!(x5.add(x8).narrow(), int(13));
    assert_eq!(x5.sub(x8).narrow(), int(-3));
    assert_eq!(x5.add(x9).narrow(), int(14));
    assert_eq!(x5.sub(x9).narrow(), int(-4));
    assert_eq!(x5.add(x10).narrow(), int(15));
    assert_eq!(x5.sub(x10).narrow(), int(-5));
    assert_eq!(x5.add(x11).narrow(), int(16));
    assert_eq!(x5.sub(x11).narrow(), int(-6));
    assert_eq!(x6.narrow(), int(6));
    assert_eq!(x6.neg().narrow(), int(-6));
    assert_eq!(x6.add(x1).narrow(), int(7));
    assert_eq!(x6.sub(x1).narrow(), int(5));
    assert_eq!(x6.add(x2).narrow(), int(8));
    assert_eq!(x6.sub(x2).narrow(), int(4));
    assert_eq!(x6.add(x3).narrow(), int(9));
    assert_eq!(x6.sub(x3).narrow(), int(3));
    assert_eq!(x6.add(x4).narrow(), int(10));
    assert_eq!(x6.sub(x4).narrow(), int(2));
    assert_eq!(x6.add(x5).narrow(), int(11));
    assert_eq!(x6.sub(x5).narrow(), int(1));
    assert_eq!(x6.add(x6).narrow(), int(12));
    assert_eq!(x6.sub(x6).narrow(), int(0));
    assert_eq!(x6.add(x7).narrow(), int(13));
    assert_eq!(x6.sub(x7).narrow(), int(-1));
    assert_eq!(x6.add(x8).narrow(), int(14));
    assert_eq!(x6.sub(x8).narrow(), int(-2));
    assert_eq!(x6.add(x9).narrow(), int(15));
    assert_eq!(x6.sub(x9).narrow(), int(-3));
    assert_eq!(x6.add(x10).narrow(), int(16));
    assert_eq!(x6.sub(x10).narrow(), int(-4));
    assert_eq!(x7.narrow(), int(7));
    assert_eq!(x7.neg().narrow(), int(-7));
    assert_eq!(x7.add(x1).narrow(), int(8));
    assert_eq!(x7.sub(x1).narrow(), int(6));
    assert_eq!(x7.add(x2).narrow(), int(9));
    assert_eq!(x7.sub(x2).narrow(), int(5));
    assert_eq!(x7.add(x3).narrow(), int(10));
    assert_eq!(x7.sub(x3).narrow(), int(4));
    assert_eq!(x7.add(x4).narrow(), int(11));
    assert_eq!(x7.sub(x4).narrow(), int(3));
    assert_eq!(x7.add(x5).narrow(), int(12));
    assert_eq!(x7.sub(x5).narrow(), int(2));
    assert_eq!(x7.add(x6).narrow(), int(13));
    assert_eq!(x7.sub(x6).narrow(), int(1));
    assert_eq!(x7.add(x7).narrow(), int(14));
    assert_eq!(x7.sub(x7).narrow(), int(0));
    assert_eq!(x7.add(x8).narrow(), int(15));
    assert_eq!(x7.sub(x8).narrow(), int(-1));
    assert_eq!(x7.add(x9).narrow(), int(16));
    assert_eq!(x7.sub(x9).narrow(), int(-2));
    assert_eq!(x8.narrow(), int(8));
    assert_eq!(x8.neg().narrow(), int(-8));
    assert_eq!(x8.add(x1).narrow(), int(9));
    assert_eq!(x8.sub(x1).narrow(), int(7));
    assert_eq!(x8.add(x2).narrow(), int(10));
    assert_eq!(x8.sub(x2).narrow(), int(6));
    assert_eq!(x8.add(x3).narrow(), int(11));
    assert_eq!(x8.sub(x3).narrow(), int(5));
    assert_eq!(x8.add(x4).narrow(), int(12));
    assert_eq!(x8.sub(x4).narrow(), int(4));
    assert_eq!(x8.add(x5).narrow(), int(13));
    assert_eq!(x8.sub(x5).narrow(), int(3));
    assert_eq!(x8.add(x6).narrow(), int(14));
    assert_eq!(x8.sub(x6).narrow(), int(2));
    assert_eq!(x8.add(x7).narrow(), int(15));
    assert_eq!(x8.sub(x7).narrow(), int(1));
    assert_eq!(x8.add(x8).narrow(), int(16));
    assert_eq!(x8.sub(x8).narrow(), int(0));
    assert_eq!(x9.narrow(), int(9));
    assert_eq!(x9.neg().narrow(), int(-9));
    assert_eq!(x9.add(x1).narrow(), int(10));
    assert_eq!(x9.sub(x1).narrow(), int(8));
    assert_eq!(x9.add(x2).narrow(), int(11));
    assert_eq!(x9.sub(x2).narrow(), int(7));
    assert_eq!(x9.add(x3).narrow(), int(12));
    assert_eq!(x9.sub(x3).narrow(), int(6));
    assert_eq!(x9.add(x4).narrow(), int(13));
    assert_eq!(x9.sub(x4).narrow(), int(5));
    assert_eq!(x9.add(x5).narrow(), int(14));
    assert_eq!(x9.sub(x5).narrow(), int(4));
    assert_eq!(x9.add(x6).narrow(), int(15));
    assert_eq!(x9.sub(x6).narrow(), int(3));
    assert_eq!(x9.add(x7).narrow(), int(16));
    assert_eq!(x9.sub(x7).narrow(), int(2));
    assert_eq!(x10.narrow(), int(10));
    assert_eq!(x10.neg().narrow(), int(-10));
    assert_eq!(x10.add(x1).narrow(), int(11));
    assert_eq!(x10.sub(x1).narrow(), int(9));
    assert_eq!(x10.add(x2).narrow(), int(12));
    assert_eq!(x10.sub(x2).narrow(), int(8));
    assert_eq!(x10.add(x3).narrow(), int(13));
    assert_eq!(x10.sub(x3).narrow(), int(7));
    assert_eq!(x10.add(x4).narrow(), int(14));
    assert_eq!(x10.sub(x4).narrow(), int(6));
    assert_eq!(x10.add(x5).narrow(), int(15));
    assert_eq!(x10.sub(x5).narrow(), int(5));
    assert_eq!(x10.add(x6).narrow(), int(16));
    assert_eq!(x10.sub(x6).narrow(), int(4));
    assert_eq!(x11.narrow(), int(11));
    assert_eq!(x11.neg().narrow(), int(-11));
    assert_eq!(x11.add(x1).narrow(), int(12));
    assert_eq!(x11.sub(x1).narrow(), int(10));
    assert_eq!(x11.add(x2).narrow(), int(13));
    assert_eq!(x11.sub(x2).narrow(), int(9));
    assert_eq!(x11.add(x3).narrow(), int(14));
    assert_eq!(x11.sub(x3).narrow(), int(8));
    assert_eq!(x11.add(x4).narrow(), int(15));
    assert_eq!(x11.sub(x4).narrow(), int(7));
    assert_eq!(x11.add(x5).narrow(), int(16));
    assert_eq!(x11.sub(x5).narrow(), int(6));
    assert_eq!(x12.narrow(), int(12));
    assert_eq!(x12.neg().narrow(), int(-12));
    assert_eq!(x12.add(x1).narrow(), int(13));
    assert_eq!(x12.sub(x1).narrow(), int(11));
    assert_eq!(x12.add(x2).narrow(), int(14));
    assert_eq!(x12.sub(x2).narrow(), int(10));
    assert_eq!(x12.add(x3).narrow(), int(15));
    assert_eq!(x12.sub(x3).narrow(), int(9));
    assert_eq!(x12.add(x4).narrow(), int(16));
    assert_eq!(x12.sub(x4).narrow(), int(8));
    assert_eq!(x13.narrow(), int(13));
    assert_eq!(x13.neg().narrow(), int(-13));
    assert_eq!(x13.add(x1).narrow(), int(14));
    assert_eq!(x13.sub(x1).narrow(), int(12));
    assert_eq!(x13.add(x2).narrow(), int(15));
    assert_eq!(x13.sub(x2).narrow(), int(11));
    assert_eq!(x13.add(x3).narrow(), int(16));
    assert_eq!(x13.sub(x3).narrow(), int(10));
    assert_eq!(x14.narrow(), int(14));
    assert_eq!(x14.neg().narrow(), int(-14));
    assert_eq!(x14.add(x1).narrow(), int(15));
    assert_eq!(x14.sub(x1).narrow(), int(13));
    assert_eq!(x14.add(x2).narrow(), int(16));
    assert_eq!(x14.sub(x2).narrow(), int(12));
    assert_eq!(x15.narrow(), int(15));
    assert_eq!(x15.neg().narrow(), int(-15));
    assert_eq!(x15.add(x1).narrow(), int(16));
    assert_eq!(x15.sub(x1).narrow(), int(14));
    assert_eq!(x16.narrow(), int(16));
    assert_eq!(x16.neg().narrow(), int(-16));
}
