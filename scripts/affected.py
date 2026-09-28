#!/usr/bin/env python3
"""Select glam test targets and bench modules affected by a git diff.

Usage:
  scripts/affected.py <base>             print a JSON plan for <base>...HEAD
  scripts/affected.py --paths PATH...    print a JSON plan for an explicit path list
  scripts/affected.py --check            validate glam's explicit [[test]] coverage

Unknown or global paths deliberately select everything. Markdown-only changes select no Cairo
tests or benches; the caller still runs the documentation checks.
"""
import argparse
import json
import re
import subprocess
import sys
import tomllib
from collections import defaultdict, deque
from dataclasses import asdict, dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GLAM = ROOT / "packages" / "glam"
GLAM_TESTS = GLAM / "tests"
BENCH_TESTS = ROOT / "packages" / "benches" / "tests"

# The crates of the glam cut (docs/audits/PK-G-glam-cut-plan.md, section 9). `glam` is the facade:
# it holds the tests and, next to `lib.cairo`, only re-exports. A source file is a "unit"
# `<crate>:<file>`; imports link units, so a change in `glam_int` selects the integer targets only
# while a change of a `glam_core` module selects everything that imports it, across crates. What the
# test targets are named after is a "module" (`test_ivec2` tests the units `glam_core:ivec2` and
# `glam_int:ivec2` together; every file of the swizzle crates belongs to the module `swizzles`).
CRATES = ("glam_core", "glam_int", "glam_swizzles", "glam_int_swizzles", "glam")
SWIZZLE_CRATES = ("glam_swizzles", "glam_int_swizzles")
SRC_ROOTS = {crate: ROOT / "packages" / crate / "src" for crate in CRATES}
SRC_RE = re.compile(r"packages/(" + "|".join(CRATES) + r")/src/(.+)\.cairo")


def unit_of(crate: str, relative: str) -> str:
    """`glam_core`, `camera/rh/view.cairo` -> `glam_core:camera`; `lib.cairo` -> `glam_core:lib`."""
    return f"{crate}:{Path(relative).parts[0].removesuffix('.cairo')}"


def module_of(unit: str) -> str:
    """The module the test and bench targets are named after: `glam_int:ivec2` -> `ivec2`."""
    crate, name = unit.split(":")
    return "swizzles" if crate in SWIZZLE_CRATES and name != "lib" else name


def source_files() -> list[tuple[str, Path]]:
    return [
        (crate, path)
        for crate, root in SRC_ROOTS.items()
        for path in sorted(root.rglob("*.cairo"))
    ]


UNITS = {
    unit_of(crate, str(path.relative_to(SRC_ROOTS[crate]))) for crate, path in source_files()
}
MODULES = {module_of(unit) for unit in UNITS if not unit.endswith(":lib")}

CODEGEN_MODULES = {
    "fvec.py": {"vec2", "vec3", "vec4"},
    "fvec_tests.py": {"vec2", "vec3", "vec4"},
    "fmat.py": {"mat2", "mat3", "mat4"},
    "fmat_tests.py": {"mat2", "mat3", "mat4"},
    "intvec.py": {"ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4"},
    "intvec_tests.py": {"ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4"},
    "intvec_bench.py": {"ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4"},
    "swizzles.py": {"swizzles"},
}

USE_RE = re.compile(r"\buse\s+(crate|glam_core|glam_int)::([a-zA-Z_][a-zA-Z0-9_]*)")
PATH_RE = re.compile(r'#\[path\("([^"\n]+)"\)\]')


@dataclass(frozen=True)
class Plan:
    all: bool
    docs_only: bool
    tests: list[str]
    benches: list[str]
    modules: list[str]


def test_targets(manifest_path: Path = GLAM / "Scarb.toml") -> dict[str, dict]:
    manifest = tomllib.loads(manifest_path.read_text())
    targets = manifest.get("test", [])
    by_name = {target.get("name"): target for target in targets}
    if len(by_name) != len(targets) or None in by_name:
        raise ValueError("packages/glam/Scarb.toml has duplicate or unnamed [[test]] targets")
    return by_name


def target_files(target: dict, tests_dir: Path = GLAM_TESTS) -> set[str]:
    source = target.get("source-path", "")
    if not source.startswith("tests/") or not source.endswith(".cairo"):
        return set()
    root = tests_dir / Path(source).name
    if not root.is_file():
        return set()
    included = {Path(source).name}
    included.update(PATH_RE.findall(root.read_text()))
    return included


def target_index(
    manifest_path: Path = GLAM / "Scarb.toml", tests_dir: Path = GLAM_TESTS
) -> tuple[list[str], dict[str, str]]:
    targets = test_targets(manifest_path)
    files: dict[str, str] = {}
    for name, target in targets.items():
        for filename in target_files(target, tests_dir):
            if filename.startswith(("test_", "golden_")):
                if filename in files:
                    raise ValueError(
                        f"packages/glam/tests/{filename} is covered by both "
                        f"{files[filename]} and {name}"
                    )
                files[filename] = name
    return sorted(targets), files


def check_targets() -> None:
    targets = test_targets()
    errors = []
    for name, target in sorted(targets.items()):
        source = target.get("source-path")
        if target.get("test-type") != "integration":
            errors.append(f"[[test]] {name}: expected test-type = \"integration\"")
        if not source or not (GLAM / source).is_file():
            errors.append(f"[[test]] {name}: missing source-path {source!r}")
    try:
        _, covered = target_index()
    except ValueError as error:
        errors.append(str(error))
        covered = {}
    expected = {
        path.name
        for path in GLAM_TESTS.glob("*.cairo")
        if path.name.startswith(("test_", "golden_"))
    }
    errors.extend(
        f"test file without a [[test]] target: tests/{name}"
        for name in sorted(expected - covered.keys())
    )
    errors.extend(
        f"[[test]] includes missing or unexpected test file: tests/{name}"
        for name in sorted(covered.keys() - expected)
    )
    if errors:
        raise SystemExit("packages/glam/Scarb.toml is out of sync with tests/:\n  " + "\n  ".join(errors))
    print(f"glam test targets OK ({len(targets)} targets, {len(expected)} files)")


def reverse_imports() -> dict[str, set[str]]:
    """imported unit -> units that import it, across the five crates."""
    reverse: dict[str, set[str]] = defaultdict(set)
    for crate, path in source_files():
        owner = unit_of(crate, str(path.relative_to(SRC_ROOTS[crate])))
        if owner.endswith(":lib"):
            continue
        for target, name in USE_RE.findall(path.read_text()):
            imported = f"{crate if target == 'crate' else target}:{name}"
            if imported in UNITS and imported != owner:
                reverse[imported].add(owner)
    return reverse


def dependents(modules: set[str], reverse: dict[str, set[str]]) -> set[str]:
    result = set(modules)
    queue = deque(modules)
    while queue:
        module = queue.popleft()
        for dependent in reverse.get(module, set()):
            if dependent not in result:
                result.add(dependent)
                queue.append(dependent)
    return result


def module_test_targets(modules: set[str], files: dict[str, str], golden_only=False) -> set[str]:
    prefixes = ("golden_",) if golden_only else ("test_", "golden_")
    return {
        files[f"{prefix}{module}.cairo"]
        for module in modules
        for prefix in prefixes
        if f"{prefix}{module}.cairo" in files
    }


def is_doc(path: str) -> bool:
    return path.endswith(".md") or path.startswith("docs/")


def plan_paths(
    paths: list[str],
    all_targets: list[str] | None = None,
    files: dict[str, str] | None = None,
    reverse: dict[str, set[str]] | None = None,
    modules: set[str] | None = None,
    bench_modules: set[str] | None = None,
) -> Plan:
    all_targets, files = (all_targets, files) if all_targets is not None else target_index()
    reverse = reverse if reverse is not None else reverse_imports()
    modules = modules if modules is not None else MODULES
    bench_modules = bench_modules if bench_modules is not None else {
        path.stem.removeprefix("bench_") for path in BENCH_TESTS.glob("bench_*.cairo")
    }
    paths = [path.removeprefix("./") for path in paths if path]
    if not paths:
        return Plan(False, True, [], [], [])
    if all(is_doc(path) for path in paths):
        return Plan(False, True, [], [], [])

    selected_tests: set[str] = set()
    selected_benches: set[str] = set()
    selected_modules: set[str] = set()
    select_all = False

    for path in paths:
        match = SRC_RE.fullmatch(path)
        if match:
            unit = unit_of(match.group(1), match.group(2))
            if unit.endswith(":lib") or module_of(unit) not in modules:
                select_all = True
                break
            affected = {module_of(u) for u in dependents({unit}, reverse)}
            selected_modules.update(affected)
            selected_tests.update(module_test_targets(affected, files))
            selected_benches.update(affected & bench_modules)
            continue

        match = re.fullmatch(r"packages/glam/tests/(test|golden)_([a-z0-9_]+)\.cairo", path)
        if match:
            filename = Path(path).name
            if filename not in files:
                select_all = True
                break
            selected_tests.add(files[filename])
            selected_modules.add(match.group(2))
            continue

        match = re.fullmatch(r"packages/benches/tests/bench_([a-z0-9_]+)\.cairo", path)
        if match and match.group(1) in bench_modules:
            selected_benches.add(match.group(1))
            selected_modules.add(match.group(1))
            continue

        if path.startswith("tools/codegen/"):
            generated = CODEGEN_MODULES.get(Path(path).name)
            if generated is None:
                select_all = True
                break
            selected_modules.update(generated)
            selected_tests.update(module_test_targets(generated, files))
            selected_benches.update(generated & bench_modules)
            continue

        match = re.fullmatch(r"tools/refgen/(?:specs|src/oracles)/([a-z0-9_]+)\.(?:toml|rs)", path)
        if match and match.group(1) in modules:
            module = match.group(1)
            selected_modules.add(module)
            selected_tests.update(module_test_targets({module}, files, golden_only=True))
            continue

        if is_doc(path):
            continue

        select_all = True
        break

    if select_all:
        return Plan(True, False, sorted(all_targets), sorted(bench_modules), sorted(modules))
    return Plan(
        False,
        False,
        sorted(selected_tests),
        sorted(selected_benches),
        sorted(selected_modules),
    )


def changed_paths(base: str) -> list[str]:
    process = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...HEAD"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return process.stdout.splitlines()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("base", nargs="?", help="git revision used as the merge-base side")
    parser.add_argument("--paths", nargs="*", help="plan an explicit list instead of invoking git")
    parser.add_argument("--check", action="store_true", help="validate explicit test targets")
    args = parser.parse_args()
    if args.check:
        check_targets()
        return
    if args.paths is None and not args.base:
        parser.error("BASE or --paths is required")
    paths = args.paths if args.paths is not None else changed_paths(args.base)
    print(json.dumps(asdict(plan_paths(paths)), separators=(",", ":")))


if __name__ == "__main__":
    main()
