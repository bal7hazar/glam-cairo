# Packages

Generated file, do not edit by hand. Run: 2026-09-29, runner: ubuntu-latest, 4 vCPU / 15 GB, 3 cold build round(s) per consumer (medians of the per-round differences). Regenerate: run `python3 scripts/consumer_cost.py --repeat 5 --interleave --json consumer_cost.json` (CI: the `Consumer cost` job uploads `consumer_cost.json` and this table as the artifact `consumer-cost`), then `python3 scripts/packages_table.py consumer_cost.json --runner RUNNER --output docs/PACKAGES.md`.

Gates: at most 40,000 library lines; marginal cost at most 5 s / 1 GB (gate 2); closures 15 s / 3 GB unless they declare a budget (gate 3). Each figure is `value / limit (margin)`; the margin is the room left below the limit, negative when over it.

## Published packages

| package | version | lines | marginal time | marginal memory | verdict |
|---|---|---:|---:|---:|---|
| glam | 0.4.1 | 170 (gate 3 only) | closure 2.4 s / 15 s (+84 %) | closure 0.72 GB / 3 GB (+76 %) | ok |
| glam_core | 0.4.1 | 18,727 / 40,000 (+53 %) | 0.7 s / 5 s (+86 %) | 0.25 GB / 1 GB (+75 %) | ok |
| glam_int | 0.4.1 | 8,606 / 40,000 (+78 %) | 0.3 s / 5 s (+94 %) | 0.07 GB / 1 GB (+93 %) | ok |
| glam_int_swizzles | 0.4.1 | 9,600 / 40,000 (+76 %) | 0.3 s / 5 s (+95 %) | 0.10 GB / 1 GB (+90 %) | ok |
| glam_swizzles | 0.4.1 | 4,803 / 40,000 (+88 %) | 0.2 s / 5 s (+96 %) | 0.03 GB / 1 GB (+97 %) | ok |

## Declared closures

| closure | members | time | memory | budget | verdict |
|---|---|---:|---:|---|---|
| core_int | glam_core, glam_int | 1.8 s / 15 s (+88 %) | 0.56 GB / 3 GB (+81 %) | 15 s / 3 GB | ok |
| core_int_swizzles | glam_core, glam_int_swizzles | 1.7 s / 15 s (+89 %) | 0.59 GB / 3 GB (+80 %) | 15 s / 3 GB | ok |
| core_swizzles | glam_core, glam_swizzles | 1.8 s / 15 s (+88 %) | 0.54 GB / 3 GB (+82 %) | 15 s / 3 GB | ok |
