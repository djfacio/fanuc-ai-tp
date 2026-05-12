//! Wire enums — every `#[repr(u8)]` / `#[repr(u16)]` discriminant that
//! appears at a fixed header offset.
//!
//! Doc-comment style note: protocol names ("INIT", "SHORT_ACK", etc.) are
//! written unquoted as wire-protocol terms of art, not Rust identifiers.
//! Clippy's `doc_markdown` lint is allowed at the module level to avoid
//! fighting over whether every mention wants backticks.
#![allow(clippy::doc_markdown)]
//!
//! Source attributions:
//! - `PacketType`, `MessageType`: packet-ge-srtp.lua:232-336 (BSD-3) +
//!   Palatis/Fanuc.RobotInterface/SRTP/PacketBase.cs (BSD-3).
//! - `ServiceRequestCode`: packet-ge-srtp.lua:93-112 (BSD-3) — the full
//!   FANUC-R553 opcode catalog.
//! - `SegmentSelector`: packet-ge-srtp.lua:137-158 (BSD-3) +
//!   Booozie-Z/Fanuc_GESRTP_Driver/srtp_message.py:83-91 (MIT).
//! - `Port`: Palatis/Fanuc.RobotInterface/RobotIF.cs:52-85 (BSD-3) +
//!   BiasedControls/snpx-client/snpx_client/globals.py:104-108 (study).
//!
//! No oracle code is copied verbatim; discriminant values are wire-protocol
//! facts, not authored expression.

use zerocopy::{Immutable, IntoBytes, TryFromBytes};

use crate::error::Error;

/// Outer packet classification — header bytes 0..2 (u16 LE). Spec §3.1.
///
/// `Unknown = 0x0008` is the port-60008 structured hello from Palatis's
/// `RobotIF.cs`; we accept it on decode but never emit it via the typed
/// request ADT (only via `Frame::fanuc_hello`).
#[derive(TryFromBytes, IntoBytes, Immutable, Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum PacketType {
    /// INIT — the 56-byte all-zero handshake packet.
    Init = 0x0000,
    /// INIT_ACK — controller response; byte 0 is `0x01` on success.
    InitAck = 0x0001,
    /// Request packet, SHORT or EXTENDED (discriminated by `MessageType`).
    Req = 0x0002,
    /// ACK for a `Req` frame.
    ReqAck = 0x0003,
    /// Port-60008 "structured hello" FANUC link-establishment packet.
    Unknown = 0x0008,
}

/// Inner message classification — header byte 31. Spec §3.1.
#[derive(TryFromBytes, IntoBytes, Immutable, Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum MessageType {
    /// SHORT request — the entire request fits in the 56-byte header.
    Short = 0xC0,
    /// SHORT_ACK — success or status-bearing ACK for a short request.
    ShortAck = 0xD4,
    /// SHORT_ERR — "Error Nack Mailbox" (Denton et al. 2017, p. S31).
    ShortErr = 0xD1,
    /// EXTENDED request — header + payload appended (`text_length > 0`).
    Extended = 0x80,
    /// EXTENDED_ACK — ACK whose read data lives after the 56-byte header.
    ExtendedAck = 0x94,
}

/// `ServiceRequestCode` — byte at offset 42 (SHORT) or 50 (EXTENDED).
///
/// Source: packet-ge-srtp.lua:93-112 (BSD-3). Confirmed by
/// Booozie-Z/Fanuc_GESRTP_Driver/srtp_message.py (MIT) for the subset it
/// exercises (`RETURN_DATETIME=0x25`, `RETURN_CONTROLLER_TYPE=0x43`).
#[derive(TryFromBytes, IntoBytes, Immutable, Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ServiceRequestCode {
    /// Short status of the PLC.
    PlcShortStatus = 0x00,
    /// Get the running program's name.
    GetProgName = 0x03,
    /// Read from system memory — `%R`, `%AI`, `%AQ`, `%I`, `%Q`.
    ReadSysMem = 0x04,
    /// Read from task memory.
    ReadTaskMem = 0x05,
    /// Read from program memory.
    ReadProgMem = 0x06,
    /// Write to system memory — `%R`, `%AI`, `%AQ`, `%I`, `%Q`.
    WriteSysMem = 0x07,
    /// Write to task memory.
    WriteTaskMem = 0x08,
    /// Write to program memory.
    WriteProgMem = 0x09,
    /// Programmer logon.
    ProgLogon = 0x20,
    /// Change privilege level.
    ChangePriv = 0x21,
    /// Set CPU ID.
    SetCpuId = 0x22,
    /// Set PLC run/stop state.
    SetPlcRun = 0x23,
    /// Set PLC wall-clock time.
    SetPlcTime = 0x24,
    /// Read PLC wall-clock time. Aliased as `RETURN_DATETIME` by Booozie.
    GetTime = 0x25,
    /// Read PLC fault table.
    GetFault = 0x38,
    /// Clear PLC fault table.
    ClrFault = 0x39,
    /// Store a program to the PLC.
    ProgStore = 0x3F,
    /// Load a program from the PLC.
    ProgLoad = 0x40,
    /// Read controller info. Aliased as `RETURN_CONTROLLER_TYPE` by Booozie.
    GetInfo = 0x43,
    /// Toggle force/unforce on a system-memory bit.
    ToggleForceSysMem = 0x44,
    /// **Hello-only.** Port-60008 FANUC link-establishment request byte
    /// at header offset 42. Appears exclusively in `Frame::fanuc_hello`;
    /// never observed in post-handshake traffic. Spec §3.8
    /// (`palatis:RobotIF.cs:67-85`).
    FanucHelloInit = 0x4F,
}

/// `SegmentSelector` — byte at offset 43 (SHORT) or 51 (EXTENDED).
///
/// Source: packet-ge-srtp.lua:137-158 (BSD-3) +
/// Booozie-Z/Fanuc_GESRTP_Driver/srtp_message.py:83-91 (MIT).
///
/// The selector determines both the **unit** of `target_index` (bit /
/// byte / word) and the unit of `target_count`. See spec §7 and the
/// [`crate::addr`] helpers.
#[derive(TryFromBytes, IntoBytes, Immutable, Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum SegmentSelector {
    /// Sentinel — used for service requests that don't address memory
    /// (`GetTime`, `GetInfo`, `PlcShortStatus`). The selector byte on the
    /// wire is `0x00` in those captures; we carry it as a named variant
    /// rather than overloading an address-bearing selector.
    None = 0x00,

    // -- Discrete bit selectors (1 bit per address, bit-level `target_index`).
    /// `%I` — discrete input bits. On FANUC R553: `DO[x]` ⇔ `%I`.
    BitI = 0x46,
    /// `%Q` — discrete output bits. On FANUC R553: `DI[x]` ⇔ `%Q`.
    BitQ = 0x48,
    /// `%M` — internal discrete memory.
    BitM = 0x4C,
    /// `%T` — temporary discrete memory.
    BitT = 0x4A,
    /// `%SA` — system status bit region A.
    BitSA = 0x4E,
    /// `%SB` — system status bit region B.
    BitSB = 0x50,
    /// `%SC` — system status bit region C.
    BitSC = 0x52,
    /// `%S` — system status bits.
    BitS = 0x54,
    /// `%G` — global bit data (bit-addressed view).
    BitG = 0x56,

    // -- Byte-addressed bit regions (1 byte = 8 bits, byte-level `target_index`).
    /// `%I` byte-addressed.
    ByteI = 0x10,
    /// `%Q` byte-addressed.
    ByteQ = 0x12,
    /// `%M` byte-addressed.
    ByteM = 0x16,
    /// `%T` byte-addressed.
    ByteT = 0x14,
    /// `%SA` byte-addressed.
    ByteSA = 0x18,
    /// `%SB` byte-addressed.
    ByteSB = 0x1A,
    /// `%SC` byte-addressed.
    ByteSC = 0x1C,
    /// `%S` byte-addressed.
    ByteS = 0x1E,
    /// `%G` byte-addressed — ASCII-over-%G command channel (Palatis).
    ByteG = 0x38,

    // -- Word-addressed regions (16-bit per address, word-level `target_index`).
    /// `%AI` — analog input words. On FANUC: `GI[x]` projection.
    WordAI = 0x0A,
    /// `%AQ` — analog output words. On FANUC: `GO[x]` projection.
    WordAQ = 0x0C,
    /// `%R` — numeric-register region. FANUC's `$SNPX_ASG` catch-all.
    WordR = 0x08,
    /// **Hello-only.** Port-60008 FANUC link-establishment selector byte
    /// at header offset 43. Appears exclusively in `Frame::fanuc_hello`;
    /// never observed in post-handshake traffic. Spec §3.8
    /// (`palatis:RobotIF.cs:67-85`).
    FanucHelloInit = 0x01,
}

/// TCP port kind — which SRTP endpoint the client is talking to. Spec §3.8.
///
/// This enum is **not** a wire type (it doesn't appear at a fixed header
/// offset). It's a client-side configuration flag that decides which
/// handshake `Client::connect` runs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum Port {
    /// GE-SRTP, IANA-registered. One-packet init: 56 zero bytes →
    /// INIT_ACK. Used by Booozie-Z and TheMadHatt3r.
    Srtp = 18245,
    /// FANUC SNP-X server. Two-packet init: 56 zero bytes → INIT_ACK,
    /// then a structured "link hello" (see spec §3.8). Used by Palatis,
    /// BiasedControls, UnderAutomation.
    FanucSnpx = 60008,
}

// ------------------------------------------------------------------
//  Discriminant-rejection helper.
//
//  zerocopy 0.8's `TryFromBytes` on a `#[repr(uN)]` enum validates that
//  the bit pattern names a known variant. We wrap it so callers get a
//  named `Error::UnknownDiscriminant` instead of an opaque
//  `zerocopy::ConvertError`.
// ------------------------------------------------------------------

/// Helper: try to decode a wire enum from its LE byte representation,
/// mapping any `TryFromBytes` failure to a named [`Error::UnknownDiscriminant`].
///
/// The `field` label shows up in error messages verbatim, so pass a
/// human-meaningful name (`"msg_type"`, `"pkt_type"`, etc.).
///
/// # Errors
///
/// Returns [`Error::UnknownDiscriminant`] if `bytes` doesn't name a
/// variant of `T`. Does not panic.
// Used by the unit tests below; will be the sole enum-decode entry point
// for `frame.rs` in phase 2. Silences the currently-unused warning while
// the frame module is still a stub.
#[allow(dead_code)]
pub(crate) fn try_enum<T>(bytes: &[u8], field: &'static str) -> Result<T, Error>
where
    T: TryFromBytes + IntoBytes + Immutable + Copy,
{
    T::try_read_from_bytes(bytes).map_err(|_| {
        // Lift the raw bytes into a u32 for uniform error reporting across
        // u8 and u16 wire enums.
        let value: u32 = match bytes.len() {
            1 => u32::from(bytes[0]),
            2 => u32::from(u16::from_le_bytes([bytes[0], bytes[1]])),
            _ => 0,
        };
        Error::UnknownDiscriminant { field, value }
    })
}

/// Fallible enum decode that falls back to `default` when `bytes`
/// doesn't name a variant. For response-path fields we don't
/// interpret downstream — `svc_req_code` and `seg_selector` in
/// `ExtendedAck` / `ShortAck` bodies — being strict on the
/// discriminant produces false-negative parse failures against
/// real controllers (e.g. ROBOGUIDE returns `svc_req_code = 0xff`
/// in `GetInfo` responses; pcap in
/// `crates/snpx-codec/tests/live/`).
#[allow(dead_code)]
pub(crate) fn try_enum_or<T>(bytes: &[u8], default: T) -> T
where
    T: TryFromBytes + IntoBytes + Immutable + Copy,
{
    T::try_read_from_bytes(bytes).unwrap_or(default)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packet_type_roundtrip_and_reject() {
        // Valid: 0x0001 LE → InitAck.
        let ok = try_enum::<PacketType>(&[0x01, 0x00], "pkt_type").unwrap();
        assert_eq!(ok, PacketType::InitAck);

        // Invalid: 0x00FF is not a variant.
        let err = try_enum::<PacketType>(&[0xFF, 0x00], "pkt_type").unwrap_err();
        match err {
            Error::UnknownDiscriminant { field, value } => {
                assert_eq!(field, "pkt_type");
                assert_eq!(value, 0x00FF);
            }
            other => panic!("unexpected error: {other:?}"),
        }
    }

    #[test]
    fn message_type_roundtrip_and_reject() {
        let ok = try_enum::<MessageType>(&[0xC0], "msg_type").unwrap();
        assert_eq!(ok, MessageType::Short);

        let err = try_enum::<MessageType>(&[0x7F], "msg_type").unwrap_err();
        assert!(matches!(
            err,
            Error::UnknownDiscriminant {
                field: "msg_type",
                value: 0x7F
            }
        ));
    }

    #[test]
    fn service_request_code_roundtrip_and_reject() {
        // Valid: 0x04 = ReadSysMem.
        let ok = try_enum::<ServiceRequestCode>(&[0x04], "svc_req_code").unwrap();
        assert_eq!(ok, ServiceRequestCode::ReadSysMem);

        // Invalid: 0x99 isn't in the 20-variant catalog (§3.6).
        let err = try_enum::<ServiceRequestCode>(&[0x99], "svc_req_code").unwrap_err();
        assert!(matches!(
            err,
            Error::UnknownDiscriminant {
                field: "svc_req_code",
                value: 0x99
            }
        ));
    }

    #[test]
    fn segment_selector_roundtrip_and_reject() {
        // Valid: 0x08 = WordR.
        let ok = try_enum::<SegmentSelector>(&[0x08], "seg_selector").unwrap();
        assert_eq!(ok, SegmentSelector::WordR);

        // Invalid: 0x77 is a gap between BitG=0x56 and the byte block.
        let err = try_enum::<SegmentSelector>(&[0x77], "seg_selector").unwrap_err();
        assert!(matches!(
            err,
            Error::UnknownDiscriminant {
                field: "seg_selector",
                value: 0x77
            }
        ));
    }

    #[test]
    fn fanuc_hello_only_variants_decode() {
        // Spec §3.8 — the port-60008 hello uses svc=0x4F, sel=0x01.
        let svc = try_enum::<ServiceRequestCode>(&[0x4F], "svc_req_code").unwrap();
        assert_eq!(svc, ServiceRequestCode::FanucHelloInit);

        let sel = try_enum::<SegmentSelector>(&[0x01], "seg_selector").unwrap();
        assert_eq!(sel, SegmentSelector::FanucHelloInit);
    }

    #[test]
    fn port_numeric_values() {
        // Port isn't a wire type, but the numeric values matter for
        // `TcpStream::connect((host, port as u16))`.
        assert_eq!(Port::Srtp as u16, 18245);
        assert_eq!(Port::FanucSnpx as u16, 60008);
    }
}
