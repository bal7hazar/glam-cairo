"""Test template (`packages/glam/tests/test_<m>.cairo`) of tools/codegen/intvec.py.

Three layers, as in docs/DESIGN.md section 5:
  * the glam-rs test cases of `tests/vec{2,3,4}.rs` (`impl_vecN_tests!`, `_signed_tests!`,
    `_signed_integer_tests!` / `_unsigned_integer_tests!`, the wrapping / saturating macros),
    ported literally;
  * tables over a pool of edge values (0, +-1, MIN, MAX, 2^16, 2^31 ...): the expected values are
    computed here with Python integers, the oracle of two's complement arithmetic;
  * seeded fuzz properties against an `i128` reference written in the test file, and one
    `#[should_panic]` per panic path with the exact message.
"""
import intvec as g

MIN, MAX, UMAX = g.I32_MIN, g.I32_MAX, g.U32_MAX


# --------------------------------------------------------------------------------------------
# Reference semantics (Rust i32 / u32)
# --------------------------------------------------------------------------------------------
def wrap(t, v):
    v &= 0xFFFFFFFF
    return v - 2**32 if t.signed and v >= 2**31 else v


def sat(t, v):
    return max(t.smin, min(t.smax, v))


def fits(t, v):
    return t.smin <= v <= t.smax


def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def trem(a, b):
    return a - b * tdiv(a, b)


def div_euclid(a, b):
    r = a % abs(b)
    return (a - r) // b


def rem_euclid(a, b):
    return a % abs(b)


# --------------------------------------------------------------------------------------------
# Emit helpers
# --------------------------------------------------------------------------------------------
def num(v):
    return str(v)


class Gen:
    def __init__(self, t):
        self.t = t
        self.out = []

    def V(self, vals, t=None):
        t = t or self.t
        return f"{t.mod}(" + ", ".join(num(v) for v in list(vals)[:t.n]) + ")"

    def B(self, vals):
        return f"{self.t.bmod}(" + ", ".join("true" if v else "false"
                                             for v in list(vals)[:self.t.n]) + ")"

    def test(self, name, lines, attrs=()):
        body = "\n".join("    " + l for l in lines)
        a = "".join(f"#[{x}]\n" for x in attrs)
        self.out.append(f"#[test]\n{a}fn {name}() {{\n{body}\n}}\n")

    def panic(self, name, msg, lines):
        self.test(name, lines, attrs=[f"should_panic(expected: {msg})"])


def pairs(t):
    """Vector pairs cycling through the pool of edge values: every pool value meets every
    other one on some component."""
    pool = ([MIN, MIN + 1, -65536, -46341, -7, -1, 0, 1, 2, 5, 46340, 65536, MAX - 1, MAX]
            if t.signed else
            [0, 1, 2, 7, 65535, 65536, 2**31 - 1, 2**31, 2**31 + 1, UMAX - 1, UMAX])
    k = len(pool)
    out = []
    for i in range(k):
        for step in (1, 3, 5):
            a = [pool[(i + j) % k] for j in range(4)]
            b = [pool[(i * step + 2 * j + step) % k] for j in range(4)]
            out.append((a, b))
    return out


def small_pairs(t):
    if t.signed:
        return [([3, -7, 11, -13], [-5, 2, 9, 4]), ([-1, -2, -3, -4], [4, 3, 2, 1]),
                ([0, 1, -1, 2], [7, -7, 7, -7]), ([100, -200, 300, -400], [-9, 8, -7, 6]),
                ([46340, -3, 1, 0], [46340, 5, -1, 5])]
    return [([30, 7, 110, 13], [5, 2, 9, 4]), ([1, 2, 3, 4], [4, 3, 2, 1]),
            ([0, 1, 5, 2], [7, 9, 7, 3]), ([100, 200, 300, 400], [9, 8, 7, 6]),
            ([65535, 3, 1, 0], [65535, 5, 1, 5])]


def gen_tests(t):
    T, S, n, o, s = t.name, t.S, t.n, t.other, t.signed
    G = Gen(t)
    V, Bm, test, panic = G.V, G.B, G.test, G.panic
    cs = t.c
    eq = lambda a, b: f"assert_eq!({a}, {b});"
    cwl = lambda f, a, b=None: [f(a[i], b[i]) if b is not None else f(a[i]) for i in range(4)]

    # ---------------------------------------------------------------- glam-rs: impl_vecN_tests
    one = [1, 2, 3, 4]
    test("test_new", [
        f"let v = {T}Trait::new({', '.join(map(str, one[:n]))});",
        *[eq(f"v.{c}", one[i]) for i, c in enumerate(cs)],
        eq("v", V(one)),
        f"let t = ({', '.join(f'{x}_{S}' for x in one[:n])});",
        f"let v: {T} = t.into();", eq("v", V(one)),
        f"let t2: ({', '.join([S] * n)}) = v.into();", eq("t2", "t"),
        f"let a = [{', '.join(f'{x}_{S}' for x in one[:n])}];",
        f"let v: {T} = a.into();", eq("v", V(one)), eq(f"{T}Trait::from_array(a)", V(one)),
        f"let a2: [{S}; {n}] = v.into();", eq("a2", "a"), eq("v.to_array()", "a"),
        eq(f"Default::<{T}>::default()", f"{T}Trait::ZERO"),
    ])
    unit = lambda i, v=1: [v if j == i else 0 for j in range(4)]
    lines = [eq(f"{T}Trait::ZERO", V([0] * 4)), eq(f"{T}Trait::ONE", V([1] * 4)),
             eq(f"{T}Trait::MIN", V([t.smin] * 4)), eq(f"{T}Trait::MAX", V([t.smax] * 4))]
    lines += [eq(f"{T}Trait::{c.upper()}", V(unit(i))) for i, c in enumerate(cs)]
    if s:
        lines += [eq(f"{T}Trait::NEG_ONE", V([-1] * 4))]
        lines += [eq(f"{T}Trait::NEG_{c.upper()}", V(unit(i, -1))) for i, c in enumerate(cs)]
    lines += [f"let [{', '.join('a' + c for c in cs)}] = {T}Trait::AXES;"]
    lines += [eq(f"a{c}", f"{T}Trait::{c.upper()}") for c in cs]
    test("test_consts", lines)
    test("test_splat", [eq(f"{T}Trait::splat(7)", V([7] * 4)),
                        eq(f"{T}Trait::splat({t.smin})", f"{T}Trait::MIN")])
    test("test_with", [
        *[eq(f"{V(one)}.with_{c}(9)", V([9 if j == i else one[j] for j in range(4)]))
          for i, c in enumerate(cs)]])
    test("test_accessors", [
        f"let mut a = {T}Trait::ZERO;",
        *[f"a.{c} = {one[i]};" for i, c in enumerate(cs)],
        eq("a", V(one)),
        *[eq(f"a[{i}]", one[i]) for i in range(n)],
    ])
    panic("test_index_out_of_bounds", f"'{T}: index out of bounds'",
          [f"let _ = {V(one)}[{n}];"])
    lines = []
    if n < 4:
        lines.append(eq(f"{V(one)}.extend({one[n]})", V(one, t.dim(n + 1))))
    if n > 2:
        lines.append(eq(f"{V(one)}.truncate()", V(one, t.dim(n - 1))))
    if n == 3:
        lines += [f"let v: {T} = ({V(one, t.dim(2))}, 3_{S}).into();", eq("v", V(one))]
    if n == 4:
        lines += [f"let v: {T} = ({V(one, t.dim(3))}, 4_{S}).into();", eq("v", V(one)),
                  f"let v: {T} = (1_{S}, {V([2, 3, 4], t.dim(3))}).into();", eq("v", V(one)),
                  f"let v: {T} = ({V(one, t.dim(2))}, 3_{S}, 4_{S}).into();", eq("v", V(one)),
                  f"let v: {T} = ({V(one, t.dim(2))}, {V([3, 4], t.dim(2))}).into();",
                  eq("v", V(one))]
    test("test_extend_truncate", lines)
    a, b = [1, 2, 3, 4], [5, 6, 7, 8]
    lines = []
    for m in range(2**n):
        bits = [(m >> i) & 1 for i in range(4)]
        lines.append(eq(f"{T}Trait::select({Bm(bits)}, {V(a)}, {V(b)})",
                        V([a[i] if bits[i] else b[i] for i in range(4)])))
    test("test_select", lines)
    lines = [f"let v: {T} = {Bm([1, 0, 1, 0])}.into();", eq("v", V([1, 0, 1, 0])),
             f"let v: {T} = {Bm([0, 1, 0, 1])}.into();", eq("v", V([0, 1, 0, 1]))]
    test("test_from_bvec", lines)

    # dot / length / cross (glam: test_dot_unsigned, test_length_squared_unsigned, test_cross)
    lines = [eq(f"{T}Trait::X.dot({T}Trait::X)", 1), eq(f"{T}Trait::X.dot({T}Trait::Y)", 0)]
    for a, b in small_pairs(t):
        d = sum(a[i] * b[i] for i in range(n))
        lines.append(eq(f"{V(a)}.dot({V(b)})", d))
        lines.append(eq(f"{V(a)}.dot_into_vec({V(b)})", V([d] * 4)))
        lines.append(eq(f"{V(a)}.length_squared()", sum(a[i] * a[i] for i in range(n))))
        if s:
            lines.append(eq(f"{V(a)}.distance_squared({V(b)})",
                            sum((a[i] - b[i])**2 for i in range(n))))
    test("test_dot_length", lines)
    if n == 3:
        cross = lambda a, b: [a[1] * b[2] - b[1] * a[2], a[2] * b[0] - b[2] * a[0],
                              a[0] * b[1] - b[0] * a[1], 0]
        lines = [eq(f"{T}Trait::X.cross({T}Trait::Y)", f"{T}Trait::Z"),
                 eq(f"{T}Trait::Y.cross({T}Trait::Z)", f"{T}Trait::X"),
                 eq(f"{T}Trait::Z.cross({T}Trait::X)", f"{T}Trait::Y")]
        if s:
            lines += [eq(f"{T}Trait::Y.cross({T}Trait::X)", f"{T}Trait::NEG_Z")]
            lines += [eq(f"{V(a)}.cross({V(b)})", V(cross(a, b))) for a, b in small_pairs(t)]
            lines += [eq(f"{V([46340, 0, 0])}.cross({V([0, 46340, 1])})",
                         V(cross([46340, 0, 0], [0, 46340, 1])))]
        else:
            lines += [eq(f"{V([3, 0, 0])}.cross({V([2, 5, 0])})", V([0, 0, 15]))]
        test("test_cross", lines)
    if s and n == 2:
        lines = [eq(f"{T}Trait::X.perp()", f"{T}Trait::Y"),
                 eq(f"{T}Trait::Y.perp()", f"{T}Trait::NEG_X"),
                 eq(f"{T}Trait::X.perp_dot({T}Trait::Y)", 1),
                 eq(f"{T}Trait::Y.perp_dot({T}Trait::X)", -1),
                 eq(f"{T}Trait::Y.rotate({T}Trait::X)", f"{T}Trait::Y"),
                 eq(f"{T}Trait::NEG_X.rotate({V([3, 4])})", V([-3, -4]))]
        for a, b in small_pairs(t):
            lines.append(eq(f"{V(a)}.perp()", V([-a[1], a[0]])))
            lines.append(eq(f"{V(a)}.perp_dot({V(b)})", a[0] * b[1] - a[1] * b[0]))
            lines.append(eq(f"{V(a)}.rotate({V(b)})",
                            V([a[0] * b[0] - a[1] * b[1], a[1] * b[0] + a[0] * b[1]])))
        test("test_perp_rotate", lines)

    # test_ops / test_assign_ops
    a = [2, 4, 8, 16]
    lines = [f"let a = {V(a)};",
             eq("a + a", V([4, 8, 16, 32])), eq("a - a", V([0] * 4)),
             eq("a * a", V([4, 16, 64, 256])), eq("a / a", V([1] * 4)),
             eq("a % a", V([0] * 4)),
             eq("a.add_scalar(2)", V([4, 6, 10, 18])), eq("a.sub_scalar(2)", V([0, 2, 6, 14])),
             eq("a.mul_scalar(2)", V([4, 8, 16, 32])), eq("a.div_scalar(2)", V([1, 2, 4, 8])),
             eq("a.rem_scalar(3)", V([2, 1, 2, 1]))]
    for x, y in small_pairs(t):
        if not s:
            x, y = [max(x[i], y[i]) for i in range(4)], [min(x[i], y[i]) or 1 for i in range(4)]
        lines += [eq(f"{V(x)} + {V(y)}", V(cwl(lambda p, q: p + q, x, y))),
                  eq(f"{V(x)} - {V(y)}", V(cwl(lambda p, q: p - q, x, y))),
                  eq(f"{V(x)} * {V(y)}", V(cwl(lambda p, q: p * q, x, y))),
                  eq(f"{V(x)} / {V(y)}", V(cwl(tdiv, x, y))),
                  eq(f"{V(x)} % {V(y)}", V(cwl(trem, x, y))),
                  eq(f"{V(x)}.div_scalar({y[0]})", V(cwl(lambda p: tdiv(p, y[0]), x))),
                  eq(f"{V(x)}.rem_scalar({y[0]})", V(cwl(lambda p: trem(p, y[0]), x)))]
    test("test_ops", lines)
    lines = []
    for sym, f in [("+", lambda p, q: p + q), ("-", lambda p, q: p - q),
                   ("*", lambda p, q: p * q), ("/", tdiv), ("%", trem)]:
        x, y = [20, 40, 80, 160], [2, 3, 7, 9]
        lines += [f"let mut a = {V(x)};", f"a {sym}= {V(y)};", eq("a", V(cwl(f, x, y))),
                  f"let mut a = {V(x)};", f"a {sym}= 3;", eq("a", V(cwl(lambda p: f(p, 3), x)))]
    test("test_assign_ops", lines)

    # min / max / clamp / reductions (glam cases, then the pool)
    a, b = [3, 5, 1, 7], [4, 2, 6, 0]
    test("test_min_max", [
        eq(f"{V(a)}.min({V(b)})", V(cwl(min, a, b))), eq(f"{V(b)}.min({V(a)})", V(cwl(min, a, b))),
        eq(f"{V(a)}.max({V(b)})", V(cwl(max, a, b))), eq(f"{V(b)}.max({V(a)})", V(cwl(max, a, b))),
        *[l for x, y in pairs(t) for l in (
            eq(f"{V(x)}.min({V(y)})", V(cwl(min, x, y))),
            eq(f"{V(x)}.max({V(y)})", V(cwl(max, x, y))))]])
    argmin = lambda v: min(range(n), key=lambda i: (v[i], i))
    argmax = lambda v: min(range(n), key=lambda i: (-v[i], i))
    lines = []
    glam_pos = {2: [[1, 2], [1, 1], [2, 1]],
                3: [[1, 2, 3], [1, 1, 1], [3, 2, 1], [1, 2, 1], [1, 0, 1]],
                4: [[1, 2, 3, 4], [1, 1, 1, 1], [4, 3, 2, 1], [1, 2, 1, 2], [1, 0, 1, 0],
                    [2, 2, 1, 1], [3, 3, 3, 4]]}[n]
    for v in glam_pos + [x[:n] for x, _ in pairs(t)]:
        v = list(v) + [0] * (4 - len(v))
        lines += [eq(f"{V(v)}.min_position()", argmin(v)), eq(f"{V(v)}.max_position()", argmax(v)),
                  eq(f"{V(v)}.min_element()", min(v[:n])), eq(f"{V(v)}.max_element()", max(v[:n]))]
    test("test_min_position_max_position_hmin_hmax", lines)
    lo, hi = [1, 3, 3, 2], [6, 8, 8, 9]
    clamp = lambda v: [min(max(v[i], lo[i]), hi[i]) for i in range(4)]
    lines = [eq(f"{V([k] * 4)}.clamp({V(lo)}, {V(hi)})", V(clamp([k] * 4)))
             for k in [0, 2, 4, 5, 6, 7, 9]]
    lines += [eq(f"{T}Trait::MIN.clamp({V(lo)}, {V(hi)})", V(lo)),
              eq(f"{T}Trait::MAX.clamp({V(lo)}, {V(hi)})", V(hi)),
              eq(f"{V(lo)}.clamp({T}Trait::MIN, {T}Trait::MAX)", V(lo))]
    test("test_clamp", lines)
    lines = [eq(f"{V(one)}.element_sum()", sum(one[:n])),
             eq(f"{V(one)}.element_product()", [0, 0, 2, 6, 24][n])]
    for x, _ in small_pairs(t)[:4]:
        p = 1
        for k in x[:n]:
            p *= k
        lines.append(eq(f"{V(x)}.element_sum()", sum(x[:n])))
        if fits(t, p):
            lines.append(eq(f"{V(x)}.element_product()", p))
    test("test_sum_product", lines)

    # comparisons
    lines = [f"let a = {V([1] * 4)};", f"let b = {V([2] * 4)};",
             "assert!(a.cmplt(b).all());", "assert!(a.cmple(b).all());",
             "assert!(b.cmpgt(a).all());", "assert!(b.cmpge(a).all());",
             "assert!(a.cmpne(b).all());", "assert!(a.cmpeq(a).all());",
             "assert!(!a.cmpeq(b).any());", "assert!(a.cmple(a).all());",
             "assert!(a.cmpge(a).all());", "assert!(!a.cmplt(a).any());",
             "assert!(a == a);", "assert!(a != b);"]
    for x, y in pairs(t):
        for f, op in [("cmpeq", lambda p, q: p == q), ("cmpne", lambda p, q: p != q),
                      ("cmpge", lambda p, q: p >= q), ("cmpgt", lambda p, q: p > q),
                      ("cmple", lambda p, q: p <= q), ("cmplt", lambda p, q: p < q)]:
            lines.append(eq(f"{V(x)}.{f}({V(y)})", Bm(cwl(op, x, y))))
    test("test_cmp", lines)

    # ------------------------------------------------------------------------------- signed
    if s:
        test("test_neg", [
            eq(f"-{V(one)}", V([-k for k in one])), eq(f"-{T}Trait::ZERO", f"{T}Trait::ZERO"),
            eq(f"-{T}Trait::MAX", V([-MAX] * 4)), eq(f"-{T}Trait::ONE", f"{T}Trait::NEG_ONE")])
        lines = []
        for m in range(2**n):
            v = [-(i + 1) if (m >> i) & 1 else i + 1 for i in range(4)]
            lines += [eq(f"{V(v)}.is_negative_bitmask()", m),
                      eq(f"{V(v)}.is_negative_mask()", Bm([(m >> i) & 1 for i in range(4)]))]
        lines += [eq(f"{T}Trait::ZERO.is_negative_bitmask()", 0),
                  eq(f"{T}Trait::MIN.is_negative_bitmask()", 2**n - 1),
                  eq(f"{T}Trait::MAX.is_negative_bitmask()", 0)]
        test("test_is_negative", lines)
        lines = [eq(f"{T}Trait::ZERO.abs()", f"{T}Trait::ZERO"),
                 eq(f"{T}Trait::ONE.abs()", f"{T}Trait::ONE"),
                 eq(f"{T}Trait::NEG_ONE.abs()", f"{T}Trait::ONE"),
                 eq(f"{T}Trait::ZERO.signum()", f"{T}Trait::ZERO"),
                 eq(f"{T}Trait::ONE.signum()", f"{T}Trait::ONE"),
                 eq(f"{T}Trait::NEG_ONE.signum()", f"{T}Trait::NEG_ONE"),
                 eq(f"{T}Trait::MIN.signum()", f"{T}Trait::NEG_ONE"),
                 eq(f"{T}Trait::MAX.signum()", f"{T}Trait::ONE")]
        for x, _ in pairs(t):
            sg = lambda p: (p > 0) - (p < 0)
            lines.append(eq(f"{V(x)}.signum()", V(cwl(sg, x))))
            if MIN not in x[:n]:
                lines.append(eq(f"{V(x)}.abs()", V(cwl(abs, x))))
        test("test_abs_signum", lines)
        # glam: test_div_euclid / test_rem_euclid, then every sign combination and the extremes
        lines = [f"let one = {T}Trait::ONE;", "let two = one + one;", "let three = two + one;",
                 "let four = three + one;",
                 eq("three.div_euclid(two)", "one"), eq("(-three).div_euclid(two)", "-two"),
                 eq("three.div_euclid(-two)", "-one"), eq("(-three).div_euclid(-two)", "two"),
                 eq("four.rem_euclid(three)", "one"), eq("(-four).rem_euclid(three)", "two"),
                 eq("four.rem_euclid(-three)", "one"), eq("(-four).rem_euclid(-three)", "two")]
        for x, y in pairs(t):
            y = [k if k != 0 else 3 for k in y]
            if any(x[i] == MIN and y[i] == -1 for i in range(n)):
                continue
            lines += [eq(f"{V(x)}.div_euclid({V(y)})", V(cwl(div_euclid, x, y))),
                      eq(f"{V(x)}.rem_euclid({V(y)})", V(cwl(rem_euclid, x, y)))]
        lines += [eq(f"{T}Trait::MIN.rem_euclid({T}Trait::NEG_ONE)", f"{T}Trait::ZERO"),
                  eq(f"{T}Trait::MIN.div_euclid({T}Trait::MIN)", f"{T}Trait::ONE"),
                  eq(f"{T}Trait::MAX.div_euclid({T}Trait::MIN)", f"{T}Trait::ZERO"),
                  eq(f"{T}Trait::MAX.rem_euclid({T}Trait::MIN)", f"{T}Trait::MAX"),
                  eq(f"{T}Trait::MIN.div_euclid({T}Trait::ONE)", f"{T}Trait::MIN")]
        test("test_div_euclid_rem_euclid", lines)
        lines = []
        for x, y in pairs(t):
            y = [k if k != 0 else 3 for k in y]
            if any(x[i] == MIN and y[i] == -1 for i in range(n)):
                continue
            lines += [eq(f"{V(x)} / {V(y)}", V(cwl(tdiv, x, y))),
                      eq(f"{V(x)} % {V(y)}", V(cwl(trem, x, y)))]
        test("test_div_rem_truncated", lines)

    # --------------------------------------------------- checked / wrapping / saturating
    Tt = f"{T}Trait"
    some = lambda v: f"Some({v})"
    lines = [eq(f"{Tt}::MAX.checked_add({Tt}::ONE)", "None"),
             *[eq(f"{Tt}::MAX.checked_add({Tt}::{c.upper()})", "None") for c in cs],
             eq(f"{Tt}::MAX.checked_add({Tt}::ZERO)", some(f"{Tt}::MAX")),
             eq(f"{Tt}::MIN.checked_sub({Tt}::ONE)", "None"),
             *[eq(f"{Tt}::MIN.checked_sub({Tt}::{c.upper()})", "None") for c in cs],
             eq(f"{Tt}::MIN.checked_sub({Tt}::ZERO)", some(f"{Tt}::MIN")),
             eq(f"{Tt}::MAX.checked_mul({Tt}::MAX)", "None"),
             eq(f"{Tt}::MAX.checked_mul({Tt}::ZERO)", some(f"{Tt}::ZERO")),
             eq(f"{Tt}::MAX.checked_mul({Tt}::ONE)", some(f"{Tt}::MAX")),
             eq(f"{Tt}::ZERO.checked_mul({Tt}::ZERO)", some(f"{Tt}::ZERO")),
             eq(f"{Tt}::ONE.checked_mul({Tt}::ONE)", some(f"{Tt}::ONE")),
             eq(f"{Tt}::MAX.checked_div({Tt}::ZERO)", "None"),
             *[eq(f"{Tt}::MAX.checked_div({Tt}::{c.upper()})", "None") for c in cs],
             eq(f"{Tt}::ZERO.checked_div({Tt}::ONE)", some(f"{Tt}::ZERO")),
             eq(f"{Tt}::MAX.checked_div({Tt}::ONE)", some(f"{Tt}::MAX"))]
    if s:
        lines += [eq(f"{Tt}::MIN.checked_mul({Tt}::MIN)", "None"),
                  eq(f"{Tt}::MAX.checked_mul({Tt}::MIN)", "None"),
                  eq(f"{Tt}::MIN.checked_mul({Tt}::MAX)", "None"),
                  eq(f"{Tt}::ZERO.checked_mul({Tt}::MIN)", some(f"{Tt}::ZERO")),
                  eq(f"{Tt}::MIN.checked_mul({Tt}::ONE)", some(f"{Tt}::MIN")),
                  eq(f"{Tt}::MIN.checked_div({Tt}::ZERO)", "None"),
                  eq(f"{Tt}::MIN.checked_div({Tt}::ONE)", some(f"{Tt}::MIN")),
                  eq(f"{Tt}::MIN.checked_div({Tt}::NEG_ONE)", "None"),
                  eq(f"{Tt}::MAX.checked_div({Tt}::NEG_ONE)", some(V([-MAX] * 4)))]
    test("test_checked", lines)

    ops = {"add": lambda p, q: p + q, "sub": lambda p, q: p - q, "mul": lambda p, q: p * q}
    for kind in ["checked", "wrapping", "saturating"]:
        lines = []
        for x, y in pairs(t):
            for op, f in ops.items():
                exact = cwl(f, x, y)
                if kind == "checked":
                    e = some(V(exact)) if all(fits(t, k) for k in exact[:n]) else "None"
                elif kind == "wrapping":
                    e = V([wrap(t, k) for k in exact])
                else:
                    e = V([sat(t, k) for k in exact])
                lines.append(eq(f"{V(x)}.{kind}_{op}({V(y)})", e))
            if kind == "checked":
                bad = any(y[i] == 0 or (x[i] == MIN and y[i] == -1) for i in range(n))
                yy = [k if i < n else 1 for i, k in enumerate(y)]
                e = "None" if bad else some(V(cwl(tdiv, x, yy)))
                lines.append(eq(f"{V(x)}.checked_div({V(y)})", e))
            else:
                yy = [k if k != 0 else 3 for k in y]
                q = [(MIN if kind == "wrapping" else MAX) if (x[i] == MIN and yy[i] == -1)
                     else tdiv(x[i], yy[i]) for i in range(4)]
                lines.append(eq(f"{V(x)}.{kind}_div({V(yy)})", V(q)))
        test(f"test_{kind}_pool", lines)

    # glam: impl_vec_wrapping_test / impl_{signed,unsigned}_saturating_tests
    w = {2: ([t.smax, 5], [1, 3]), 3: ([t.smax, 0, 5], [1, 2, 3]),
         4: ([t.smax, 0, 5, 4], [1, 2, 3, 2])}[n]
    x, y = [k for k in w[0]] + [0] * 4, [k for k in w[1]] + [1] * 4
    lines = [eq(f"{V(x)}.wrapping_add({V(y)})", V(cwl(lambda p, q: wrap(t, p + q), x, y)))]
    x2 = [t.smin] + x[1:]
    x2 = [t.smin, 4, 5, 4] if n > 2 else [t.smin, 5, 0, 0]
    lines += [eq(f"{V(x2)}.wrapping_sub({V(y)})", V(cwl(lambda p, q: wrap(t, p - q), x2, y)))]
    x3, y3 = [t.smax, 2, 5, 4], [3, 2, 3, 2]
    lines += [eq(f"{V(x3)}.wrapping_mul({V(y3)})", V(cwl(lambda p, q: wrap(t, p * q), x3, y3))),
              eq(f"{V(x3)}.wrapping_div({V(y3)})", V(cwl(tdiv, x3, y3)))]
    if s:
        x, y = [MAX, MIN, 0, 0], [1, -1, 0, 0]
        lines += [eq(f"{V(x)}.saturating_add({V(y)})", V(x)),
                  eq(f"{V([MIN, MAX, 0, 0])}.saturating_sub({V(y)})", V([MIN, MAX, 0, 0])),
                  eq(f"{V(x)}.saturating_mul({V([2, 2, 0, 0])})", V(x)),
                  eq(f"{V(x)}.saturating_div({V([2, 2, 3, 4])})",
                     V([MAX // 2, -(2**30), 0, 0])),
                  eq(f"{Tt}::MIN.wrapping_div({Tt}::NEG_ONE)", f"{Tt}::MIN"),
                  eq(f"{Tt}::MIN.saturating_div({Tt}::NEG_ONE)", f"{Tt}::MAX")]
    else:
        x, y = [UMAX, UMAX, 0, 0], [1, UMAX, 2, 3]
        lines += [eq(f"{V(x)}.saturating_add({V(y)})", V([UMAX, UMAX, 2, 3])),
                  eq(f"{V([0, UMAX, 0, 0])}.saturating_sub({V([1, 1, 2, 3])})",
                     V([0, UMAX - 1, 0, 0])),
                  eq(f"{V([UMAX, UMAX, 0, 0])}.saturating_mul({V([2, UMAX, 3, 4])})",
                     V([UMAX, UMAX, 0, 0])),
                  eq(f"{V([UMAX, UMAX, 0, 0])}.saturating_div({V([2, UMAX, 3, 4])})",
                     V([UMAX // 2, 1, 0, 0]))]
    test("test_wrapping_saturating", lines)

    # mixed signedness
    oT = f"{o.name}Trait"
    lines = []
    if s:
        lines += [eq(f"{Tt}::MAX.checked_add_unsigned({oT}::ONE)", "None"),
                  eq(f"{Tt}::NEG_ONE.checked_add_unsigned({oT}::ONE)", some(f"{Tt}::ZERO")),
                  eq(f"{Tt}::MIN.checked_sub_unsigned({oT}::ONE)", "None"),
                  eq(f"{Tt}::ZERO.checked_sub_unsigned({oT}::ONE)", some(f"{Tt}::NEG_ONE")),
                  eq(f"{Tt}::MAX.wrapping_add_unsigned({oT}::ONE)", f"{Tt}::MIN"),
                  eq(f"{Tt}::MIN.wrapping_sub_unsigned({oT}::ONE)", f"{Tt}::MAX"),
                  eq(f"{Tt}::MAX.saturating_add_unsigned({oT}::ONE)", f"{Tt}::MAX"),
                  eq(f"{Tt}::MIN.saturating_sub_unsigned({oT}::ONE)", f"{Tt}::MIN"),
                  eq(f"{Tt}::MIN.checked_add_unsigned({oT}::MAX)", some(f"{Tt}::MAX")),
                  eq(f"{Tt}::MAX.checked_sub_unsigned({oT}::MAX)", some(f"{Tt}::MIN"))]
        mixed = [("add", 1), ("sub", -1)]
        sfx = "unsigned"
    else:
        lines += [eq(f"{Tt}::MAX.checked_add_signed({oT}::ONE)", "None"),
                  eq(f"{Tt}::ONE.checked_add_signed({oT}::NEG_ONE)", some(f"{Tt}::ZERO")),
                  eq(f"{Tt}::ZERO.checked_add_signed({oT}::NEG_ONE)", "None"),
                  eq(f"{Tt}::MAX.wrapping_add_signed({oT}::ONE)", f"{Tt}::MIN"),
                  eq(f"{Tt}::MIN.wrapping_add_signed({oT}::NEG_ONE)", f"{Tt}::MAX"),
                  eq(f"{Tt}::MAX.saturating_add_signed({oT}::ONE)", f"{Tt}::MAX"),
                  eq(f"{Tt}::MIN.saturating_add_signed({oT}::NEG_ONE)", f"{Tt}::MIN")]
        mixed = [("add", 1)]
        sfx = "signed"
    for (x, _), (y, _) in zip(pairs(t), pairs(o)):
        for op, sign in mixed:
            exact = cwl(lambda p, q: p + sign * q, x, y)
            f = f"{op}_{sfx}"
            lines += [
                eq(f"{V(x)}.checked_{f}({V(y, o)})",
                   some(V(exact)) if all(fits(t, k) for k in exact[:n]) else "None"),
                eq(f"{V(x)}.wrapping_{f}({V(y, o)})", V([wrap(t, k) for k in exact])),
                eq(f"{V(x)}.saturating_{f}({V(y, o)})", V([sat(t, k) for k in exact]))]
    test(f"test_{sfx}_ops", lines)

    # distances
    lines = [eq(f"{V([3, 27, 98, 5])}.manhattan_distance({V([20, 65, 97, 9])})",
                sum(abs(p - q) for p, q in zip([3, 27, 98, 5][:n], [20, 65, 97, 9][:n]))),
             eq(f"{V([3, 27, 98, 5])}.chebyshev_distance({V([20, 65, 97, 9])})",
                max(abs(p - q) for p, q in zip([3, 27, 98, 5][:n], [20, 65, 97, 9][:n]))),
             eq(f"{Tt}::MIN.checked_manhattan_distance({Tt}::MAX)", "None"),
             eq(f"{Tt}::MIN.chebyshev_distance({Tt}::MAX)", UMAX),
             eq(f"{Tt}::MAX.chebyshev_distance({Tt}::MIN)", UMAX),
             eq(f"{Tt}::MIN.manhattan_distance({Tt}::MIN.with_x({t.smax}))", UMAX)]
    if s:
        lines += [eq(f"{V([-23, 2, -99, 4])}.manhattan_distance({V([22, -12, 24, -4])})",
                     sum(abs(p - q) for p, q in zip([-23, 2, -99, 4][:n], [22, -12, 24, -4][:n])))]
    for x, y in pairs(t):
        d = [abs(x[i] - y[i]) for i in range(n)]
        lines.append(eq(f"{V(x)}.checked_manhattan_distance({V(y)})",
                        some(sum(d)) if sum(d) <= UMAX else "None"))
        if sum(d) <= UMAX:
            lines.append(eq(f"{V(x)}.manhattan_distance({V(y)})", sum(d)))
        lines.append(eq(f"{V(x)}.chebyshev_distance({V(y)})", max(d)))
    test("test_manhattan_chebyshev_distance", lines)

    # casts
    lines = []
    for x, _ in pairs(t):
        cast = [wrap(o, k) for k in x]
        lines.append(eq(f"{V(x)}.as_{o.mod}()", V(cast, o)))
        lines.append(eq(f"{V(cast, o)}.as_{t.mod}()", V(x)))
        ok = all(fits(o, k) for k in x[:n])
        lines.append(f"let r: Option<{o.name}> = {V(x)}.try_into();")
        lines.append(eq("r", some(V(x, o)) if ok else "None"))
    test("test_casts", lines)

    # bit operators and shifts
    lines = []
    for x, y in pairs(t):
        lines += [eq(f"{V(x)} & {V(y)}", V(cwl(lambda p, q: wrap(t, p & q), x, y))),
                  eq(f"{V(x)} | {V(y)}", V(cwl(lambda p, q: wrap(t, p | q), x, y))),
                  eq(f"{V(x)} ^ {V(y)}", V(cwl(lambda p, q: wrap(t, p ^ q), x, y))),
                  eq(f"~{V(x)}", V(cwl(lambda p: wrap(t, ~p), x)))]
    test("test_bit_ops", lines)
    lines = []
    for k in [0, 1, 2, 5, 15, 16, 30, 31]:
        for x, _ in pairs(t)[::3]:
            lines += [eq(f"{V(x)}.shl({k})", V(cwl(lambda p: wrap(t, p << k), x))),
                      eq(f"{V(x)}.shr({k})", V(cwl(lambda p: p >> k, x)))]
    test("test_shifts", lines)

    # derives
    test("test_hash_serde", [
        f"let a = {V(one)};", f"let b = {V(list(reversed(one[:n])) + [0] * 4)};",
        "assert_eq!(hash(a), hash(a));", "assert!(hash(a) != hash(b));",
        "let mut out = array![];", "a.serialize(ref out);",
        eq("out.len()", n), "let mut span = out.span();",
        eq(f"Serde::<{T}>::deserialize(ref span)", "Some(a)"),
    ])

    # ------------------------------------------------------------------------------ panics
    sp = lambda name, msg, expr: panic(name, msg, [f"let _ = {expr};"])
    add_msg = f"'{S}_add Overflow'"
    sp("test_add_overflow", add_msg, f"{Tt}::MAX + {Tt}::X")
    sp("test_add_scalar_overflow", add_msg, f"{Tt}::MAX.add_scalar(1)")
    if s:
        sp("test_add_underflow", "'i32_add Underflow'", f"{Tt}::MIN + {Tt}::NEG_X")
        sp("test_sub_underflow", "'i32_sub Underflow'", f"{Tt}::MIN - {Tt}::X")
        sp("test_sub_overflow", "'i32_sub Overflow'", f"{Tt}::MAX - {Tt}::NEG_X")
        sp("test_neg_overflow", "'i32_neg Underflow'", f"-{Tt}::MIN")
        sp("test_abs_overflow", "'i32_neg Underflow'", f"{Tt}::MIN.abs()")
        sp("test_div_overflow", "'attempt to divide with overflow'", f"{Tt}::MIN / {Tt}::NEG_ONE")
        sp("test_rem_overflow", "'attempt to divide with overflow'", f"{Tt}::MIN % {Tt}::NEG_ONE")
        sp("test_div_scalar_overflow", "'attempt to divide with overflow'",
           f"{Tt}::MIN.div_scalar(-1)")
        sp("test_div_euclid_overflow", "'attempt to divide with overflow'",
           f"{Tt}::MIN.div_euclid({Tt}::NEG_ONE)")
        sp("test_div_euclid_by_zero", "'Division by 0'", f"{Tt}::ONE.div_euclid({Tt}::X)")
        sp("test_rem_euclid_by_zero", "'Division by 0'", f"{Tt}::ONE.rem_euclid({Tt}::X)")
        sp("test_distance_squared_overflow", g.ovf(t),
           f"{Tt}::MAX.distance_squared({Tt}::MIN)")
        if n == 2:
            sp("test_perp_overflow", "'i32_neg Underflow'", f"{Tt}::MIN.perp()")
            sp("test_perp_dot_overflow", g.ovf(t), f"{V([MAX, 0])}.perp_dot({V([0, MAX])})")
            sp("test_rotate_overflow", g.ovf(t), f"{Tt}::MAX.rotate({Tt}::MIN)")
    else:
        sp("test_sub_overflow", "'u32_sub Overflow'", f"{Tt}::ZERO - {Tt}::X")
        sp("test_sub_scalar_overflow", "'u32_sub Overflow'", f"{Tt}::ZERO.sub_scalar(1)")
    sp("test_mul_overflow", f"'{S}_mul Overflow'", f"{Tt}::MAX * {V([2] * 4)}")
    sp("test_mul_scalar_overflow", f"'{S}_mul Overflow'", f"{Tt}::MAX.mul_scalar(2)")
    sp("test_div_by_zero", "'Division by 0'", f"{Tt}::ONE / {Tt}::X")
    sp("test_rem_by_zero", "'Division by 0'", f"{Tt}::ONE % {Tt}::X")
    sp("test_div_scalar_by_zero", "'Division by 0'", f"{Tt}::ONE.div_scalar(0)")
    sp("test_rem_scalar_by_zero", "'Division by 0'", f"{Tt}::ONE.rem_scalar(0)")
    sp("test_wrapping_div_by_zero", "'Division by 0'", f"{Tt}::ONE.wrapping_div({Tt}::X)")
    sp("test_saturating_div_by_zero", "'Division by 0'", f"{Tt}::ONE.saturating_div({Tt}::X)")
    sp("test_dot_overflow", g.ovf(t), f"{Tt}::MAX.dot({Tt}::MAX)")
    sp("test_dot_into_vec_overflow", g.ovf(t), f"{Tt}::MAX.dot_into_vec({Tt}::MAX)")
    sp("test_length_squared_overflow", g.ovf(t), f"{Tt}::MAX.length_squared()")
    sp("test_element_sum_overflow", g.ovf(t) if g.is_fused(t, "element_sum") else add_msg,
       f"{Tt}::MAX.element_sum()")
    sp("test_element_product_overflow",
       g.ovf(t) if g.is_fused(t, "element_product") else f"'{S}_mul Overflow'",
       f"{Tt}::MAX.element_product()")
    sp("test_manhattan_distance_overflow",
       g.ovf(t) if g.is_fused(t, "manhattan_distance") else "'u32_add Overflow'",
       f"{Tt}::MIN.manhattan_distance({Tt}::MAX)")
    if n == 3:
        sp("test_cross_overflow", g.ovf(t),
           f"{V([65536, 0, 0, 0])}.cross({V([0, 65536, 0, 0])})")
        if not s:
            sp("test_cross_negative", g.ovf(t), f"{Tt}::Y.cross({Tt}::X)")
    sp("test_shl_overflow", f"'{T}: shift overflow'", f"{Tt}::ONE.shl(32)")
    sp("test_shr_overflow", f"'{T}: shift overflow'", f"{Tt}::ONE.shr(32)")

    # the fused kernels only range-check the result
    lines = []
    if s:
        x, y = [MAX, MAX, 5, 5], [2, -2, 1, 1]
        lines.append(eq(f"{V(x)}.dot({V(y)})", sum(x[i] * y[i] for i in range(n))))
        if n >= 3:
            lines.append(eq(f"{V([MAX, 7, MIN, 1])}.element_sum()", sum([MAX, 7, MIN, 1][:n])))
            lines.append(eq(f"{V([MAX, 2, 0, 1])}.element_product()", 0))
    else:
        if n >= 3:
            lines.append(eq(f"{V([UMAX, 2, 0, 1])}.element_product()", 0))
    if lines:
        test("test_fused_kernels_check_the_result_only", lines)

    # -------------------------------------------------------------------------------- fuzz
    def fuzz(name, seed, args, lines):
        body = "\n".join("    " + l for l in lines)
        G.out.append(f"#[test]\n#[fuzzer(runs: 256, seed: {seed})]\nfn {name}({args}) {{\n"
                     f"{body}\n}}\n")

    rot = lambda names: [names[i % len(names)] for i in range(4)]
    seed = 1000 * n + (0 if s else 500)
    sc = ", ".join(f"{k}: {S}" for k in "abcd")
    va = V(rot(["a", "b"]))
    vb = V(rot(["c", "d", "a"]))
    la, lb = rot(["a", "b"])[:n], rot(["c", "d", "a"])[:n]
    fuzz("fuzz_wrapping_checked_saturating", seed + 1, sc, [
        f"let va = {va};", f"let vb = {vb};",
        *[l for op, sym in [("add", "+"), ("sub", "-"), ("mul", "*")] for l in (
            "let exact = [" + ", ".join(f"wide({p}) {sym} wide({q})" for p, q in zip(la, lb))
            + "];",
            f"assert_eq!(va.wrapping_{op}(vb).to_array(), map_wrap(exact));",
            f"assert_eq!(va.saturating_{op}(vb).to_array(), map_sat(exact));",
            f"assert_eq!(va.checked_{op}(vb), map_checked(exact));")],
    ])
    fuzz("fuzz_min_max_clamp_select_cmp", seed + 2, sc, [
        f"let va = {va};", f"let vb = {vb};",
        "let lo = va.min(vb);", "let hi = va.max(vb);",
        "assert!(lo.cmple(hi).all());",
        "assert!(lo.cmple(va).all() && lo.cmple(vb).all());",
        "assert!(hi.cmpge(va).all() && hi.cmpge(vb).all());",
        f"assert_eq!({Tt}::select(va.cmplt(vb), va, vb), lo);",
        f"assert_eq!({Tt}::select(va.cmpgt(vb), va, vb), hi);",
        "assert_eq!(va.cmpeq(vb), !va.cmpne(vb));",
        "assert_eq!(va.cmpge(vb), !va.cmplt(vb));",
        "assert_eq!(va.cmple(vb), !va.cmpgt(vb));",
        f"let vc = {V(rot(['d', 'a', 'c']))};",
        "let c = vc.clamp(lo, hi);",
        "assert_eq!(c, vc.max(lo).min(hi));",
        "assert!(lo.min_element() <= lo.max_element());",
        "assert_eq!(va[va.min_position()], va.min_element());",
        "assert_eq!(va[va.max_position()], va.max_element());",
    ])
    fuzz("fuzz_distances", seed + 3, sc, [
        f"let va = {va};", f"let vb = {vb};",
        "let d = [" + ", ".join(f"abs_wide(wide({p}) - wide({q}))" for p, q in zip(la, lb))
        + "];",
        f"let [{', '.join('d' + c for c in cs)}] = d;",
        f"let sum = {' + '.join('d' + c for c in cs)};",
        "let expected: Option<u32> = sum.try_into();",
        "assert_eq!(va.checked_manhattan_distance(vb), expected);",
        "assert_eq!(vb.checked_manhattan_distance(va), expected);",
        "let mut m = dx;",
        *[f"if d{c} > m {{ m = d{c}; }}" for c in cs[1:]],
        "assert_eq!(wide_u(va.chebyshev_distance(vb)), m);",
    ])
    small = lambda k: f"{k} / 0x40000"
    fuzz("fuzz_dot_sum_product", seed + 4, sc, [
        "// 14-bit operands: nothing overflows",
        f"let va = {V([small(k) for k in rot(['a', 'b'])])};",
        f"let vb = {V([small(k) for k in rot(['c', 'd', 'a'])])};",
        "let expected = " + " + ".join(f"wide({small(p)}) * wide({small(q)})"
                                       for p, q in zip(la, lb)) + ";",
        "assert_eq!(wide(va.dot(vb)), expected);",
        "assert_eq!(va.dot(vb), vb.dot(va));",
        "assert_eq!(va.length_squared(), va.dot(va));",
        "assert_eq!(wide(va.element_sum()), " + " + ".join(f"wide({small(p)})" for p in la) + ");",
        f"let tiny = {V([f'{k} / 0x1000000' for k in rot(['a', 'b'])])};",
        "assert_eq!(wide(tiny.element_product()), "
        + " * ".join(f"wide({p} / 0x1000000)" for p in la) + ");",
        *([f"assert_eq!(wide(va.distance_squared(vb)), "
           + " + ".join(f"(wide({small(p)}) - wide({small(q)})) * (wide({small(p)}) - "
                        f"wide({small(q)}))" for p, q in zip(la, lb)) + ");"] if s else []),
        *([f"let tb = {V([f'{k} / 0x1000000' for k in rot(['c', 'd', 'a'])])};",
           "let c = tiny.cross(tb);", "assert_eq!(c.dot(tiny), 0);", "assert_eq!(c.dot(tb), 0);",
           "assert_eq!(tb.cross(tiny), -c);"] if s and n == 3 else []),
        *(["assert_eq!(va.perp_dot(vb), va.perp().dot(vb));",
           "assert_eq!(va.rotate(vb), vb.rotate(va));"] if s and n == 2 else []),
    ])
    fuzz("fuzz_casts_bits_shifts", seed + 5, f"a: {S}, b: {S}, k: u32", [
        f"let va = {V(rot(['a', 'b']))};", f"let vb = {V(rot(['b', 'a', 'a']))};",
        f"assert_eq!(va.as_{o.mod}().as_{t.mod}(), va);",
        f"assert_eq!(wide_o(va.as_{o.mod}().x), wrap_o(wide(a)));",
        "// (a & b) + (a | b) == a + b and (a ^ b) + 2 * (a & b) == a + b",
        "assert_eq!(wide((va & vb).x) + wide((va | vb).x), wide(a) + wide(b));",
        "assert_eq!(wide((va ^ vb).x) + 2 * wide((va & vb).x), wide(a) + wide(b));",
        "assert_eq!((va ^ vb) ^ vb, va);", "assert_eq!(~(va & vb), ~va | ~vb);",
        "assert_eq!(wide((~va).x), -1 - wide(a)" + ("" if s else " + 0x100000000") + ");",
        "let k = k % 32;", "let p = pow2(k);",
        "assert_eq!(wide(va.shl(k).x), wrap(wide(a) * p));",
        "assert_eq!(wide(va.shr(k).x), floor_div(wide(a), p));",
    ])
    if s:
        fuzz("fuzz_div_euclid_rem_euclid", seed + 6, sc, [
            f"let va = {va};",
            f"let vb = {V([f'nz({k})' for k in rot(['c', 'd', 'a'])])};",
            f"if !({' || '.join(f'({p} == {MIN} && nz({q}) == -1)' for p, q in zip(la, lb))}) {{",
            "    let q = va.div_euclid(vb);", "    let r = va.rem_euclid(vb);",
            "    assert!(r.cmpge(" + Tt + "::ZERO).all());",
            *[f"    assert!(wide(r.{c}) < abs_wide(wide(vb.{c})));" for c in cs],
            *[f"    assert_eq!(wide(q.{c}) * wide(vb.{c}) + wide(r.{c}), wide(va.{c}));"
              for c in cs],
            "    let tq = va / vb;", "    let tr = va % vb;",
            *[f"    assert_eq!(wide(tq.{c}) * wide(vb.{c}) + wide(tr.{c}), wide(va.{c}));"
              for c in cs],
            *[f"    assert!(abs_wide(wide(tr.{c})) < abs_wide(wide(vb.{c})));" for c in cs],
            *[f"    assert!(wide(tr.{c}) == 0 || (tr.{c} < 0) == (va.{c} < 0));" for c in cs],
            "    assert_eq!(va.wrapping_div(vb), tq);",
            "}",
        ])
        fuzz("fuzz_abs_signum_neg", seed + 7, f"a: {S}, b: {S}", [
            f"let a = if a == {MIN} {{ 0 }} else {{ a }};",
            f"let b = if b == {MIN} {{ 0 }} else {{ b }};",
            f"let va = {V(rot(['a', 'b']))};",
            "assert_eq!(va.signum() * va.abs(), va);", "assert_eq!((-va).abs(), va.abs());",
            "assert_eq!(-(-va), va);", "assert!(va.abs().cmpge(" + Tt + "::ZERO).all());",
            f"assert_eq!(va.is_negative_mask(), va.cmplt({Tt}::ZERO));",
            "assert_eq!(va.is_negative_bitmask(), va.is_negative_mask().bitmask());",
        ])
    else:
        fuzz("fuzz_div_rem", seed + 6, sc, [
            f"let va = {va};",
            f"let vb = {V([f'nz({k})' for k in rot(['c', 'd', 'a'])])};",
            "let q = va / vb;", "let r = va % vb;", "assert!(r.cmplt(vb).all());",
            *[f"assert_eq!(wide(q.{c}) * wide(vb.{c}) + wide(r.{c}), wide(va.{c}));" for c in cs],
            "assert_eq!(va.wrapping_div(vb), q);", "assert_eq!(va.saturating_div(vb), q);",
            "assert_eq!(va.checked_div(vb), Some(q));",
        ])
    mixed_fn = "add_unsigned" if s else "add_signed"
    fuzz("fuzz_mixed_sign_ops", seed + 8, f"a: {S}, b: {S}, c: {o.S}, d: {o.S}", [
        f"let va = {V(rot(['a', 'b']))};", f"let vb = {V(rot(['c', 'd']), o)};",
        "let exact = [" + ", ".join(f"wide({p}) + wide_o({q})"
                                     for p, q in zip(rot(['a', 'b'])[:n], rot(['c', 'd'])[:n]))
        + "];",
        f"assert_eq!(va.wrapping_{mixed_fn}(vb).to_array(), map_wrap(exact));",
        f"assert_eq!(va.saturating_{mixed_fn}(vb).to_array(), map_sat(exact));",
        f"assert_eq!(va.checked_{mixed_fn}(vb), map_checked(exact));",
        *([
            "let exact = [" + ", ".join(
                f"wide({p}) - wide_o({q})"
                for p, q in zip(rot(['a', 'b'])[:n], rot(['c', 'd'])[:n])) + "];",
            "assert_eq!(va.wrapping_sub_unsigned(vb).to_array(), map_wrap(exact));",
            "assert_eq!(va.saturating_sub_unsigned(vb).to_array(), map_sat(exact));",
            "assert_eq!(va.checked_sub_unsigned(vb), map_checked(exact));"] if s else []),
    ])

    arr = lambda f: "[" + ", ".join(f(c) for c in cs) + "]"
    lo_w, hi_w = (f"{MIN}", f"{MAX}") if s else ("0", f"{UMAX}")
    prelude = f"""{g.HEADER}//! Tests of `glam::{t.mod}`: the glam-rs integer vector test macros of `tests/vec{n}.rs`, tables over
//! a pool of edge values (expected values computed by the generator with Python integers), seeded
//! fuzz properties against the `i128` reference below, and one test per panic path.

use core::hash::{{HashStateExTrait, HashStateTrait}};
use core::poseidon::PoseidonTrait;
use glam::{t.bmod}::{{{t.B}Trait, {t.bmod}}};
use glam::{t.mod}::{{{T}, {T}Trait, {t.mod}}};
use glam::{o.mod}::{{{o.name}, {o.name}Trait, {o.mod}}};
{"".join(f"use glam::{t.dim(k).mod}::{t.dim(k).mod};" + chr(10) for k in (2, 3, 4) if k != n and abs(k - n) <= (2 if n == 4 else 1))}
fn hash(v: {T}) -> felt252 {{
    PoseidonTrait::new().update_with(v).finalize()
}}

// The reference: exact arithmetic in `i128`, reduced to `{S}` the way Rust does.

fn wide(v: {S}) -> i128 {{
    v.into()
}}

fn wide_o(v: {o.S}) -> i128 {{
    v.into()
}}

fn wide_u(v: u32) -> i128 {{
    v.into()
}}

fn abs_wide(v: i128) -> i128 {{
    if v < 0 {{
        -v
    }} else {{
        v
    }}
}}

/// Euclidean remainder of `v` by `2^32`.
fn low32(v: i128) -> i128 {{
    let m: i128 = 0x100000000;
    ((v % m) + m) % m
}}

/// Two's complement reduction to `{S}`.
fn wrap(v: i128) -> i128 {{
    let r = low32(v);
    {"if r >= 0x80000000 { r - 0x100000000 } else { r }" if s else "r"}
}}

/// Two's complement reduction to `{o.S}`.
fn wrap_o(v: i128) -> i128 {{
    let r = low32(v);
    {"r" if s else "if r >= 0x80000000 { r - 0x100000000 } else { r }"}
}}

fn sat(v: i128) -> i128 {{
    if v < {lo_w} {{
        {lo_w}
    }} else if v > {hi_w} {{
        {hi_w}
    }} else {{
        v
    }}
}}

fn narrow(v: i128) -> {S} {{
    v.try_into().unwrap()
}}

fn map_wrap(e: [i128; {n}]) -> [{S}; {n}] {{
    let [{', '.join(cs)}] = e;
    {arr(lambda c: f"narrow(wrap({c}))")}
}}

fn map_sat(e: [i128; {n}]) -> [{S}; {n}] {{
    let [{', '.join(cs)}] = e;
    {arr(lambda c: f"narrow(sat({c}))")}
}}

fn map_checked(e: [i128; {n}]) -> Option<{T}> {{
    let [{', '.join(cs)}] = e;
    if {' && '.join(f'sat({c}) == {c}' for c in cs)} {{
        Some({t.cw(lambda c: f"narrow({c})")})
    }} else {{
        None
    }}
}}

fn pow2(k: u32) -> i128 {{
    let mut p: i128 = 1;
    for _ in 0..k {{
        p *= 2;
    }}
    p
}}

/// `floor(a / p)` for `p > 0`.
fn floor_div(a: i128, p: i128) -> i128 {{
    let r = ((a % p) + p) % p;
    (a - r) / p
}}

/// A non-zero divisor.
fn nz(v: {S}) -> {S} {{
    if v == 0 {{
        3
    }} else {{
        v
    }}
}}

"""
    return prelude + "\n".join(G.out)
