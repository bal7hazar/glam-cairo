"""Text shared by the generators for the iterator and the span / array entry points (lot AP).

`Sum` / `Product` over iterators and the `from_span` / `write_to` I/O entry points are the only
places of the library that take a `Span` or loop (the exception recorded in docs/DESIGN.md
section 4, rule 1): they are aggregation and I/O glue, not math kernels, and no math function
gains a `Span` or a loop.

Dependency-free; imported by `fvec.py`, `fmat.py` and `intvec.py` (their directory is on the path).
"""

import textwrap

# `Span`, `Array`, `assert` and `Iterator` are in the Cairo prelude: no import is emitted.


def span_msg(T):
    """The panic message of a span shorter than the type needs (<= 31 chars)."""
    return f"'{T}: span too short'"


def span_panic(T, n):
    return f"`{span_msg(T)}` if `span` has fewer than {n} elements."


def from_span_head(T, n):
    """The length check that opens every `from_span` / `from_cols_span` / `from_rows_span`."""
    return f"assert(span.len() >= {n}, {span_msg(T)});"


FROM_SPAN_DEV = (
    "Takes a `Span` (Cairo has no slice reference); a span longer than the type needs is "
    "accepted and its first elements are read, as the slice of glam-rs. A shorter span panics "
    "with the message above where glam-rs panics with an index out of bounds."
)

WRITE_TO_DEV = (
    "Appends the elements to `out` (an `Array` cannot be overwritten in place), where "
    "glam-rs overwrites the first elements of the slice: pass an empty array to get the same "
    "elements."
)

MAP_DEV = (
    "The callback is a closure (`core::ops::Fn`) and each element is mapped in order (`x` first)."
)


def _doc(text, width=96):
    """`///` lines of one paragraph, wrapped."""
    return "\n".join("///" + (" " + l) for l in textwrap.wrap(text, width - 4))


def _bullets(items, width=96):
    out = []
    for item in items:
        w = textwrap.wrap(item, width - 8)
        out.append("/// * " + w[0])
        out += ["///   " + l for l in w[1:]]
    return "\n".join(out)


def accum_impl(T, trait, start, start_name, op, panics, owner_doc, commutes=True):
    """`pub impl {T}{trait} of {trait}<{T}>`: a left-to-right fold of the iterator.

    `trait` is `Sum` or `Product`, `start` the accumulator before the first item (`T::ZERO` for the
    sum, `T::IDENTITY` / `T::ONE` for the product) named `start_name`, `op` the operator (`+` or
    `*`) of the type; `commutes` is false when the order of the factors changes the result."""
    fn = trait.lower()
    what = "sum" if trait == "Sum" else "product"
    order = (f"Items are folded in iteration order, left to right, starting from `{start_name}`, "
             f"with the `{op}` of `{T}`: `(((start {op} a) {op} b) {op} c)`. That order is the "
             "determinism contract")
    if not commutes:
        order += ": the product is not commutative, so the order of the items changes the result"
    order += ". An empty iterator yields the start value."
    dev = [
        f"The Cairo trait is `core::iter::{trait}<{T}>` with one impl: the owned form and the "
        f"reference form of glam-rs (`{trait}<&{T}>`) are one, as values are `Copy` and passed "
        "by value.",
        "Iterator glue, not a math kernel: it loops over the iterator "
        "(docs/DESIGN.md section 4, exception AP).",
    ]
    return (
        f"{_doc(f'The {what} of an iterator of `{T}` ({owner_doc}).')}\n"
        f"///\n{_doc(order)}\n"
        f"///\n/// Mirrors `impl {trait} for glam::{T}` and `impl<'a> {trait}<&'a {T}> for "
        f"glam::{T}`.\n"
        f"/// #### Panics\n{_bullets(panics)}\n"
        f"/// #### Deviations\n{_bullets(dev)}\n"
        f"pub impl {T}{trait} of {trait}<{T}> {{\n"
        f"    fn {fn}<I, +Iterator<I>[Item: {T}], +Destruct<I>, +Destruct<{T}>>(mut iter: I) -> {T} {{\n"
        f"        let mut acc = {start};\n"
        f"        while let Some(item) = iter.next() {{\n"
        f"            acc = acc {op} item;\n"
        f"        }}\n"
        f"        acc\n"
        f"    }}\n"
        f"}}\n"
    )


# --------------------------------------------------------------------------------------------
# Tests (hand-written expectations: small integers, exact in every scalar)
# --------------------------------------------------------------------------------------------
def tests_vector(T, mod, n, S, sc, ctor, zero, one, map_double=True, big=None, add_msg=None,
                 mul_msg=None, owner=None):
    owner = owner or T  # the owner scripts/deviations.py derives from the file stem
    """Tests of `Sum` / `Product`, `from_span` / `write_to` and `map` of a vector type.

    `sc(k)` is the Cairo scalar of the small integer `k`, `ctor(vals)` the vector of the scalars
    `vals` (a list of ints), `zero` / `one` the constants as Cairo expressions."""
    xs = [[k + 2 for k in range(n)], [k + 3 for k in range(n)], [k + 4 for k in range(n)]]
    sums = [sum(x[k] for x in xs) for k in range(n)]
    prods = [xs[0][k] * xs[1][k] * xs[2][k] for k in range(n)]
    items = ", ".join(ctor(x) for x in xs)
    arr = lambda vals: "array![" + ", ".join(sc(v) for v in vals) + "]"
    full = list(range(1, n + 1))
    out = f"""
// ---- iterators, span and array entry points, `map` (lot AP)
use glam::{mod}::{{{T}Product, {T}Sum}};

#[test]
fn test_sum_product_iter() {{
    let s = {T}Sum::sum(array![{items}].into_iter());
    assert!(s == {ctor(sums)}, "sum");
    let p = {T}Product::product(array![{items}].into_iter());
    assert!(p == {ctor(prods)}, "product");
    let none: Array<{T}> = array![];
    assert!({T}Sum::sum(none.into_iter()) == {zero}, "empty sum");
    let none: Array<{T}> = array![];
    assert!({T}Product::product(none.into_iter()) == {one}, "empty product");
}}

#[test]
fn test_sum_product_method_form() {{
    let s: {T} = array![{items}].into_iter().sum();
    assert!(s == {ctor(sums)}, "sum");
    let p: {T} = array![{items}].into_iter().product();
    assert!(p == {ctor(prods)}, "product");
}}

#[test]
fn test_from_span_write_to() {{
    let longer: Array<{S}> = {arr(full + [n + 1])};
    let v = {T}Trait::from_span(longer.span());
    assert!(v == {ctor(full)}, "N + 1 reads the first N");
    let exact: Array<{S}> = {arr(full)};
    assert!({T}Trait::from_span(exact.span()) == v, "exactly N");
    let mut out: Array<{S}> = array![];
    v.write_to(ref out);
    assert!(out.len() == {n}, "N elements appended");
    assert!({T}Trait::from_span(out.span()) == v, "round trip");
    v.write_to(ref out);
    assert!(out.len() == {2 * n}, "write_to appends");
}}

#[test]
#[should_panic(expected: '{T}: span too short')]
fn test_from_span_short() {{
    let short: Array<{S}> = {arr(full[:-1])};
    let _ = {T}Trait::from_span(short.span());
}}
"""
    out += f"""
// panics: {owner}::{T}Sum
#[test]
#[should_panic(expected: '{add_msg}')]
fn test_sum_overflow() {{
    let _ = {T}Sum::sum(array![{big}, {big}].into_iter());
}}

// panics: {owner}::{T}Product
#[test]
#[should_panic(expected: '{mul_msg}')]
fn test_product_overflow() {{
    let _ = {T}Product::product(array![{big}, {big}].into_iter());
}}
"""
    if map_double:
        out += f"""
#[test]
fn test_map() {{
    let v = {T}Trait::from_span({arr(full)}.span());
    assert!(v.map(|x| x + x) == {ctor([2 * k for k in full])}, "map doubles");
    let offset = {sc(5)};
    assert!(v.map(|x| x + offset) == {ctor([k + 5 for k in full])}, "map captures");
}}
"""
    return out


def _matmul(a, b, n):
    """Product of two column major `n`x`n` matrices given as flat lists (small integers)."""
    return [sum(a[k * n + j] * b[i * n + k] for k in range(n)) for i in range(n) for j in range(n)]


def tests_matrix(T, mod, n, sc, ident, big):
    """Tests of `Sum` / `Product`, `from_cols_span` / `from_rows_span` / `write_cols_to` of a matrix."""
    N = n * n
    a = [k + 1 for k in range(N)]
    b = [(3 * k + 2) % 5 for k in range(N)]
    c = [(2 * k + 1) % 4 for k in range(N)]
    ab, ba = _matmul(a, b, n), _matmul(b, a, n)
    assert ab != ba, "the order test needs a non-commutative pair"
    abc = _matmul(ab, c, n)
    sums = [x + y + z for x, y, z in zip(a, b, c)]
    ctor = lambda vals: f"{T}Trait::from_cols_array([" + ", ".join(sc(v) for v in vals) + "])"
    arr = lambda vals: "array![" + ", ".join(sc(v) for v in vals) + "]"
    full = list(range(1, N + 1))
    return f"""
// ---- iterators and span entry points (lot AP)
use glam::{mod}::{{{T}Product, {T}Sum}};

#[test]
fn test_sum_iter() {{
    let s = {T}Sum::sum(array![{ctor(a)}, {ctor(b)}, {ctor(c)}].into_iter());
    assert!(s == {ctor(sums)}, "sum");
    let none: Array<{T}> = array![];
    assert!({T}Sum::sum(none.into_iter()) == {T}Trait::ZERO, "empty sum");
}}

#[test]
fn test_sum_product_method_form() {{
    let (a, b, c) = ({ctor(a)}, {ctor(b)}, {ctor(c)});
    let s: {T} = array![a, b, c].into_iter().sum();
    assert!(s == {ctor(sums)}, "sum");
    let p: {T} = array![a, b, c].into_iter().product();
    assert!(p == a * b * c, "product");
}}

#[test]
fn test_product_iter_order() {{
    let (a, b, c) = ({ctor(a)}, {ctor(b)}, {ctor(c)});
    let p = {T}Product::product(array![a, b].into_iter());
    assert!(p == {ctor(ab)}, "a * b");
    assert!(p != {ctor(ba)}, "not b * a");
    let p3 = {T}Product::product(array![a, b, c].into_iter());
    assert!(p3 == {ctor(abc)}, "(a * b) * c");
    assert!(p3 == a * b * c, "the operator");
    let none: Array<{T}> = array![];
    assert!({T}Product::product(none.into_iter()) == {ident}, "empty product");
}}

#[test]
fn test_from_span_write_to() {{
    let longer: Array<Fixed> = {arr(full + [N + 1])};
    let m = {T}Trait::from_cols_span(longer.span());
    assert!(m == {ctor(full)}, "N + 1 reads the first N");
    let exact: Array<Fixed> = {arr(full)};
    assert!({T}Trait::from_cols_span(exact.span()) == m, "exactly N");
    assert!({T}Trait::from_rows_span(exact.span()) == m.transpose(), "rows are the transpose");
    let mut out: Array<Fixed> = array![];
    m.write_cols_to(ref out);
    assert!(out.len() == {N}, "N elements appended");
    assert!({T}Trait::from_cols_span(out.span()) == m, "round trip");
    m.write_cols_to(ref out);
    assert!(out.len() == {2 * N}, "write_cols_to appends");
}}

// panics: {T}::{T}Sum
#[test]
#[should_panic(expected: 'i64_add Overflow')]
fn test_sum_overflow() {{
    let _ = {T}Sum::sum(array![{big}, {big}].into_iter());
}}

// panics: {T}::{T}Product
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_product_overflow() {{
    let _ = {T}Product::product(array![{big}, {big}].into_iter());
}}

#[test]
#[should_panic(expected: '{T}: span too short')]
fn test_from_cols_span_short() {{
    let short: Array<Fixed> = {arr(full[:-1])};
    let _ = {T}Trait::from_cols_span(short.span());
}}

#[test]
#[should_panic(expected: '{T}: span too short')]
fn test_from_rows_span_short() {{
    let short: Array<Fixed> = {arr(full[:-1])};
    let _ = {T}Trait::from_rows_span(short.span());
}}
"""
