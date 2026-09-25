#!/usr/bin/env bash
# Quality gate. With `--affected BASE`, run only the glam tests and benches selected from
# `git diff BASE...HEAD`; without arguments, run the full suite.
set -euo pipefail
cd "$(dirname "$0")/.."

base=""
plan=""
docs_only=false
if [[ $# -gt 0 ]]; then
  if [[ $# -ne 2 || "$1" != "--affected" ]]; then
    echo "usage: scripts/check.sh [--affected BASE]" >&2
    exit 2
  fi
  base=$2
  plan=$(python3 scripts/affected.py "$base")
  docs_only=$(python3 -c 'import json, sys; print(str(json.load(sys.stdin)["docs_only"]).lower())' <<<"$plan")
fi

scarb fmt --check --workspace
if [[ "$docs_only" != true ]]; then
  scarb lint --workspace --test --deny-warnings
  scarb build --workspace
  # The benches package is not run here: `bench.py check` below runs every bench (twice, once per
  # metric) and fails on any failing test, so `snforge test --workspace` would only repeat it.
  if [[ -z "$base" ]]; then
    for dir in packages/*/; do
      pkg=$(basename "$dir")
      [ "$pkg" = benches ] || snforge test -p "$pkg"
    done
    python3 scripts/bench.py check
  else
    mapfile -t test_targets < <(
      python3 -c 'import json, sys; print(*json.load(sys.stdin)["tests"], sep="\n")' <<<"$plan"
    )
    mapfile -t bench_modules < <(
      python3 -c 'import json, sys; print(*json.load(sys.stdin)["benches"], sep="\n")' <<<"$plan"
    )
    for target in "${test_targets[@]}"; do
      [[ -z "$target" ]] || snforge test "$target" -p glam
    done
    for module in "${bench_modules[@]}"; do
      [[ -z "$module" ]] || python3 scripts/bench.py check "bench_$module"
    done
  fi
  # Class size of the packages/consumer contract fixture (gas/bytecode.size, release build).
  python3 scripts/bytecode_size.py check
  # Generated source, tests and benches must match their Python templates.
  python3 tools/codegen/fvec.py --check
  python3 tools/codegen/fmat.py --check
  python3 tools/codegen/intvec.py --check
  python3 tools/codegen/swizzles.py --check
  # Golden vectors are up to date with tools/refgen (skipped when the Rust toolchain is absent; CI
  # always runs it in the `golden` job).
  if command -v cargo >/dev/null 2>&1; then
    cargo run --quiet --locked --manifest-path tools/refgen/Cargo.toml -- check
  else
    echo "cargo not found: skipping the golden vector check"
  fi
fi
python3 scripts/api_parity.py --check
python3 scripts/panic_coverage.py --check
python3 scripts/gas_tables.py --check
python3 scripts/affected.py --check
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
scarb doc --workspace --disable-remote-linking >/dev/null
echo "all checks passed"
