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
GLAM_SRC = GLAM / "src"
GLAM_TESTS = GLAM / "tests"
BENCH_TESTS = ROOT / "packages" / "benches" / "tests"

MODULES = {
    path.relative_to(GLAM_SRC).parts[0].removesuffix(".cairo")
    for path in GLAM_SRC.rglob("*.cairo")
    if path.name != "lib.cairo"
}

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

USE_RE = re.compile(r"\buse\s+(?:crate|glam)::([a-zA-Z_][a-zA-Z0-9_]*)")
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


def owner_module(path: Path) -> str:
    relative = path.relative_to(GLAM_SRC)
    return relative.parts[0].removesuffix(".cairo")


def reverse_imports(src_dir: Path = GLAM_SRC) -> dict[str, set[str]]:
    reverse: dict[str, set[str]] = defaultdict(set)
    for path in src_dir.rglob("*.cairo"):
        if path.name == "lib.cairo":
            continue
        owner = owner_module(path)
        for imported in USE_RE.findall(path.read_text()):
            if imported in MODULES and imported != owner:
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
        match = re.fullmatch(r"packages/glam/src/(.+)\.cairo", path)
        if match:
            relative = Path(match.group(1))
            module = relative.parts[0]
            if module == "lib" or module not in modules:
                select_all = True
                break
            affected = dependents({module}, reverse)
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
