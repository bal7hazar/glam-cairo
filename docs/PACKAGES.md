# Packages

Generated file, do not edit by hand. Run: 2026-10-03, runner: ubuntu-latest, 4 vCPU / 15 GB, 3 cold build round(s) per consumer (medians of the per-round differences). Regenerate: run `python3 scripts/consumer_cost.py --repeat 5 --interleave --json consumer_cost.json` (CI: the `Consumer cost` job uploads `consumer_cost.json` and this table as the artifact `consumer-cost`), then `python3 scripts/packages_table.py consumer_cost.json --runner RUNNER --output docs/PACKAGES.md`.

Gates: at most 40,000 library lines; marginal cost at most 5 s / 1 GB (gate 2); closures 15 s / 3 GB unless they declare a budget (gate 3). Each figure is `value / limit (margin)`; the margin is the room left below the limit, negative when over it.

## Published packages

| package | version | lines | marginal time | marginal memory | verdict |
|---|---|---:|---:|---:|---|
| glam | 0.5.0 | 170 (gate 3 only) | closure 2.3 s / 15 s (+85 %) | closure 0.68 GB / 3 GB (+77 %) | ok |
| glam_core | 0.5.0 | 20,067 / 40,000 (+50 %) | 0.7 s / 5 s (+86 %) | 0.25 GB / 1 GB (+75 %) | ok |
| glam_int | 0.5.0 | 8,918 / 40,000 (+78 %) | 0.1 s / 5 s (+99 %) | 0.08 GB / 1 GB (+92 %) | ok |
| glam_int_swizzles | 0.5.0 | 9,600 / 40,000 (+76 %) | 0.1 s / 5 s (+98 %) | 0.09 GB / 1 GB (+91 %) | ok |
| glam_swizzles | 0.5.0 | 4,803 / 40,000 (+88 %) | 0.2 s / 5 s (+96 %) | 0.03 GB / 1 GB (+97 %) | ok |

## Declared closures

| closure | members | time | memory | budget | verdict |
|---|---|---:|---:|---|---|
| core_int | glam_core, glam_int | 1.9 s / 15 s (+87 %) | 0.52 GB / 3 GB (+83 %) | 15 s / 3 GB | ok |
| core_int_swizzles | glam_core, glam_int_swizzles | 2.0 s / 15 s (+87 %) | 0.54 GB / 3 GB (+82 %) | 15 s / 3 GB | ok |
| core_swizzles | glam_core, glam_swizzles | 1.7 s / 15 s (+89 %) | 0.50 GB / 3 GB (+83 %) | 15 s / 3 GB | ok |
