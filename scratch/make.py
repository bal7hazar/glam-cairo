#!/usr/bin/env python3
"""Prototype of the glam cut (PK-G part B): build a scratch workspace from packages/glam/src.

usage: make.py SRC_DIR OUT_DIR VARIANT   (VARIANT: a | b | c1 | c2 | c3)
  a   glam_core (all but swizzles) + glam_swizzles (float + int swizzles)
  b   glam_core (float, bvec, camera, float swizzles) + glam_int (int types, casts, int swizzles)
  c1  glam_core + glam_int (types, casts) + glam_swizzles (float + int swizzles; depends on glam_int)
  c2  glam_core + glam_int (types, casts, int swizzles) + glam_swizzles (float swizzles)
  c3  glam_core + glam_int (types, casts) + glam_swizzles (float) + glam_int_swizzles
Always: a `glam` facade crate re-exporting everything.
"""
import os
import re
import shutil
import sys

SRC, OUT, VARIANT = sys.argv[1], sys.argv[2], sys.argv[3]
CORE_MODS = ["affine2", "affine3", "bvec2", "bvec3", "bvec4", "camera", "euler", "mat2", "mat3",
             "mat4", "quat", "vec2", "vec3", "vec4"]
INT_MODS = ["ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4"]
FLOAT_SW = ["vec2", "vec3", "vec4"]
INT_SW = INT_MODS
VERSION = "0.4.0"


def read(p):
    with open(p) as f:
        return f.read()


def write(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(s)


def copy_module(name, dst_src):
    """Copy `name.cairo` (and the directory `name/` when it exists) into `dst_src`."""
    shutil.copy(os.path.join(SRC, name + ".cairo"), os.path.join(dst_src, name + ".cairo"))
    if os.path.isdir(os.path.join(SRC, name)):
        shutil.copytree(os.path.join(SRC, name), os.path.join(dst_src, name))


def scarb(name, deps, description):
    lines = ["[package]", f'name = "{name}"', f'description = "{description}"',
             f'version = "{VERSION}"', 'edition = "2024_07"', 'cairo-version = "2.19.4"',
             'license = "MIT"', "", "[dependencies]"]
    for d in deps:
        lines.append('fixed = "0.4.0"' if d == "fixed" else f'{d} = {{ path = "../{d}" }}')
    lines += ["", "[tool]", "fmt.workspace = true", ""]
    return "\n".join(lines)


def crate_ref(mod):
    """The crate that hosts the module `mod` in this variant (for `crate::mod` rewriting)."""
    if mod in CORE_MODS:
        return "glam_core"
    if mod in INT_MODS:
        return "glam_int" if VARIANT != "a" else "glam_core"
    raise KeyError(mod)


def rewrite_uses(text, here):
    """`use crate::m::..` -> `use <crate of m>::m::..` when m lives in another crate."""
    def sub(m):
        mod = m.group(1)
        c = crate_ref(mod)
        return m.group(0) if c == here else f"use {c}::{mod}"

    return re.sub(r"\buse crate::(\w+)", sub, text)


def cut_block(text, start_pat, end_kind):
    """Remove the item that starts at the doc-comment/attribute block preceding `start_pat`.

    `end_kind`: 'decl' (ends at the first `;` at depth 0) or 'body' (ends at the matching `}`).
    Returns (new_text, removed_text)."""
    m = re.search(start_pat, text)
    assert m, start_pat
    i = m.start()
    # walk up over doc comments / attributes
    lines_before = text[:i].split("\n")
    # lines_before[-1] is the (indent) prefix of the line holding the match
    k = len(lines_before) - 1
    while k > 0 and re.match(r"\s*(///|#\[)", lines_before[k - 1]):
        k -= 1
    start = sum(len(l) + 1 for l in lines_before[:k])
    depth, j = 0, i
    while True:
        c = text[j]
        if c in "({[":
            depth += 1
        elif c in ")}]":
            depth -= 1
            if depth == 0 and c == "}" and end_kind == "body":
                j += 1
                break
        elif c == ";" and depth == 0 and end_kind == "decl":
            j += 1
            break
        j += 1
    # swallow the trailing newline(s)
    while j < len(text) and text[j] == "\n":
        j += 1
        if text[j - 1:j + 1] == "\n\n":
            break
    return text[:start] + text[j:], text[start:j]


def strip_int_casts(name):
    """Remove from a float vector module everything that names an integer vector."""
    n = name[-1]
    text = read(os.path.join(SRC, name + ".cairo"))
    removed = {}
    text = re.sub(rf"use crate::ivec{n}::IVec{n};\n", "", text)
    text = re.sub(rf"use crate::uvec{n}::UVec{n};\n", "", text)
    for fn, ret in ((f"as_ivec{n}", f"IVec{n}"), (f"as_uvec{n}", f"UVec{n}")):
        text, removed[fn + "_decl"] = cut_block(text, rf"fn {fn}\(self: Vec{n}\) -> {ret};", "decl")
        text, removed[fn + "_impl"] = cut_block(
            text, rf"fn {fn}\(self: Vec{n}\) -> {ret} \{{", "body")
    for kind in ("IVec", "UVec"):
        text, removed[kind + "_into"] = cut_block(
            text, rf"pub impl {kind}{n}IntoVec{n} of Into<{kind}{n}, Vec{n}> \{{", "body")
    text, removed["to_u32"] = cut_block(text, r"fn to_u32\(v: Fixed\) -> u32 \{", "body")
    return text, removed


def dedent_impl(s):
    return s


def make_casts(cast_data):
    """glam_int/src/casts.cairo: the extension traits (float -> int) and `to_u32`."""
    out = ["//! The casts between the float vectors of `glam_core` and the integer vectors, moved out of",
           "//! `glam_core::vec{2,3,4}::Vec{2,3,4}Trait` by the cut (PK-G prototype).",
           "use fixed::fixed::{Fixed, FixedTrait};"]
    for n in "234":
        out.append(f"use glam_core::vec{n}::Vec{n};")
        out.append(f"use crate::ivec{n}::IVec{n};")
        out.append(f"use crate::uvec{n}::UVec{n};")
    out.append("")
    for n in "234":
        rem = cast_data[n]
        decl = rem[f"as_ivec{n}_decl"] + rem[f"as_uvec{n}_decl"]
        impl_ = (rem[f"as_ivec{n}_impl"] + rem[f"as_uvec{n}_impl"]).replace("to_u32(", f"to_u32_{n}(")
        out.append(f"pub trait Vec{n}IntCasts {{\n{decl}}}\n")
        out.append(f"pub impl Vec{n}IntCastsImpl of Vec{n}IntCasts {{\n{impl_}}}\n")
        out.append(rem["to_u32"].replace("fn to_u32", f"fn to_u32_{n}"))
        out.append("")
    text = "\n".join(out)
    for n in "234":
        text = text.replace(f"to_u32(self.x)", f"to_u32_{n}(self.x)") if False else text
    return text


def main():
    if os.path.exists(OUT):
        sys.exit(f"{OUT} exists")
    os.makedirs(OUT)
    write(os.path.join(OUT, "Scarb.toml"),
          '[workspace]\nmembers = ["glam_core", "glam_swizzles", "glam_int", "glam", "glam_int_swizzles"]\n\n'
          '[workspace.tool.fmt]\nsort-module-level-items = true\nmax-line-length = 100\n')
    # the members that do not exist in a variant are dropped below
    has_int = VARIANT != "a"
    has_int_sw_crate = VARIANT == "c3"
    sw_int_where = {"a": "swizzles", "b": "int", "c1": "swizzles", "c2": "int", "c3": "intsw"}[VARIANT]
    sw_float_where = "core" if VARIANT == "b" else "swizzles"

    core_src = os.path.join(OUT, "glam_core", "src")
    os.makedirs(core_src)
    core_mods = list(CORE_MODS) + ([] if has_int else INT_MODS)
    casts = {}
    for m in core_mods:
        if m in ("vec2", "vec3", "vec4") and has_int:
            text, removed = strip_int_casts(m)
            casts[m[-1]] = removed
            write(os.path.join(core_src, m + ".cairo"), text)
        else:
            copy_module(m, core_src)
    # rewrite crate:: references of core modules (only int -> bvec crosses crates)
    if has_int:
        int_src = os.path.join(OUT, "glam_int", "src")
        os.makedirs(int_src)
        for m in INT_MODS:
            text = read(os.path.join(SRC, m + ".cairo"))
            text = rewrite_uses(text, "glam_int")
            write(os.path.join(int_src, m + ".cairo"), text)
    # Into<IVec, Vec> / Into<UVec, Vec> hosted in the integer module (found without an import)
    if has_int:
        for m in INT_MODS:
            n = m[-1]
            kind = "IVec" if m.startswith("i") else "UVec"
            body = casts[n][kind + "_into"]
            p = os.path.join(OUT, "glam_int", "src", m + ".cairo")
            text = read(p)
            text += f"\nuse fixed::fixed::FixedTrait;\nuse glam_core::vec{n}::Vec{n};\n\n" + body
            write(p, text)
        write(os.path.join(OUT, "glam_int", "src", "casts.cairo"), make_casts(casts))

    # swizzle files
    def sw_files(kind):
        return FLOAT_SW if kind == "float" else INT_SW

    def sw_crate_src(crate, mods):
        d = os.path.join(OUT, crate, "src")
        os.makedirs(d, exist_ok=True)
        lib = ["//! Swizzle traits (PK-G prototype)."]
        for m in mods:
            text = read(os.path.join(SRC, "swizzles", m + ".cairo"))
            here = crate
            # swizzle files reference the vector types of their family
            def sub(mm):
                mod = mm.group(1)
                c = crate_ref(mod)
                return f"use {c}::{mod}"
            text = re.sub(r"\buse crate::(\w+)", sub, text)
            write(os.path.join(d, "swz_" + m + ".cairo"), text)
            lib.append(f"pub mod swz_{m};")
        for m in mods:
            n = m[-1]
            base = {"vec": "Vec", "ivec": "IVec", "uvec": "UVec"}[re.match(r"[a-z]+", m).group(0)]
            lib.append(f"pub use swz_{m}::{{{base}{n}Swizzles, {base}{n}SwizzlesImpl}};")
        write(os.path.join(d, "lib.cairo"), "\n".join(lib) + "\n")

    if sw_float_where == "core":
        # b: float swizzles stay in glam_core under `swizzles/`
        for m in FLOAT_SW:
            text = read(os.path.join(SRC, "swizzles", m + ".cairo"))
            write(os.path.join(core_src, "swizzles", m + ".cairo"), text)
        lib = ["pub mod vec2;", "pub mod vec3;", "pub mod vec4;"] + [
            f"pub use vec{n}::{{Vec{n}Swizzles, Vec{n}SwizzlesImpl}};" for n in "234"]
        write(os.path.join(core_src, "swizzles.cairo"), "\n".join(lib) + "\n")
        core_mods.append("swizzles")
        sw_crate = None
    # crates of the swizzles
    swz_crates = {}
    if VARIANT == "a":
        sw_crate_src("glam_swizzles", FLOAT_SW + INT_SW)
        swz_crates["glam_swizzles"] = ["glam_core"]
    elif VARIANT == "b":
        # int swizzles inside glam_int (module `swizzles`)
        d = os.path.join(OUT, "glam_int", "src", "swizzles")
        lib = []
        for m in INT_SW:
            text = read(os.path.join(SRC, "swizzles", m + ".cairo"))
            write(os.path.join(d, m + ".cairo"), text)
            lib.append(f"pub mod {m};")
        for m in INT_SW:
            n = m[-1]
            base = "IVec" if m.startswith("i") else "UVec"
            lib.append(f"pub use {m}::{{{base}{n}Swizzles, {base}{n}SwizzlesImpl}};")
        write(os.path.join(OUT, "glam_int", "src", "swizzles.cairo"), "\n".join(lib) + "\n")
    elif VARIANT == "c1":
        sw_crate_src("glam_swizzles", FLOAT_SW + INT_SW)
        swz_crates["glam_swizzles"] = ["glam_core", "glam_int"]
    elif VARIANT == "c2":
        sw_crate_src("glam_swizzles", FLOAT_SW)
        swz_crates["glam_swizzles"] = ["glam_core"]
        d = os.path.join(OUT, "glam_int", "src", "swizzles")
        lib = []
        for m in INT_SW:
            write(os.path.join(d, m + ".cairo"), read(os.path.join(SRC, "swizzles", m + ".cairo")))
            lib.append(f"pub mod {m};")
        for m in INT_SW:
            n = m[-1]
            base = "IVec" if m.startswith("i") else "UVec"
            lib.append(f"pub use {m}::{{{base}{n}Swizzles, {base}{n}SwizzlesImpl}};")
        write(os.path.join(OUT, "glam_int", "src", "swizzles.cairo"), "\n".join(lib) + "\n")
    elif VARIANT == "c3":
        sw_crate_src("glam_swizzles", FLOAT_SW)
        swz_crates["glam_swizzles"] = ["glam_core"]
        sw_crate_src("glam_int_swizzles", INT_SW)
        swz_crates["glam_int_swizzles"] = ["glam_int"]

    # lib.cairo of glam_core / glam_int; swizzle files inside core/int use crate:: paths
    if VARIANT == "b":
        for m in FLOAT_SW:
            p = os.path.join(core_src, "swizzles", m + ".cairo")
            write(p, read(p))
    # int swizzles inside glam_int: `crate::ivec2` stays valid (same crate)
    write(os.path.join(core_src, "lib.cairo"),
          "\n".join(f"pub mod {m};" for m in sorted(core_mods)) + "\n")
    core_lib = os.path.join(core_src, "lib.cairo")
    if has_int:
        int_mods = list(INT_MODS) + ["casts"] + (["swizzles"] if VARIANT in ("b", "c2") else [])
        write(os.path.join(OUT, "glam_int", "src", "lib.cairo"),
              "\n".join(f"pub mod {m};" for m in sorted(int_mods)) + "\n")

    # Scarb manifests
    write(os.path.join(OUT, "glam_core", "Scarb.toml"), scarb("glam_core", ["fixed"], "glam core"))
    if has_int:
        write(os.path.join(OUT, "glam_int", "Scarb.toml"),
              scarb("glam_int", ["fixed", "glam_core"], "glam integer vectors"))
    for c, deps in swz_crates.items():
        write(os.path.join(OUT, c, "Scarb.toml"), scarb(c, ["fixed"] + deps, "glam swizzles"))

    # facade
    facade = ["//! The `glam` facade (PK-G prototype): today's paths."]
    for m in sorted(m for m in core_mods if m != "swizzles"):
        facade.append(f"pub use glam_core::{m};")
    if has_int:
        for m in INT_MODS:
            facade.append(f"pub use glam_int::{m};")
        facade.append("pub use glam_int::casts;")
    sw_items = []
    fl = [f"{b}{n}Swizzles" for b in ("Vec",) for n in "234"]
    it = [f"{b}{n}Swizzles" for b in ("IVec", "UVec") for n in "234"]
    facade.append("pub mod swizzles {")
    if VARIANT == "a":
        for t in fl + it:
            facade.append(f"    pub use glam_swizzles::{{{t}, {t}Impl}};")
    elif VARIANT == "b":
        for t in fl:
            facade.append(f"    pub use glam_core::swizzles::{{{t}, {t}Impl}};")
        for t in it:
            facade.append(f"    pub use glam_int::swizzles::{{{t}, {t}Impl}};")
    elif VARIANT == "c1":
        for t in fl + it:
            facade.append(f"    pub use glam_swizzles::{{{t}, {t}Impl}};")
    elif VARIANT == "c2":
        for t in fl:
            facade.append(f"    pub use glam_swizzles::{{{t}, {t}Impl}};")
        for t in it:
            facade.append(f"    pub use glam_int::swizzles::{{{t}, {t}Impl}};")
    elif VARIANT == "c3":
        for t in fl:
            facade.append(f"    pub use glam_swizzles::{{{t}, {t}Impl}};")
        for t in it:
            facade.append(f"    pub use glam_int_swizzles::{{{t}, {t}Impl}};")
    facade.append("}")
    # root re-exports of the original lib.cairo, verbatim
    orig = read(os.path.join(SRC, "lib.cairo"))
    orig = re.sub(r"pub use swizzles::\{[^}]*\};", "", orig)
    facade += [l.rstrip() for l in orig.split("\n") if l.startswith("pub use")]
    facade.append("pub use swizzles::{" + ", ".join(fl + it) + "};")
    write(os.path.join(OUT, "glam", "src", "lib.cairo"), "\n".join(facade) + "\n")
    deps = ["fixed", "glam_core"] + (["glam_int"] if has_int else []) + list(swz_crates)
    write(os.path.join(OUT, "glam", "Scarb.toml"), scarb("glam", deps, "glam facade"))
    # drop the workspace members that do not exist
    members = [m for m in ("glam_core", "glam_swizzles", "glam_int", "glam", "glam_int_swizzles")
               if os.path.isdir(os.path.join(OUT, m))]
    write(os.path.join(OUT, "Scarb.toml"),
          "[workspace]\nmembers = [" + ", ".join(f'"{m}"' for m in members) + "]\n\n"
          '[workspace.tool.fmt]\nsort-module-level-items = true\nmax-line-length = 100\n')


main()
