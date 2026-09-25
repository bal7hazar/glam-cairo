# consumer

Unpublished. A Starknet contract fixture that links `glam` into a deployable class, so that the
compiled class size of a realistic consumer is tracked against the network limits:

| contract | content |
|---|---|
| `GlamSink` | the `glam` entry points of the former `KitchenSink`: circle contact on `Vec2`, a contact frame on `Vec3` / `Quat`, `Mat3` inverse of a rotated inertia tensor, `Mat4` inverse, `slerp` with Euler conversions, a camera projection |

Every input comes from calldata (nothing is constant-folded). The logic is in `src/sim.cairo`.
The scalar fixture (`Scalar`) now lives in
[`fixed-cairo`](https://github.com/bal7hazar/fixed-cairo), the `glamx` ones (`Particles2d`,
`Rigid3d`, `KitchenSink`) in [`glamx-cairo`](https://github.com/bal7hazar/glamx-cairo).

Run from the repository root:

```sh
scripts/bytecode_size.py            # size table (release build)
scripts/bytecode_size.py check      # compare with gas/bytecode.size (part of scripts/check.sh and CI)
scripts/bytecode_size.py snapshot   # rewrite gas/bytecode.size
scripts/bytecode_size.py attribution --strategy default --strategy avoid   # CASM felts per call site
```

Keep the compiler's default `inlining-strategy` in a contract that uses these packages: `avoid` or
a small numeric threshold shrinks the class by up to 27 % but costs +74 % to +177 % gas on the
library (`docs/audits/R1-bytecode-size.md` section 4.2).

Analysis and recommendations: `docs/audits/R1-bytecode-size.md`.
