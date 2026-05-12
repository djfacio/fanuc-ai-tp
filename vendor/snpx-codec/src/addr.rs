//! Address-math helpers — selector-family-aware `target_index` computation.
//!
//! Centralizes the unit conversions so off-by-ones don't propagate through
//! the codec. The canonical wire-truth rule, grounded in
//! `captures:Writing-DO` (DO184..DO197 show `target_index` incrementing by
//! **1 per DO**, not 1 per 8 DOs), cross-checked against
//! `palatis:RobotIF.cs:151-173` (BSD-3):
//!
//! - Word selectors (`WORD_R`, `WORD_AI`, `WORD_AQ`):
//!   `target_index = addr - 1` at word-level.
//! - Bit selectors (`BIT_I`, `BIT_Q`, …): `target_index = addr - 1` at
//!   **bit-level**; payload byte for single-bit writes carries
//!   `1 << ((addr-1) % 8)`.
//! - Byte selectors (`BYTE_I`, `BYTE_Q`, `BYTE_G`, …):
//!   `target_index = addr - 1` at byte-level.
//!
//! Booozie's `robot_comm.py:28` uses `(addr-1)/8` for bit-selector reads —
//! that happens to coincide with the correct value only for DI/DO ≤ 8.
//! Do not follow it; see the `bit_read_range_high_addr` test below for
//! the concrete counter-example.

use crate::error::{Error, Result};

/// 1-based FANUC operator-visible address. Newtype around `u16` so
/// callers cannot confuse "the address an operator types on the
/// pendant" with "the 0-based wire index the codec emits."
///
/// `FanucAddr(0)` is explicitly allowed because Booozie's `%R[0]`
/// liveness probe relies on it — `Client::link_probe` reads that
/// address. `FanucAddr::new` validates against the caller's
/// selector-native upper bound where one applies; for the general
/// case use `FanucAddr::from_raw` and document the precondition on
/// the call-site.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct FanucAddr(u16);

impl FanucAddr {
    /// Construct without a range check. Callers that have their own
    /// bound (e.g. `$SNPX_ASG` slot plan) use this.
    #[must_use]
    pub const fn from_raw(addr: u16) -> Self {
        Self(addr)
    }

    /// Construct with a caller-supplied inclusive upper bound
    /// (selector-native). Rejects out-of-range addresses with
    /// [`Error::InvalidRequest`] so the validation lives at the
    /// public request layer rather than deep in address math.
    ///
    /// # Errors
    ///
    /// - [`Error::InvalidRequest`] if `addr > max`.
    pub fn new_bounded(addr: u16, max: u16) -> Result<Self> {
        if addr > max {
            return Err(Error::InvalidRequest(
                "FanucAddr out of selector-native range",
            ));
        }
        Ok(Self(addr))
    }

    /// Access the 1-based address. Use this when constructing user-
    /// facing log lines; never pass the raw value to the codec as a
    /// `target_index`.
    #[must_use]
    pub const fn get(self) -> u16 {
        self.0
    }
}

impl From<u16> for FanucAddr {
    fn from(addr: u16) -> Self {
        Self::from_raw(addr)
    }
}

/// Word-selector `target_index = addr - 1` (word-level, 0-based).
///
/// Saturates at 0 so `addr = 0` (the legal Booozie `%R[0]` liveness-probe
/// case) does not underflow.
#[must_use]
pub fn word_target(addr: u16) -> u16 {
    addr.saturating_sub(1)
}

/// Byte-selector `target_index = addr - 1` (byte-level, 0-based).
#[must_use]
pub fn byte_target(addr: u16) -> u16 {
    addr.saturating_sub(1)
}

/// Bit-selector single-bit write. Returns the tuple
/// `(target_index, payload_byte)` where `target_index` is the bit-level
/// 0-based index and `payload_byte` has exactly the target bit set.
///
#[must_use]
pub fn bit_write(addr: u16) -> (u16, u8) {
    let zero = addr.saturating_sub(1);
    // `zero % 8` is always in 0..=7; the shift-left fits in u8.
    let bit = zero % 8;
    let mask: u8 = 1u8.wrapping_shl(u32::from(bit));
    (zero, mask)
}

/// Bit-selector byte-aligned read window (Palatis convention,
/// `palatis:RobotIF.cs:151-173`). Returns the triple
/// `(target_index, count_bits, first_byte_bit_offset)` where:
///
/// - `target_index` is the byte-aligned bit index to request,
/// - `count_bits` is `target_count` in bits (rounded up to the next byte),
/// - `first_byte_bit_offset` is the offset of the caller's first requested
///   bit inside the first returned byte — the caller masks the returned
///   bytes with it.
///
/// # Errors
///
/// Returns [`Error::InvalidRequest`] if `addr + count` or the resulting
/// byte-aligned window would overflow `u16`. A well-behaved caller that
/// has validated against the selector-native upper bound will never hit
/// this; the check is defense-in-depth against a high `addr` + high
/// `count` pair that would otherwise wrap in release or panic in debug.
///
pub fn bit_read_range(addr: u16, count: u16) -> Result<(u16, u16, u8)> {
    let zero = addr.saturating_sub(1);
    let first = (zero / 8) * 8; // byte-aligned bit index
                                // Round `zero + count` up to the next multiple of 8 via `div_ceil`, with
                                // every arithmetic step checked.
    let sum = zero
        .checked_add(count)
        .ok_or(Error::InvalidRequest("bit_read_range: addr+count overflow"))?;
    let last = sum
        .div_ceil(8)
        .checked_mul(8)
        .ok_or(Error::InvalidRequest("bit_read_range: window exceeds u16"))?;
    let span = last
        .checked_sub(first)
        .ok_or(Error::InvalidRequest("bit_read_range: window underflow"))?;
    let offset = u8::try_from(zero - first)
        .map_err(|_| Error::InvalidRequest("bit_read_range: offset exceeds u8"))?;
    Ok((first, span, offset))
}

/// Doctest bundle — these four cases are the address-math oracles cited
/// in spec §7.
///
/// ```
/// use snpx_codec::addr::{word_target, bit_write, bit_read_range};
///
/// // Reading %R5: addr=5 -> target_index=4
/// assert_eq!(word_target(5), 4);
///
/// // Writing DO[184] ⇔ %I184 (BIT_I selector). Capture: 07 46 b7 00 01 00 80.
/// // target_index = 183 (bit-level), payload mask = 0x80.
/// assert_eq!(bit_write(184), (183, 0x80));
///
/// // DO[1]: target_index=0, mask=0x01
/// assert_eq!(bit_write(1), (0, 0x01));
///
/// // Reading DI[17..24]: byte-aligned bit index 16, 8 bits, offset 0
/// assert_eq!(bit_read_range(17, 8).unwrap(), (16, 8, 0));
/// ```
#[allow(dead_code)] // Doc-only item; the `///` block above is the whole test.
const _DOCTEST_ANCHOR: () = ();

impl From<FanucAddr> for u16 {
    fn from(a: FanucAddr) -> u16 {
        a.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fanuc_addr_preserves_raw() {
        assert_eq!(FanucAddr::from_raw(42).get(), 42);
        assert_eq!(FanucAddr::from_raw(0).get(), 0);
        assert_eq!(u16::from(FanucAddr::from_raw(7)), 7);
    }

    #[test]
    fn fanuc_addr_bounded_accepts_within_range() {
        let a = FanucAddr::new_bounded(50, 100).expect("in range");
        assert_eq!(a.get(), 50);
    }

    #[test]
    fn fanuc_addr_bounded_rejects_over_range() {
        let err = FanucAddr::new_bounded(101, 100).expect_err("out of range");
        match err {
            Error::InvalidRequest(msg) => {
                assert!(msg.contains("range"), "got: {msg}");
            }
            other => panic!("expected InvalidRequest, got {other:?}"),
        }
    }

    #[test]
    fn fanuc_addr_at_exact_max_accepted() {
        let a = FanucAddr::new_bounded(100, 100).expect("inclusive");
        assert_eq!(a.get(), 100);
    }

    #[test]
    fn word_target_zero_based() {
        assert_eq!(word_target(5), 4);
        assert_eq!(word_target(1), 0);
        assert_eq!(word_target(0), 0); // saturating
    }

    #[test]
    fn byte_target_zero_based() {
        assert_eq!(byte_target(1), 0);
        assert_eq!(byte_target(8), 7);
    }

    #[test]
    fn bit_write_low_and_high_addresses() {
        assert_eq!(bit_write(1), (0, 0x01));
        assert_eq!(bit_write(8), (7, 0x80));
        assert_eq!(bit_write(9), (8, 0x01));
        // The spec's capture: DO[184] → (183, 0x80).
        assert_eq!(bit_write(184), (183, 0x80));
    }

    /// The counter-example that disambiguates Booozie (byte-level) from
    /// Palatis (bit-level) for bit-selector reads: `bit_read_range(9, 8)`.
    ///
    /// Booozie's math `(addr-1)/8 = 1` with `count=1` would read byte 1
    /// but only bits 8..=15 — indirectly correct by coincidence.
    /// Our math (spec §7, Palatis convention): byte-aligned bit index 8,
    /// `count = 8` bits, offset 0 inside the first returned byte.
    #[test]
    fn bit_read_range_high_addr() {
        // addr = 9, count = 8 → DI[9..=16], which is the whole second byte.
        assert_eq!(bit_read_range(9, 8).unwrap(), (8, 8, 0));
    }

    #[test]
    fn bit_read_range_boundary_cases() {
        // The spec doctest case, re-asserted here so `cargo test` alone
        // exercises it (doctests are a separate runner).
        assert_eq!(bit_read_range(17, 8).unwrap(), (16, 8, 0));
        // addr=1, count=1 → byte-aligned index 0, 8 bits, offset 0.
        assert_eq!(bit_read_range(1, 1).unwrap(), (0, 8, 0));
    }

    /// Regression guard for the overflow finding: high address + high count
    /// must return `InvalidRequest`, not panic in debug or wrap in release.
    #[test]
    fn bit_read_range_rejects_addr_plus_count_overflow() {
        let err = bit_read_range(u16::MAX, 16).expect_err("addr+count overflows u16");
        match err {
            Error::InvalidRequest(msg) => assert!(msg.contains("overflow"), "got: {msg}"),
            other => panic!("expected InvalidRequest, got {other:?}"),
        }
    }

    /// The window rounded up to a byte boundary must also be checked — a
    /// sum that fits in u16 but whose `div_ceil(8) * 8` doesn't still has
    /// to be rejected rather than silently wrapping.
    #[test]
    fn bit_read_range_rejects_window_overflow() {
        // addr=65529 → zero=65528. count=8 → sum=65536 already overflows.
        // Drop count by one to exercise the later `* 8` check: sum=65535,
        // div_ceil(8)=8192, 8192*8=65536 — fits in u32 but not u16.
        let err = bit_read_range(65529, 7).expect_err("window rounded up overflows u16");
        match err {
            Error::InvalidRequest(msg) => assert!(
                msg.contains("overflow") || msg.contains("exceeds"),
                "got: {msg}"
            ),
            other => panic!("expected InvalidRequest, got {other:?}"),
        }
    }
}
