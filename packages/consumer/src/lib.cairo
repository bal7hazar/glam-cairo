//! A Starknet contract fixture that links `glam` into a deployable class, so that the size of a
//! realistic consumer can be tracked against the network limits.
//!
//! Measurement fixture, not a product: `scripts/bytecode_size.py` builds this package in the
//! release profile and reports the Sierra and CASM sizes of every contract
//! (`gas/bytecode.size`); the analysis is in `docs/audits/R1-bytecode-size.md`. Every input comes
//! from calldata, so that nothing is constant-folded.
//!
//! `GlamSink` holds the heavy `glam` items a physics step touches (`Vec3`, `Quat`, `Mat3` /
//! `Mat4` inverse, `slerp`, Euler conversions, a camera projection). The scalar fixture lives in
//! `fixed-cairo`, the `glamx` ones in `glamx-cairo`. The logic lives in `sim`, like it would in a
//! real consumer.

pub mod glam_sink;
pub mod sim;
