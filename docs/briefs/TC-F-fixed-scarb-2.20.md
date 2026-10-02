# TC-F: fixed-cairo to Scarb 2.20.1 / starknet-foundry 0.64.0 (record)

Owner's rule D-180 (`/home/claude/projects/pm/decisions/2026-10-01-scarb-latest-migration.md`). Given inline to a
herdr thread on 2026-10-02 (before briefs were committed for this track); recorded here for the history.

Scope: `.tool-versions`, CI, toolchain pins, gas / bytecode-size snapshots and generated tables re-measured,
`docs/PACKAGES.md` re-measured. Results bit-identical; a numeric change stops the task. No release.

Result: fixed-cairo #5, merged d444ffe. No numeric change (363 tests, goldens unchanged); l2_gas -120 on 76 of 278
net rows (VPS, reproduced by CI), steps / builtins / bytecode size unchanged; Cairo pins 2.20.0 (Scarb 2.20.1
bundles Cairo 2.20.0). TC-G and TC-X follow the same scope (`TC-G-glam-scarb-2.20.md`, `TC-X-glamx-scarb-2.20.md`).
