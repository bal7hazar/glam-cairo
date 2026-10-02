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
# Only when their inputs changed since <base>: the code generators' `--check`, the golden vectors and,
# in the heavy group, the build of the touched packages and of the workspace packages that depend on
# them, the lint (`--test --deny-warnings`) of the touched packages only, and the class size of the
# consumer fixture. Nothing Cairo-related runs when no Cairo source, manifest or toolchain file changed.
#
# The heavy group (compile, lint, bytecode_size) on the shared VPS: the machine shim ~/.local/bin/scarb
# serialises `scarb build|lint|...` on ~/orchestrator/heavy-build.lock. This script takes that lock
# itself, once, for the whole group (`flock -w 90 -E 75`), writes a marker file once it holds it, and
# inside the group calls the real scarb with HEAVY_BUILD_LOCK_HELD=1 (set only there). When the lock
# is still busy after 90 s (exit 75, empty marker) the heavy steps are left to CI and the script
# passes. When HEAVY_BUILD_LOCK_HELD is set or an ancestor already holds the lock, the group runs
# directly. Without a lock directory or without flock (a Mac), the steps call scarb through PATH.
# Nothing is ever killed.
#
# Left to CI (`scripts/check.sh`, the full gate): the snforge test suites, the gas snapshots
# (`scripts/bench.py check`), `scarb doc`, the workspace-wide build and lint, the lint of the
# dependents of a touched package, the generator unit tests of tools/refgen, and the consumer-cost
# measures.
set -euo pipefail
cd "$(dirname "$0")/.."

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }

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

# The heavy group: SCARB (the scarb to call), RUN_BYTECODE, TOUCHED and DEPENDENTS (space separated).
heavy_group() {
  local package
  for package in $TOUCHED $DEPENDENTS; do
    step "scarb build -p $package" "$SCARB" build -p "$package"
  done
  for package in $TOUCHED; do
    step "scarb lint -p $package" "$SCARB" lint -p "$package" --test --deny-warnings
  done
  if [[ "$RUN_BYTECODE" == true ]]; then
    step "bytecode_size check" python3 scripts/bytecode_size.py check
  fi
}

# Used by the group when it runs under the lock in a child shell (see run_heavy).
if [[ "${1:-}" == "--heavy-group" ]]; then
  heavy_group
  exit 0
fi

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

changed=$(git diff --name-only "$base...$sha")

# A here-string, not a pipe: `grep -q` closing early must not fail the left side under pipefail.
changed_matching() { grep -Eq "$1" <<<"$changed"; }

# 1. Unlocked steps first: they fail fast.
total_start=$(now)
step "scarb fmt --check" scarb fmt --check --workspace
step "consumer_cost self-test" python3 scripts/consumer_cost.py --self-test
step "packages_table self-test" python3 scripts/packages_table.py --self-test
step "unit tests of the scripts" python3 -m unittest discover -s scripts/tests -p 'test_*.py'
step "api_parity --check" python3 scripts/api_parity.py --check
step "panic_coverage --check" python3 scripts/panic_coverage.py --check
step "gas_tables --check" python3 scripts/gas_tables.py --check
step "affected --check" python3 scripts/affected.py --check

cairo_re='(\.cairo|(^|/)Scarb\.toml|(^|/)Scarb\.lock|^\.tool-versions)$'
cairo_changed=false
changed_matching "$cairo_re" && cairo_changed=true

if $cairo_changed || changed_matching '^tools/codegen/'; then
  for gen in fvec fmat intvec swizzles; do
    step "codegen $gen --check" python3 "tools/codegen/$gen.py" --check
  done
fi

if changed_matching '^(tools/refgen/|packages/glam/tests/golden_)' && command -v cargo >/dev/null 2>&1; then
  step "golden vectors" cargo run --quiet --locked --manifest-path tools/refgen/Cargo.toml -- check
fi

if ! $cairo_changed; then
  echo "==> no Cairo source, manifest or toolchain file changed since $base: no compile, no lint"
  echo "prepush passed: $sha ($(elapsed "$total_start" "$(now)") s in total)"
  exit 0
fi

# 2. The packages: TOUCHED (built and linted) and their DEPENDENTS (built only), transitively.
# A failure of the helper fails the script (assignment, not a process substitution).
selection=$(python3 -c '
import re
import sys
import tomllib
from pathlib import Path

cairo = re.compile(sys.argv[1])
manifests = {p.parent.name: tomllib.loads(p.read_text()) for p in Path("packages").glob("*/Scarb.toml")}
touched, workspace = set(), False
for path in sys.stdin.read().split("\n"):
    if not cairo.search(path):
        continue
    parts = path.split("/")
    if len(parts) > 2 and parts[0] == "packages" and parts[1] in manifests:
        touched.add(parts[1])
    else:
        workspace = True
if workspace:
    touched = set(manifests)
closure = set(touched)
grew = True
while grew:
    grew = False
    for name, manifest in manifests.items():
        deps = set(manifest.get("dependencies", {})) | set(manifest.get("dev-dependencies", {}))
        if name not in closure and deps & closure:
            closure.add(name)
            grew = True
print("touched", *sorted(touched))
print("dependents", *sorted(closure - touched))
' "$cairo_re" <<<"$changed")
TOUCHED=$(sed -n 's/^touched *//p' <<<"$selection")
DEPENDENTS=$(sed -n 's/^dependents *//p' <<<"$selection")
[[ -n "$TOUCHED" ]] || { echo "prepush: no package selected" >&2; exit 1; }
RUN_BYTECODE=false
changed_matching '^packages/(glam_core|glam_int|glam_swizzles|glam_int_swizzles|glam|consumer)/(src/|Scarb\.toml)|^Scarb\.(toml|lock)$|^\.tool-versions$|^gas/bytecode\.size$' &&
  RUN_BYTECODE=true
export TOUCHED DEPENDENTS RUN_BYTECODE

# 3. The heavy group, under the shared lock when this machine has one.
lock=${HEAVY_BUILD_LOCK:-$HOME/orchestrator/heavy-build.lock}
scarb_path=$(command -v scarb)

ancestor_holds_lock() {
  local p=$PPID
  while [[ -n "$p" && "$p" -gt 1 ]] 2>/dev/null; do
    if ls -l "/proc/$p/fd" 2>/dev/null | grep -qF -- "$lock"; then return 0; fi
    p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null) || return 1
  done
  return 1
}

if [[ -n "${HEAVY_BUILD_LOCK_HELD:-}" ]] || ancestor_holds_lock; then
  # The lock is already ours: run the group directly.
  SCARB=scarb
  heavy_group
elif [[ -d "$(dirname "$lock")" ]] && command -v flock >/dev/null 2>&1 && grep -qs HEAVY_BUILD_LOCK "$scarb_path"; then
  real="$HOME/.asdf/shims/scarb"
  [[ -x "$real" ]] || { echo "prepush: real scarb not found at $real" >&2; exit 1; }
  marker=$(mktemp)
  trap 'rm -f "$marker"' EXIT
  wait_start=$(now)
  rc=0
  # The group runs in a child of flock, so the shim finds the lock held through HEAVY_BUILD_LOCK_HELD.
  flock -w 90 -E 75 "$lock" bash -c '
    echo locked >"$1"
    export HEAVY_BUILD_LOCK_HELD=1 SCARB="$2"
    exec nice -n 10 bash "$3" --heavy-group
  ' _ "$marker" "$real" "$(readlink -f "$0")" || rc=$?
  if [[ "$rc" -eq 75 && ! -s "$marker" ]]; then
    echo "heavy lock busy: Cairo compile left to CI (waited $(elapsed "$wait_start" "$(now)") s)"
    echo "prepush: passed (heavy steps left to CI)"
    exit 0
  elif [[ "$rc" -ne 0 ]]; then
    exit "$rc"
  fi
else
  # No lock directory or no flock (a Mac): the steps call scarb through PATH.
  SCARB=scarb
  heavy_group
fi

echo "prepush passed: $sha ($(elapsed "$total_start" "$(now)") s in total)"
