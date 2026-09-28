#!/usr/bin/env python3
"""Variant B of the glam cut (PK-G part B2): the integer vector types stay in glam_core.

usage: make_vb.py SRC_DIR OUT_DIR

Crates (arrows = depends on):
  glam_core           everything but swizzles and the integer method traits: the float vectors with
                      `as_ivec*` / `as_uvec*` in `Vec*Trait` (unchanged), the integer vector *types*
                      and every impl of a core trait for them (operators, conversions), which Cairo's
                      impl lookup only finds in the module of the type
  glam_int            -> glam_core   `IVec*Trait` / `UVec*Trait` + impls, constructors, private helpers
  glam_swizzles       -> glam_core   float swizzles
  glam_int_swizzles   -> glam_core   integer swizzles (the types are in the core)
  glam                facade
"""
import os
import re
import shutil
import sys

SRC, OUT = sys.argv[1], sys.argv[2]
CORE_MODS = ["affine2", "affine3", "bvec2", "bvec3", "bvec4", "camera", "euler", "mat2", "mat3",
             "mat4", "quat", "vec2", "vec3", "vec4"]
INT_MODS = ["ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4"]
FLOAT_SW = ["vec2", "vec3", "vec4"]
VERSION = "0.4.0"


def read(p):
    with open(p) as f:
        return f.read()


def write(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(s)


def scarb(name, deps):
    lines = ["[package]", f'name = "{name}"', 'description = "glam cut prototype"',
             f'version = "{VERSION}"', 'edition = "2024_07"', 'cairo-version = "2.19.4"',
             'license = "MIT"', "", "[dependencies]"]
    for d in deps:
        lines.append('fixed = "0.4.0"' if d == "fixed" else f'{d} = {{ path = "../{d}" }}')
    lines += ["", "[tool]", "fmt.workspace = true", ""]
    return "\n".join(lines)


def strip_code(line):
    line = re.sub(r"'[^']*'", "''", line)
    line = re.sub(r'"[^"]*"', '""', line)
    return line.split("//")[0]


def parse_items(text):
    """Split a module into (header_lines, items); item = dict(kind, name, pub, text)."""
    lines = text.split("\n")
    items, header, i = [], [], 0
    prefix = []
    while i < len(lines):
        l = lines[i]
        if l.startswith("//") and not l.startswith("///"):
            header.append(l) if not items and not prefix else None
            i += 1
            continue
        if l.startswith("///") or l.startswith("#["):
            prefix.append(l)
            i += 1
            continue
        if l.strip() == "":
            if prefix:  # a blank line breaks a prefix only if not followed by an item: keep
                pass
            i += 1
            continue
        # an item starts here
        start = i
        depth = 0
        body = []
        while True:
            code = strip_code(lines[i])
            depth += code.count("{") + code.count("(") + code.count("[")
            depth -= code.count("}") + code.count(")") + code.count("]")
            body.append(lines[i])
            i += 1
            done = (depth == 0 and (code.rstrip().endswith("}") or code.rstrip().endswith(";")
                                    or code.rstrip().endswith("]")))
            if done or i >= len(lines):
                break
        first = body[0]
        m = re.match(r"(pub\s+)?(struct|trait|impl|fn|const|type|use|mod)\s+(\w+)?", first)
        kind = m.group(2) if m else "?"
        name = m.group(3) if m else None
        items.append({"kind": kind, "name": name, "pub": bool(m and m.group(1)),
                      "text": "\n".join(prefix + body), "head": first})
        prefix = []
    return header, items


def inline_trait_calls(text, methods):
    """Replace `XTrait::m(a, b)` by a block with the body of the method (from `methods`)."""
    def sub(mm):
        key = (mm.group(1), mm.group(2))
        if key not in methods:
            return mm.group(0)
        params, body = methods[key]
        args = [a.strip() for a in split_args(mm.group(3))]
        assert len(args) == len(params), (key, args, params)
        lets = []
        for p, a in zip(params, args):
            pn = "self_" if p == "self" else p
            lets.append(f"let {pn} = {a};")
        b = re.sub(r"\bself\b", "self_", body)
        return "{ " + " ".join(lets) + " " + b + " }"

    return re.sub(r"\b(\w+Trait)::(\w+)\(([^;{}]*?)\)(?=[;\s,)])", sub, text)


def split_args(s):
    out, depth, cur = [], 0, ""
    for c in s:
        if c == "," and depth == 0:
            out.append(cur)
            cur = ""
            continue
        depth += c in "([{"
        depth -= c in ")]}"
        cur += c
    if cur.strip():
        out.append(cur)
    return out


def trait_methods(impl_text, trait):
    """{(trait, method): ([param names], body-inner-text)} of a `pub impl XImpl of XTrait`."""
    out = {}
    for m in re.finditer(r"fn (\w+)\(([^)]*)\)[^{]*\{", impl_text):
        name = m.group(1)
        params = [p.split(":")[0].strip() for p in split_args(m.group(2))]
        # body
        depth, j = 1, m.end()
        while depth:
            depth += impl_text[j] == "{"
            depth -= impl_text[j] == "}"
            j += 1
        body = impl_text[m.end():j - 1].strip()
        out[(trait, name)] = (params, body)
    return out


def split_int_module(name, text):
    """(core_text, int_text, core_pub_names, int_pub_names) of `ivec2.cairo` / `uvec2.cairo`."""
    header, items = parse_items(text)
    uses = [it for it in items if it["kind"] == "use"]
    rest = [it for it in items if it["kind"] != "use"]
    trait_name = [it["name"] for it in rest if it["kind"] == "trait"][0]
    impl_it = [it for it in rest if it["kind"] == "impl" and it["name"] == trait_name[:-5] + "Impl"][0]
    core, integ, priv = [], [], {}
    for it in rest:
        if it["kind"] == "struct":
            core.append(it)
        elif it["kind"] == "trait" or it is impl_it:
            integ.append(it)
        elif it["kind"] == "fn" and it["pub"]:  # the constructor
            integ.append(it)
        elif it["kind"] == "impl":
            core.append(it)
        else:  # private helper
            priv[it["name"]] = it
    methods = trait_methods(impl_it["text"], trait_name)
    core_text = "\n".join(i["text"] for i in core)
    # inline the trait-method calls of the core impls (core cannot depend on glam_int)
    core_text = inline_trait_calls(core_text, methods)
    # private helpers reachable from the core impls move to the core, made `pub`
    moved = {}
    work = core_text
    changed = True
    while changed:
        changed = False
        for n, it in priv.items():
            if n not in moved and re.search(rf"\b{n}\b", work):
                moved[n] = it
                work += "\n" + it["text"]
                changed = True
    core_items_text = core_text + "\n\n" + "\n\n".join(
        re.sub(r"^(\s*(?:#\[[^\n]*\]\n)*)fn ", r"\1pub fn ", it["text"], flags=re.M, count=0)
        if False else make_pub(it["text"]) for it in moved.values())
    int_items = integ + [it for n, it in priv.items() if n not in moved]
    use_text = "\n".join(u["text"] for u in uses)
    core_pub = [it["name"] for it in core if it["name"]]
    int_pub = [it["name"] for it in integ if it["name"]]
    return use_text, "\n".join(header), core_items_text, [i["text"] for i in int_items], core_pub, \
        int_pub, list(moved)


def make_pub(text):
    lines = text.split("\n")
    for k, l in enumerate(lines):
        if l.startswith("fn "):
            lines[k] = "pub " + l
            break
    return "\n".join(lines)


def main():
    if os.path.exists(OUT):
        sys.exit(f"{OUT} exists")
    core_src = os.path.join(OUT, "glam_core", "src")
    int_src = os.path.join(OUT, "glam_int", "src")
    os.makedirs(core_src)
    os.makedirs(int_src)
    for m in CORE_MODS:
        shutil.copy(os.path.join(SRC, m + ".cairo"), os.path.join(core_src, m + ".cairo"))
        if os.path.isdir(os.path.join(SRC, m)):
            shutil.copytree(os.path.join(SRC, m), os.path.join(core_src, m))
    facade_items = {}
    for m in INT_MODS:
        text = read(os.path.join(SRC, m + ".cairo"))
        use_text, header, core_items, int_items, core_pub, int_pub, moved = split_int_module(m, text)
        write(os.path.join(core_src, m + ".cairo"),
              header + "\n" + use_text + "\n\n" + core_items + "\n")
        int_uses = re.sub(r"\buse crate::", "use glam_core::", use_text)
        own = [n for n in core_pub if n[0].isupper() and re.fullmatch(r"[IU]Vec\d", n)]
        imp = f"use glam_core::{m}::{{{', '.join(own + moved)}}};\n"
        write(os.path.join(int_src, m + ".cairo"),
              header + "\n" + int_uses + "\n" + imp + "\n" + "\n\n".join(int_items) + "\n")
        facade_items[m] = (core_pub, int_pub)
    write(os.path.join(core_src, "lib.cairo"),
          "\n".join(f"pub mod {m};" for m in sorted(CORE_MODS + INT_MODS)) + "\n")
    write(os.path.join(int_src, "lib.cairo"),
          "\n".join(f"pub mod {m};" for m in sorted(INT_MODS)) + "\n")
    write(os.path.join(OUT, "glam_core", "Scarb.toml"), scarb("glam_core", ["fixed"]))
    write(os.path.join(OUT, "glam_int", "Scarb.toml"), scarb("glam_int", ["fixed", "glam_core"]))

    def sw_crate(crate, mods, dep):
        d = os.path.join(OUT, crate, "src")
        lib = []
        for m in mods:
            t = read(os.path.join(SRC, "swizzles", m + ".cairo"))
            t = re.sub(r"\buse crate::", "use glam_core::", t)
            write(os.path.join(d, "swz_" + m + ".cairo"), t)
            lib.append(f"pub mod swz_{m};")
        for m in mods:
            n = m[-1]
            base = {"vec": "Vec", "ivec": "IVec", "uvec": "UVec"}[re.match(r"[a-z]+", m).group(0)]
            lib.append(f"pub use swz_{m}::{{{base}{n}Swizzles, {base}{n}SwizzlesImpl}};")
        write(os.path.join(d, "lib.cairo"), "\n".join(lib) + "\n")
        write(os.path.join(OUT, crate, "Scarb.toml"), scarb(crate, ["fixed", dep]))

    sw_crate("glam_swizzles", FLOAT_SW, "glam_core")
    sw_crate("glam_int_swizzles", INT_MODS, "glam_core")

    # facade
    fl = [f"Vec{n}Swizzles" for n in "234"]
    it = [f"{b}{n}Swizzles" for b in ("IVec", "UVec") for n in "234"]
    fac = ["//! The `glam` facade (variant B prototype)."]
    for m in sorted(CORE_MODS):
        fac.append(f"pub use glam_core::{m};")
    for m in INT_MODS:
        core_pub, int_pub = facade_items[m]
        fac.append(f"pub mod {m} {{")
        fac.append(f"    pub use glam_core::{m}::{{{', '.join(core_pub)}}};")
        fac.append(f"    pub use glam_int::{m}::{{{', '.join(int_pub)}}};")
        fac.append("}")
    fac.append("pub mod swizzles {")
    for t in fl:
        fac.append(f"    pub use glam_swizzles::{{{t}, {t}Impl}};")
    for t in it:
        fac.append(f"    pub use glam_int_swizzles::{{{t}, {t}Impl}};")
    fac.append("}")
    orig = re.sub(r"pub use swizzles::\{[^}]*\};", "", read(os.path.join(SRC, "lib.cairo")))
    fac += [l.rstrip() for l in orig.split("\n") if l.startswith("pub use")]
    fac.append("pub use swizzles::{" + ", ".join(fl + it) + "};")
    write(os.path.join(OUT, "glam", "src", "lib.cairo"), "\n".join(fac) + "\n")
    write(os.path.join(OUT, "glam", "Scarb.toml"),
          scarb("glam", ["fixed", "glam_core", "glam_int", "glam_swizzles", "glam_int_swizzles"]))
    members = ["glam_core", "glam_swizzles", "glam_int", "glam", "glam_int_swizzles"]
    write(os.path.join(OUT, "Scarb.toml"),
          "[workspace]\nmembers = [" + ", ".join(f'"{m}"' for m in members) + "]\n\n"
          '[workspace.tool.fmt]\nsort-module-level-items = true\nmax-line-length = 100\n')


main()
