# Packages

Generated file, do not edit by hand. Run: 2026-10-02, runner: ubuntu-latest, 4 vCPU / 15 GB, 3 cold build round(s) per consumer (medians of the per-round differences). Regenerate: run `python3 scripts/consumer_cost.py --repeat 5 --interleave --json consumer_cost.json` (CI: the `Consumer cost` job uploads `consumer_cost.json` and this table as the artifact `consumer-cost`), then `python3 scripts/packages_table.py consumer_cost.json --runner RUNNER --output docs/PACKAGES.md`.

Gates: at most 40,000 library lines; marginal cost at most 5 s / 1 GB (gate 2); closures 15 s / 3 GB unless they declare a budget (gate 3). Each figure is `value / limit (margin)`; the margin is the room left below the limit, negative when over it.

## Published packages

| package | version | lines | marginal time | marginal memory | verdict |
|---|---|---:|---:|---:|---|
| glam | 0.4.1 | 170 (gate 3 only) | closure 2.3 s / 15 s (+85 %) | closure 0.63 GB / 3 GB (+79 %) | ok |
| glam_core | 0.4.1 | 18,727 / 40,000 (+53 %) | 0.7 s / 5 s (+86 %) | 0.23 GB / 1 GB (+77 %) | ok |
| glam_int | 0.4.1 | 8,606 / 40,000 (+78 %) | 0.2 s / 5 s (+95 %) | 0.06 GB / 1 GB (+94 %) | ok |
| glam_int_swizzles | 0.4.1 | 9,600 / 40,000 (+76 %) | 0.3 s / 5 s (+95 %) | 0.10 GB / 1 GB (+90 %) | ok |
| glam_swizzles | 0.4.1 | 4,803 / 40,000 (+88 %) | 0.1 s / 5 s (+98 %) | 0.05 GB / 1 GB (+95 %) | ok |

## Declared closures

| closure | members | time | memory | budget | verdict |
|---|---|---:|---:|---|---|
| core_int | glam_core, glam_int | 1.8 s / 15 s (+88 %) | 0.49 GB / 3 GB (+84 %) | 15 s / 3 GB | ok |
| core_int_swizzles | glam_core, glam_int_swizzles | 1.7 s / 15 s (+88 %) | 0.51 GB / 3 GB (+83 %) | 15 s / 3 GB | ok |
| core_swizzles | glam_core, glam_swizzles | 1.6 s / 15 s (+89 %) | 0.47 GB / 3 GB (+84 %) | 15 s / 3 GB | ok |
