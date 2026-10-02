#!/usr/bin/env bash
# Pre-push check: the cheap part of the gate, run before every push (`.githooks/pre-push` calls it).
#
#   scripts/prepush.sh [<sha> [<base>]]
#
# <sha> is the commit to check (default HEAD; the hook passes the pushed sha), <base> the commit the
# change is measured from (default: the merge base of <sha> and origin/main). The checks run on the
# working tree, so the script refuses when the tree is not exactly <sha>.
#
# Always: `scarb fmt --check`, the self-tests of the Python scripts, the unit tests under
# scripts/tests, and the `--check` modes of the scripts that compare documents with committed sources.
# Only when their inputs changed since <base>: build and lint of the touched packages and of the
# workspace packages that depend on them, the code generators' `--check`, the class size of the
# consumer fixture, the golden vectors. Nothing Cairo-related runs when no Cairo source, manifest or
# toolchain file changed.
#
# Left to CI (`scripts/check.sh`, the full gate): the snforge test suites, the gas snapshots
# (`scripts/bench.py check`), `scarb doc`, the workspace-wide build and lint, the generator unit tests
# of tools/refgen, and the consumer-cost measures.
#
# On the shared VPS `scarb build|lint|check` go through ~/.local/bin/scarb, which serialises them on
# ~/orchestrator/heavy-build.lock. The locked steps are never run around it: the script takes the lock
# itself once (the shim recognises a holder among its ancestors), so that the wait is printed apart
# from the work.
set -euo pipefail
cd "$(dirname "$0")/.."

sha=$(git rev-parse --verify "${1:-HEAD}^{commit}")
head=$(git rev-parse HEAD)
base=${2:-$(git merge-base "$sha" origin/main)}

if [[ "$head" != "$sha" || -n "$(git status --porcelain)" ]]; then
  {
    echo "prepush: refusing to check: the working tree is not exactly the commit to check."
    echo "  checked sha: $sha"
    echo "  HEAD:        $head"
    git status --short | sed 's/^/  /'
    echo "The checks run on the working tree but a push sends commits: commit the changes (or remove"
    echo "them) and check out the commit to push. Never use --no-verify."
  } >&2
  exit 1
fi

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }

total_start=$(now)
lock_wait=0

step() {
  local name=$1
  shift
  echo "==> $name"
  local start
  start=$(now)
  if "$@"; then
    echo "    ok ($(elapsed "$start" "$(now)") s)"
  else
    echo "    FAILED: $name ($(elapsed "$start" "$(now)") s)" >&2
    exit 1
  fi
}

mapfile -t changed < <(git diff --name-only "$base...$sha")

changed_matching() { printf '%s\n' "${changed[@]}" | grep -Eq "$1"; }

# 1. Unlocked steps first: they fail fast.
step "scarb fmt --check" scarb fmt --check --workspace
step "consumer_cost self-test" python3 scripts/consumer_cost.py --self-test
step "packages_table self-test" python3 scripts/packages_table.py --self-test
step "unit tests of the scripts" python3 -m unittest discover -s scripts/tests -p 'test_*.py'
step "api_parity --check" python3 scripts/api_parity.py --check
step "panic_coverage --check" python3 scripts/panic_coverage.py --check
step "gas_tables --check" python3 scripts/gas_tables.py --check
step "affected --check" python3 scripts/affected.py --check

cairo_re='(\.cairo|(^|/)Scarb\.toml|(^|/)Scarb\.lock|^\.tool-versions)$'
if changed_matching "$cairo_re"; then
  cairo_changed=true
else
  cairo_changed=false
fi

if $cairo_changed || changed_matching '^tools/codegen/'; then
  for gen in fvec fmat intvec swizzles; do
    step "codegen $gen --check" python3 "tools/codegen/$gen.py" --check
  done
fi

if changed_matching '^(tools/refgen/|packages/glam/tests/golden_)' && command -v cargo >/dev/null 2>&1; then
  step "golden vectors" cargo run --quiet --locked --manifest-path tools/refgen/Cargo.toml -- check
fi

# 2. The packages to compile: the touched ones and everything that depends on them, transitively.
if $cairo_changed; then
  mapfile -t packages < <(printf '%s\n' "${changed[@]}" | python3 -c '
import re
import sys
import tomllib
from pathlib import Path

cairo = re.compile(sys.argv[1])
manifests = {p.parent.name: tomllib.loads(p.read_text()) for p in Path("packages").glob("*/Scarb.toml")}
touched, workspace = set(), False
for line in sys.stdin.read().split():
    if not cairo.search(line):
        continue
    parts = line.split("/")
    if len(parts) > 2 and parts[0] == "packages" and parts[1] in manifests:
        touched.add(parts[1])
    else:
        workspace = True
if workspace:
    touched = set(manifests)
changed = True
while changed:
    changed = False
    for name, manifest in manifests.items():
        deps = set(manifest.get("dependencies", {})) | set(manifest.get("dev-dependencies", {}))
        if name not in touched and deps & touched:
            touched.add(name)
            changed = True
print(*sorted(touched), sep="\n")
' "$cairo_re")
  [[ ${#packages[@]} -gt 0 ]] || { echo "prepush: no package selected" >&2; exit 1; }

  # Take the shared lock once, timed apart, when scarb is the machine shim.
  lock=${HEAVY_BUILD_LOCK:-$HOME/orchestrator/heavy-build.lock}
  if grep -qs HEAVY_BUILD_LOCK "$(command -v scarb)"; then
    echo "==> waiting for $lock"
    start=$(now)
    mkdir -p "$(dirname "$lock")"
    exec 9>"$lock"
    flock 9
    lock_wait=$(elapsed "$start" "$(now)")
    echo "    lock acquired after $lock_wait s"
  fi

  for package in "${packages[@]}"; do
    step "scarb build -p $package" scarb build -p "$package"
  done
  for package in "${packages[@]}"; do
    step "scarb lint -p $package" scarb lint -p "$package" --test --deny-warnings
  done
  library_re='^packages/(glam_core|glam_int|glam_swizzles|glam_int_swizzles|glam|consumer)/(src/|Scarb\.toml)'
  if changed_matching "$library_re|^Scarb\.(toml|lock)$|^\.tool-versions$|^gas/bytecode\.size$"; then
    step "bytecode_size check" python3 scripts/bytecode_size.py check
  fi
else
  echo "==> no Cairo source, manifest or toolchain file changed since $base: no compile, no lint"
fi

total=$(elapsed "$total_start" "$(now)")
echo "prepush passed: $sha ($total s in total, of which $lock_wait s waiting for the build lock)"
