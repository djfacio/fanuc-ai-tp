//! Agreement tests: proptests that cross-check `snpx-codec::addr`
//! functions against the executable form of the Verus specs in
//! `hmi-bridge-proofs::addr`. Closes the drift loop that
//! `assume_specification` alone can't: if the real body diverges
//! from what Verus was told to assume, these tests fail.
//!
//! **Add one per `assume_specification` in `hmi-bridge-proofs`.**
//! The CI lint at `ci/lint-agreement-tests` greps for unpaired specs.
//!
//! Background:
//! <https://verus-lang.github.io/verus/guide/calling-unverified-from-verified.html>

use proptest::prelude::*;
use snpx_codec::addr;

// Executable twins of the Verus specs. These are plain Rust —
// no `verus!` macro, no `vstd`. They must match the bodies of the
// corresponding `open spec fn`s in `hmi-bridge-proofs::addr`
// character-for-character (modulo Rust syntax). A divergence here
// either means the spec changed and the test didn't update, or the
// real function changed and the spec didn't update. Either way, the
// agreement is broken and the test should fail.

fn word_target_spec(addr: u16) -> u16 {
    if addr == 0 {
        0
    } else {
        addr - 1
    }
}

fn byte_target_spec(addr: u16) -> u16 {
    // Byte and word selectors share identical math; the semantic
    // difference is in the caller's interpretation of the result.
    if addr == 0 {
        0
    } else {
        addr - 1
    }
}

fn bit_write_target_spec(addr: u16) -> u16 {
    if addr == 0 {
        0
    } else {
        addr - 1
    }
}

fn bit_write_mask_spec(addr: u16) -> u8 {
    let pos: u8 = (bit_write_target_spec(addr) % 8) as u8;
    1u8 << pos
}

// bit_read_range has a richer spec: succeed-or-fail + three result
// values. Encode the success predicate and the result fields
// separately, mirroring the Verus spec in
// `hmi-bridge-proofs::addr::bit_read_range_*`.
fn bit_read_range_succeeds(addr: u16, count: u16) -> bool {
    let zero: u32 = if addr == 0 { 0 } else { (addr - 1) as u32 };
    let sum: u32 = zero + count as u32;
    if sum > u16::MAX as u32 {
        return false;
    }
    let rem = sum % 8;
    let last: u32 = sum + if rem == 0 { 0 } else { 8 - rem };
    last <= u16::MAX as u32
}

fn bit_read_range_first(addr: u16) -> u16 {
    let zero = if addr == 0 { 0 } else { addr - 1 };
    (zero / 8) * 8
}

fn bit_read_range_span(addr: u16, count: u16) -> u16 {
    let zero: u32 = if addr == 0 { 0 } else { (addr - 1) as u32 };
    let first: u32 = (zero / 8) * 8;
    let sum: u32 = zero + count as u32;
    let rem = sum % 8;
    let last: u32 = sum + if rem == 0 { 0 } else { 8 - rem };
    (last - first) as u16
}

fn bit_read_range_offset(addr: u16) -> u8 {
    let zero = if addr == 0 { 0 } else { addr - 1 };
    let first = (zero / 8) * 8;
    (zero - first) as u8
}

proptest! {
    /// `word_target` — mirrors `hmi_bridge_proofs::addr::word_target_spec`.
    #[test]
    fn agreement_word_target(addr in any::<u16>()) {
        let real = addr::word_target(addr);
        let spec = word_target_spec(addr);
        prop_assert_eq!(real, spec, "word_target({}) diverged from spec", addr);
    }

    /// `byte_target` — mirrors `hmi_bridge_proofs::addr::byte_target_spec`.
    #[test]
    fn agreement_byte_target(addr in any::<u16>()) {
        let real = addr::byte_target(addr);
        let spec = byte_target_spec(addr);
        prop_assert_eq!(real, spec, "byte_target({}) diverged from spec", addr);
    }

    /// `bit_write` — mirrors `hmi_bridge_proofs::addr::{bit_write_target_spec, bit_write_mask_spec}`.
    #[test]
    fn agreement_bit_write(addr in any::<u16>()) {
        let (real_target, real_mask) = addr::bit_write(addr);
        let spec_target = bit_write_target_spec(addr);
        let spec_mask = bit_write_mask_spec(addr);
        prop_assert_eq!(real_target, spec_target,
            "bit_write({}).0 (target) diverged from spec", addr);
        prop_assert_eq!(real_mask, spec_mask,
            "bit_write({}).1 (mask) diverged from spec", addr);
    }

    /// `bit_read_range` — mirrors
    /// `hmi_bridge_proofs::addr::{bit_read_range_succeeds, _first, _span, _offset}`.
    #[test]
    fn agreement_bit_read_range(addr in any::<u16>(), count in any::<u16>()) {
        let real = addr::bit_read_range(addr, count);
        let should_succeed = bit_read_range_succeeds(addr, count);
        prop_assert_eq!(real.is_ok(), should_succeed,
            "bit_read_range({}, {}) success predicate diverged", addr, count);
        if let Ok((first, span, offset)) = real {
            prop_assert_eq!(first, bit_read_range_first(addr),
                "first diverged at ({}, {})", addr, count);
            prop_assert_eq!(span, bit_read_range_span(addr, count),
                "span diverged at ({}, {})", addr, count);
            prop_assert_eq!(offset, bit_read_range_offset(addr),
                "offset diverged at ({}, {})", addr, count);
        }
    }
}

// Spot-check deterministic edges. proptest's default 256-case run
// will almost certainly hit these, but explicit is free and
// documents the boundaries.
#[test]
fn edges() {
    assert_eq!(addr::word_target(0), 0);
    assert_eq!(addr::word_target(1), 0);
    assert_eq!(addr::word_target(u16::MAX), u16::MAX - 1);
    assert_eq!(addr::bit_write(1), (0, 0x01));
    assert_eq!(addr::bit_write(8), (7, 0x80));
    assert_eq!(addr::bit_write(9), (8, 0x01));
    // DO[184] → (183, 0x80) — the capture cited in addr.rs.
    assert_eq!(addr::bit_write(184), (183, 0x80));
}
