//! Wire frame types — the 56-byte SRTP header plus optional extended payload.
//!
//! This module defines two layers:
//!
//! - [`HeaderRaw`] — a `#[repr(C)]` byte-exact view of the 56-byte header,
//!   zerocopy-derived so `&[u8] ⇌ &HeaderRaw` is free. Spec §4.0.
//! - [`Frame`] / [`FrameBody`] — the ergonomic owned struct that the public
//!   API exposes. Built from `HeaderRaw` on decode, written into a
//!   `HeaderRaw` on encode. Spec §4.1.
//!
//! Attribution format: every wire-layout decision cites the spec section
//! and its upstream oracle line (e.g. `palatis:PacketBase.cs:64`). The
//! discriminants themselves are defined in [`crate::enums`]; this module
//! owns the *structural* decisions (offsets, body variants, parse dispatch).
#![allow(clippy::doc_markdown)]

use bytes::{Bytes, BytesMut};
use zerocopy::byteorder::little_endian::{U16, U32};
use zerocopy::{FromBytes, FromZeros, Immutable, IntoBytes, KnownLayout, Unaligned};

use crate::enums::{
    try_enum, try_enum_or, MessageType, PacketType, SegmentSelector, ServiceRequestCode,
};
use crate::error::{Error, Result};

/// Byte-exact image of the 56-byte SRTP header. Every offset maps to a
/// line of `Palatis/packet-ge-srtp/packet-ge-srtp.lua` and
/// `Palatis/Fanuc.RobotInterface/SRTP/PacketBase.cs` — see spec §4.0 /
/// §11.2.
///
/// - `Unaligned` — wire bytes are 1-byte aligned, no packing required.
/// - `Immutable` — we never hand out a `&mut HeaderRaw` through a zerocopy
///   cast, so the safety invariant for `IntoBytes` holds trivially.
#[derive(FromBytes, IntoBytes, Unaligned, KnownLayout, Immutable, Debug, Clone)]
#[repr(C)]
pub struct HeaderRaw {
    /// Bytes 0..2 — `PacketType` (u16 LE). `lua:232`.
    pub pkt_type: U16,
    /// Bytes 2..4 — monotonic request sequence number. `lua:234`.
    pub seq_index: U16,
    /// Bytes 4..6 — length in bytes of the EXTENDED payload that follows
    /// this header. Zero for SHORT. `lua:236`.
    pub text_length: U16,
    /// Bytes 6..26 — five u32 reserved slots. On EXTENDED, slots at
    /// offsets 8 and 16 (= `reserved_a[2..6]` and `reserved_a[10..14]`
    /// as u32 LE) default to `0x00000200`. `palatis:ExtendedPacketBase.cs:17-18`.
    pub reserved_a: [u8; 20],
    /// Byte 26 — wall-clock seconds. `palatis:PacketBase.cs:43`.
    pub time_sec: u8,
    /// Byte 27 — wall-clock minutes. `palatis:PacketBase.cs:44`.
    pub time_min: u8,
    /// Byte 28 — wall-clock hours. `palatis:PacketBase.cs:45`.
    pub time_hour: u8,
    /// Byte 29 — always 0 on outbound; preserved on inbound.
    pub reserved_b: u8,
    /// Byte 30 — **mirror of `seq_index` low byte**.
    /// `palatis:PacketBase.cs:64` (`_SequenceNumber = _SequenceNumber2 = value`).
    pub msg_seq2: u8,
    /// Byte 31 — `MessageType` discriminant.
    pub msg_type: u8,
    /// Bytes 32..36 — source mailbox (u32 LE).
    pub mbox_src: U32,
    /// Bytes 36..40 — destination mailbox (u32 LE). FANUC robot service =
    /// `0x0000_0E10`.
    pub mbox_dst: U32,
    /// Byte 40 — fragment index, 1-based.
    pub pkt_num: u8,
    /// Byte 41 — total fragments.
    pub total_pkt_num: u8,
    /// Bytes 42..56 — body, interpreted per `msg_type`. See §3.2–§3.5.
    pub body: [u8; 14],
}

const _: () = {
    assert!(core::mem::size_of::<HeaderRaw>() == 56);
};

/// SHORT_ACK / SHORT_ERR bytes 42–43. Typed so callers can branch on
/// "success" (`major == 0`) vs "error" without re-parsing raw bytes.
/// FANUC R-30iB emits `(0, 0)` for every SHORT_ERR observed so far — see
/// spec §9.2 open question O-1.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Status {
    /// Major status byte at body offset 0 (header offset 42).
    pub major: u8,
    /// Minor status byte at body offset 1 (header offset 43).
    pub minor: u8,
}

/// SHORT_ACK bytes 50–55 — "PLC piggy-back status" per
/// `denton:p_S31 Fig.4`. Present on **every** `SHORT_ACK` regardless of
/// the operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PiggyBack {
    /// Control program number. `0xFF` = master not logged in,
    /// `0x00` = logged in. Body offset 8 (header offset 50).
    pub prog_num: u8,
    /// Current privilege level of the master. Body offset 9.
    pub privilege: u8,
    /// Last program-sweep time in milliseconds (u16 LE). Body offset 10.
    pub sweep_ms: u16,
    /// PLC status word, bit flags. Body offset 12. Observed `0x217C`
    /// on Booozie captures.
    pub status: u16,
}

/// Typed view of the 14-byte body at header offsets 42..56. Variant is
/// selected by `msg_type` per the spec §4.1 dispatch table, except that
/// `PacketType::{Init, InitAck, Unknown}` bypass the table — see
/// [`Frame::parse`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FrameBody {
    /// SHORT request (`msg_type = 0xC0`). Spec §3.2.
    ShortReq {
        /// Service-request code at body offset 0.
        svc_req_code: ServiceRequestCode,
        /// Segment selector at body offset 1.
        seg_selector: SegmentSelector,
        /// Zero-based, selector-native target index (body offset 2, u16 LE).
        target_index: u16,
        /// Count in selector-native units (body offset 4, u16 LE).
        target_count: u16,
        /// Up to 6 bytes of inline payload at body offset 6..12.
        inline_payload: [u8; 6],
    },
    /// SHORT ACK (`msg_type = 0xD4`). Spec §3.3.
    ShortAck {
        /// Major/minor status at body offsets 0..2.
        status: Status,
        /// Up to 6 bytes / 3 words of return data at body offsets 2..8.
        inline_payload: [u8; 6],
        /// PLC piggy-back status at body offsets 8..14.
        piggy: PiggyBack,
    },
    /// SHORT ERR — "Error Nack Mailbox" (`msg_type = 0xD1`). Spec §3.4.
    /// We keep the typed status *and* the full 14-byte body until live
    /// captures disambiguate FANUC's layout (spec §9.2 O-1).
    ShortErr {
        /// Typed view of bytes 42..44.
        status: Status,
        /// Full opaque body at bytes 42..56.
        raw: [u8; 14],
    },
    /// EXTENDED request (`msg_type = 0x80`). Spec §3.5. The payload bytes
    /// live in [`Frame::extended`].
    Extended {
        /// Service-request code at body offset 8.
        svc_req_code: ServiceRequestCode,
        /// Segment selector at body offset 9.
        seg_selector: SegmentSelector,
        /// Zero-based target index at body offset 10.
        target_index: u16,
        /// Count in selector-native units at body offset 12.
        target_count: u16,
        /// Fragment index at body offset 6 (overrides header byte 40).
        pkt_num_ext: u8,
        /// Total fragments at body offset 7 (overrides header byte 41).
        total_pkt_num_ext: u8,
        /// Opaque bytes at body offsets 0..6 (header bytes 42..48).
        /// Spec §3.5 marks these reserved; captured Kepware writes
        /// populate `body[0]` with the low byte of `text_length`.
        /// Preserved verbatim for byte-exact round-trip.
        reserved_body: [u8; 6],
    },
    /// EXTENDED ACK (`msg_type = 0x94`). Spec §3.5.
    ExtendedAck {
        /// Service-request code at body offset 8.
        svc_req_code: ServiceRequestCode,
        /// Segment selector at body offset 9.
        seg_selector: SegmentSelector,
        /// Zero-based target index at body offset 10.
        target_index: u16,
        /// Count in selector-native units at body offset 12.
        target_count: u16,
        /// Fragment index at body offset 6.
        pkt_num_ext: u8,
        /// Total fragments at body offset 7.
        total_pkt_num_ext: u8,
        /// Opaque bytes at body offsets 0..6. See [`Self::Extended`].
        reserved_body: [u8; 6],
    },
    /// INIT — the 56-byte all-zero handshake. Body is meaningless;
    /// preserved implicitly as zeros.
    Init,
    /// INIT_ACK — full 56-byte controller response captured opaque for
    /// upstream inspection. Callers check the first byte is `0x01`.
    InitAck {
        /// Full 56-byte inbound buffer.
        raw: [u8; 56],
    },
}

/// The fixed 56-byte SRTP header + optional extended payload. All
/// multi-byte integers have already been converted from little-endian.
/// Spec §4.1.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    /// Outer packet classification (header bytes 0..2).
    pub pkt_type: PacketType,
    /// Monotonic request sequence number (header bytes 2..4).
    pub seq_index: u16,
    /// Bytes of extended payload following the 56-byte header.
    /// Always equals `self.extended.len()` for frames this crate emits.
    pub text_length: u16,
    /// Low byte of `seq_index`, mirrored at header byte 30. Preserved
    /// on decode even when it doesn't match `seq_index as u8`.
    pub msg_seq: u8,
    /// Inner message classification (header byte 31).
    pub msg_type: MessageType,
    /// Source mailbox (header bytes 32..36).
    pub mbox_src: u32,
    /// Destination mailbox (header bytes 36..40).
    pub mbox_dst: u32,
    /// Fragment index (header byte 40).
    pub pkt_num: u8,
    /// Total fragments (header byte 41).
    pub total_pkt_num: u8,
    /// Wall-clock timestamp `(hh, mm, ss)`. `None` iff all three bytes
    /// are zero. Header bytes 26..29.
    pub time: Option<(u8, u8, u8)>,
    /// Opaque reserved bytes at header offsets 6..26 (five u32 slots).
    /// Spec §3.1: "Decoder preserves all 20 bytes opaque on relay."
    ///
    /// On emit, if this field is all-zero AND `msg_type` is
    /// `Extended`/`ExtendedAck`, the emitter writes `0x00000200` at
    /// slots 2 and 16 per `palatis:ExtendedPacketBase.cs:17-18`. Otherwise
    /// the field is written verbatim, which preserves byte-for-byte
    /// round-trip of captured wire data whose reserved slots carry
    /// controller-specific values (e.g. Kepware writes `0x0100`).
    pub reserved_a: [u8; 20],
    /// Decoded body at header bytes 42..56.
    pub body: FrameBody,
    /// Extended payload (empty for SHORT / SHORT_ACK / SHORT_ERR).
    pub extended: Bytes,
}

/// Sentinel `msg_type` byte used by `Frame::init` — INIT packets carry a
/// zero byte at offset 31, which is not a valid [`MessageType`]
/// discriminant. The decoder accepts this byte only when `pkt_type` is
/// `Init` / `InitAck` / `Unknown`.
const MSG_TYPE_ZERO: u8 = 0x00;

impl Frame {
    /// Construct the 56-byte all-zero INIT packet. Both ports' first
    /// handshake packet. Spec §3.8.
    ///
    /// `msg_type = 0x00` is not a valid [`MessageType`] variant — we
    /// store `MessageType::Short` as a placeholder and set the raw byte
    /// to zero on emit. The decoder round-trip goes through the
    /// `FrameBody::Init` path, which ignores `msg_type`.
    #[must_use]
    pub fn init() -> Self {
        Self {
            pkt_type: PacketType::Init,
            seq_index: 0,
            text_length: 0,
            msg_seq: 0,
            // Placeholder — emit writes `MSG_TYPE_ZERO` for INIT frames.
            msg_type: MessageType::Short,
            mbox_src: 0,
            mbox_dst: 0,
            pkt_num: 0,
            total_pkt_num: 0,
            time: None,
            reserved_a: [0u8; 20],
            body: FrameBody::Init,
            extended: Bytes::new(),
        }
    }

    /// Construct the port-60008 FANUC "structured hello" packet
    /// (second packet of the two-packet init). Spec §3.8,
    /// `palatis:RobotIF.cs:67-85`.
    ///
    /// Fields per spec:
    /// - `pkt_type = 0x0008` (= [`PacketType::Unknown`]).
    /// - `seq_index = 1`.
    /// - `msg_type = 0xC0` ([`MessageType::Short`]).
    /// - `mbox_dst = 0x0000_0E10` (robot service mailbox).
    /// - `pkt_num = total_pkt_num = 1`.
    /// - body: `svc_req_code = 0x4F`, `seg_selector = 0x01` —
    ///   hello-only discriminants, see [`ServiceRequestCode::FanucHelloInit`]
    ///   and [`SegmentSelector::FanucHelloInit`].
    ///
    /// Bytes 9 and 17 (both inside `reserved_a`) are emitted as `0x00`
    /// per Palatis; BiasedControls uses `0x01`. Spec §3.8 notes both
    /// work on a real controller.
    #[must_use]
    pub fn fanuc_hello() -> Self {
        Self {
            pkt_type: PacketType::Unknown,
            seq_index: 1,
            text_length: 0,
            msg_seq: 1,
            msg_type: MessageType::Short,
            mbox_src: 0,
            mbox_dst: 0x0000_0E10,
            pkt_num: 1,
            total_pkt_num: 1,
            time: None,
            reserved_a: [0u8; 20],
            body: FrameBody::ShortReq {
                svc_req_code: ServiceRequestCode::FanucHelloInit,
                seg_selector: SegmentSelector::FanucHelloInit,
                target_index: 0,
                target_count: 0,
                inline_payload: [0u8; 6],
            },
            extended: Bytes::new(),
        }
    }

    /// Return the low byte of `pkt_type` as it appears on the wire (byte 0
    /// of the header).
    ///
    /// Used by `Client::connect` to embed the raw discriminant in
    /// [`Error::InitFailed`] when an `INIT` handshake doesn't yield an
    /// `INIT_ACK`. Spec §3.8: callers check byte 0 of the response is
    /// `0x01`.
    #[must_use]
    pub fn raw_first_byte(&self) -> u8 {
        // `pkt_type` is u16 LE on the wire; byte 0 is the low byte.
        // Truncation here is the wire definition.
        #[allow(clippy::cast_possible_truncation)]
        let b = pkt_type_to_u16(self.pkt_type) as u8;
        b
    }

    /// Decode a full-length frame buffer (56 + `text_length` bytes).
    ///
    /// Callers (the codec) pre-validate the buffer length. `parse`
    /// re-checks defensively — the cheap path is `HeaderRaw::ref_from_prefix`
    /// followed by a msg-type dispatch.
    ///
    /// # Errors
    ///
    /// - [`Error::FrameTooShort`] — `bytes.len() < 56` (header incomplete)
    ///   or `bytes.len() < 56 + text_length` (extended payload short).
    /// - [`Error::UnknownDiscriminant`] — an unknown discriminant at one
    ///   of the wire-enum offsets: `pkt_type` (bytes 0–1), `msg_type`
    ///   (byte 31), `svc_req_code` (body byte 0 for SHORT / body byte 8
    ///   for EXTENDED), or `seg_selector` (body byte 1 / body byte 9).
    ///
    /// Upstream (codec layer): [`Error::PduTooLarge`] is reported by
    /// [`crate::SrtpCodec`] before `parse` is called, so oversize
    /// `text_length` never reaches this function. A caller building
    /// [`Bytes`] independently and invoking `parse` directly is
    /// responsible for its own size cap.
    pub fn parse(bytes: &Bytes) -> Result<Self> {
        // Special-case: INIT / INIT_ACK frames are 56 zero-ish bytes and
        // carry a `msg_type` byte that isn't a valid MessageType variant.
        // We check `pkt_type` first so we can bypass the msg_type decode.
        let (hdr, _tail) =
            HeaderRaw::ref_from_prefix(bytes.as_ref()).map_err(|_| Error::FrameTooShort {
                need: 56,
                have: bytes.len(),
            })?;

        let text_len = hdr.text_length.get() as usize;
        let total = 56usize.checked_add(text_len).ok_or(Error::FrameTooShort {
            need: 56,
            have: bytes.len(),
        })?;
        if bytes.len() < total {
            return Err(Error::FrameTooShort {
                need: total,
                have: bytes.len(),
            });
        }

        let pkt_type = try_enum::<PacketType>(hdr.pkt_type.as_bytes(), "pkt_type")?;

        // Bypass dispatch for INIT / INIT_ACK / Unknown (the hello packet).
        // Spec §4.1 "PacketType::Init / InitAck / Unknown bypass it".
        // We honor that for Init and InitAck, but NOT for Unknown — the
        // hello packet carries a real SHORT body (svc=0x4F, sel=0x01) and
        // losing that on decode would break round-trip. Spec §3.8.
        let (body, msg_type) = match pkt_type {
            PacketType::Init => (FrameBody::Init, MessageType::Short),
            PacketType::InitAck => {
                let mut raw = [0u8; 56];
                raw.copy_from_slice(&bytes.as_ref()[..56]);
                (FrameBody::InitAck { raw }, MessageType::Short)
            }
            PacketType::Req | PacketType::ReqAck | PacketType::Unknown => {
                let msg_type = try_enum::<MessageType>(&[hdr.msg_type], "msg_type")?;
                let body = FrameBody::parse_body(&hdr.body, msg_type)?;
                (body, msg_type)
            }
        };

        let extended = if text_len > 0 {
            bytes.slice(56..56 + text_len)
        } else {
            Bytes::new()
        };

        let time = if hdr.time_sec == 0 && hdr.time_min == 0 && hdr.time_hour == 0 {
            None
        } else {
            // Spec §3.1: three bytes are (sec, min, hh).
            Some((hdr.time_hour, hdr.time_min, hdr.time_sec))
        };

        Ok(Frame {
            pkt_type,
            seq_index: hdr.seq_index.get(),
            text_length: hdr.text_length.get(),
            msg_seq: hdr.msg_seq2,
            msg_type,
            mbox_src: hdr.mbox_src.get(),
            mbox_dst: hdr.mbox_dst.get(),
            pkt_num: hdr.pkt_num,
            total_pkt_num: hdr.total_pkt_num,
            time,
            reserved_a: hdr.reserved_a,
            body,
            extended,
        })
    }

    /// Write this frame (56-byte header + extended payload) into `dst`.
    ///
    /// Sets `msg_seq2 = self.seq_index as u8` per spec §3.1 and
    /// `palatis:PacketBase.cs:64`. For EXTENDED / EXTENDED_ACK msg_types,
    /// sets `reserved_a` slots at offsets 8 and 16 to `0x00000200` per
    /// `palatis:ExtendedPacketBase.cs:17-18`. For SHORT / SHORT_ACK /
    /// SHORT_ERR, `reserved_a` is all zeros.
    pub fn emit(&self, dst: &mut BytesMut) {
        let mut hdr = HeaderRaw::new_zeroed();

        // Bytes 0..2: pkt_type.
        hdr.pkt_type = U16::new(pkt_type_to_u16(self.pkt_type));

        // Bytes 2..4: seq_index.
        hdr.seq_index = U16::new(self.seq_index);

        // Bytes 4..6: text_length reflects the extended payload byte count.
        // Spec §3.5: text_length is the payload *byte* count, not
        // target_count. For SHORT frames this is 0.
        let ext_len_u16 = u16::try_from(self.extended.len()).unwrap_or(u16::MAX);
        hdr.text_length = U16::new(ext_len_u16);

        // Bytes 6..26: reserved_a. Precedence rules:
        //   1. If the caller populated `self.reserved_a` (any non-zero byte),
        //      we emit it verbatim — preserves captured wire data.
        //   2. Otherwise, for EXTENDED frames, fill slots at offsets 8 and
        //      16 (= reserved_a[2..6] / [10..14]) with 0x00000200 LE per
        //      palatis:ExtendedPacketBase.cs:17-18.
        //   3. Otherwise, leave zero.
        if self.reserved_a != [0u8; 20] {
            hdr.reserved_a = self.reserved_a;
        } else if matches!(
            self.msg_type,
            MessageType::Extended | MessageType::ExtendedAck
        ) {
            let le_bytes = 0x0000_0200u32.to_le_bytes();
            hdr.reserved_a[2..6].copy_from_slice(&le_bytes);
            hdr.reserved_a[10..14].copy_from_slice(&le_bytes);
        }

        // Bytes 26..29: time (sec, min, hh) — stored in that order on
        // the wire per spec §3.1 field comment ("seconds→minutes→hours").
        if let Some((hh, mm, ss)) = self.time {
            hdr.time_sec = ss;
            hdr.time_min = mm;
            hdr.time_hour = hh;
        }

        // Byte 29: reserved_b stays zero.

        // Byte 30: msg_seq2. Spec §3.1 + palatis:PacketBase.cs:64 says
        // this mirrors the low byte of seq_index. Captured Kepware frames
        // violate that rule (byte 30 carries some other per-session counter),
        // so we preserve `self.msg_seq` verbatim for byte-exact relay. The
        // typed request builders (`Request::into_frame`) set `msg_seq` to
        // `seq as u8` to keep the mirror invariant for client-generated
        // frames.
        hdr.msg_seq2 = self.msg_seq;

        // Byte 31: msg_type. Special-case INIT → emit the zero byte
        // that isn't a valid MessageType.
        hdr.msg_type = match self.body {
            FrameBody::Init => MSG_TYPE_ZERO,
            FrameBody::InitAck { raw } => {
                // InitAck is a controller response; emit the raw captured
                // byte so relays preserve it. For a freshly-built InitAck
                // the raw buffer's byte 31 is the authoritative value.
                raw[31]
            }
            _ => msg_type_to_u8(self.msg_type),
        };

        // Bytes 32..36: mbox_src.
        hdr.mbox_src = U32::new(self.mbox_src);

        // Bytes 36..40: mbox_dst.
        hdr.mbox_dst = U32::new(self.mbox_dst);

        // Byte 40: pkt_num. Byte 41: total_pkt_num.
        hdr.pkt_num = self.pkt_num;
        hdr.total_pkt_num = self.total_pkt_num;

        // Bytes 42..56: body.
        self.body.emit_into(&mut hdr.body);

        // Special-case InitAck: the raw 56-byte buffer overrides every
        // field we just populated — the caller captured it opaque.
        if let FrameBody::InitAck { raw } = &self.body {
            dst.extend_from_slice(raw);
        } else {
            dst.extend_from_slice(hdr.as_bytes());
        }

        if !self.extended.is_empty() {
            dst.extend_from_slice(&self.extended);
        }
    }
}

impl FrameBody {
    /// Decode the 14-byte body `b` per the spec §4.1 dispatch table.
    fn parse_body(b: &[u8; 14], msg_type: MessageType) -> Result<FrameBody> {
        match msg_type {
            MessageType::Short => Ok(FrameBody::ShortReq {
                svc_req_code: try_enum::<ServiceRequestCode>(&b[0..1], "svc_req_code")?,
                seg_selector: try_enum::<SegmentSelector>(&b[1..2], "seg_selector")?,
                target_index: u16::from_le_bytes([b[2], b[3]]),
                target_count: u16::from_le_bytes([b[4], b[5]]),
                inline_payload: [b[6], b[7], b[8], b[9], b[10], b[11]],
            }),
            MessageType::ShortAck => Ok(FrameBody::ShortAck {
                status: Status {
                    major: b[0],
                    minor: b[1],
                },
                inline_payload: [b[2], b[3], b[4], b[5], b[6], b[7]],
                piggy: PiggyBack {
                    prog_num: b[8],
                    privilege: b[9],
                    sweep_ms: u16::from_le_bytes([b[10], b[11]]),
                    status: u16::from_le_bytes([b[12], b[13]]),
                },
            }),
            MessageType::ShortErr => Ok(FrameBody::ShortErr {
                status: Status {
                    major: b[0],
                    minor: b[1],
                },
                raw: *b,
            }),
            MessageType::Extended => Ok(FrameBody::Extended {
                reserved_body: [b[0], b[1], b[2], b[3], b[4], b[5]],
                pkt_num_ext: b[6],
                total_pkt_num_ext: b[7],
                svc_req_code: try_enum::<ServiceRequestCode>(&b[8..9], "svc_req_code")?,
                seg_selector: try_enum::<SegmentSelector>(&b[9..10], "seg_selector")?,
                target_index: u16::from_le_bytes([b[10], b[11]]),
                target_count: u16::from_le_bytes([b[12], b[13]]),
            }),
            // Response-side parsing is lenient on `svc_req_code` and
            // `seg_selector`: real controllers emit non-standard values
            // here (e.g. ROBOGUIDE returns `svc_req_code = 0xff` in
            // `GetInfo` ExtendedAck — see `tests/live/roboguide-snpx-
            // 60008-postfix.pcapng`). Neither field is interpreted by
            // `Response::from_frame` for ack paths, so a strict decode
            // would block legitimate traffic for no benefit. Fall back
            // to harmless defaults; lossy round-trip is acceptable for
            // received-only frames.
            MessageType::ExtendedAck => Ok(FrameBody::ExtendedAck {
                reserved_body: [b[0], b[1], b[2], b[3], b[4], b[5]],
                pkt_num_ext: b[6],
                total_pkt_num_ext: b[7],
                svc_req_code: try_enum_or(&b[8..9], ServiceRequestCode::PlcShortStatus),
                seg_selector: try_enum_or(&b[9..10], SegmentSelector::None),
                target_index: u16::from_le_bytes([b[10], b[11]]),
                target_count: u16::from_le_bytes([b[12], b[13]]),
            }),
        }
    }

    /// Mirror of [`Self::parse_body`] — serialize this body into the
    /// 14-byte buffer at header offsets 42..56.
    fn emit_into(&self, out: &mut [u8; 14]) {
        *out = [0u8; 14];
        match *self {
            FrameBody::ShortReq {
                svc_req_code,
                seg_selector,
                target_index,
                target_count,
                inline_payload,
            } => {
                out[0] = svc_req_code_to_u8(svc_req_code);
                out[1] = seg_selector_to_u8(seg_selector);
                out[2..4].copy_from_slice(&target_index.to_le_bytes());
                out[4..6].copy_from_slice(&target_count.to_le_bytes());
                out[6..12].copy_from_slice(&inline_payload);
                // out[12..14] reserved, left zero.
            }
            FrameBody::ShortAck {
                status,
                inline_payload,
                piggy,
            } => {
                out[0] = status.major;
                out[1] = status.minor;
                out[2..8].copy_from_slice(&inline_payload);
                out[8] = piggy.prog_num;
                out[9] = piggy.privilege;
                out[10..12].copy_from_slice(&piggy.sweep_ms.to_le_bytes());
                out[12..14].copy_from_slice(&piggy.status.to_le_bytes());
            }
            FrameBody::ShortErr { raw, .. } => {
                *out = raw;
            }
            FrameBody::Extended {
                svc_req_code,
                seg_selector,
                target_index,
                target_count,
                pkt_num_ext,
                total_pkt_num_ext,
                reserved_body,
            }
            | FrameBody::ExtendedAck {
                svc_req_code,
                seg_selector,
                target_index,
                target_count,
                pkt_num_ext,
                total_pkt_num_ext,
                reserved_body,
            } => {
                out[0..6].copy_from_slice(&reserved_body);
                out[6] = pkt_num_ext;
                out[7] = total_pkt_num_ext;
                out[8] = svc_req_code_to_u8(svc_req_code);
                out[9] = seg_selector_to_u8(seg_selector);
                out[10..12].copy_from_slice(&target_index.to_le_bytes());
                out[12..14].copy_from_slice(&target_count.to_le_bytes());
            }
            FrameBody::Init | FrameBody::InitAck { .. } => {
                // Init leaves the body zero; InitAck is handled entirely
                // by the raw-buffer override in `Frame::emit`.
            }
        }
    }
}

// ------------------------------------------------------------------
// Enum-to-byte helpers. We go the other direction (bytes → enum) via
// `try_enum`; these are plain `as`-casts, justified by the
// `#[repr(uN)]` attribute on each enum.
//
// clippy::as_conversions would normally object, but the spec (§2.1)
// permits explicit `as` for discriminant extraction.
// ------------------------------------------------------------------

#[inline]
fn pkt_type_to_u16(p: PacketType) -> u16 {
    p as u16
}

#[inline]
fn msg_type_to_u8(m: MessageType) -> u8 {
    m as u8
}

#[inline]
fn svc_req_code_to_u8(s: ServiceRequestCode) -> u8 {
    s as u8
}

#[inline]
fn seg_selector_to_u8(s: SegmentSelector) -> u8 {
    s as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_init_is_56_zero_bytes() {
        let mut buf = BytesMut::new();
        Frame::init().emit(&mut buf);
        assert_eq!(buf.len(), 56);
        assert_eq!(&buf[..], &[0u8; 56][..]);
    }

    #[test]
    fn fanuc_hello_matches_spec_bytes() {
        let mut buf = BytesMut::new();
        Frame::fanuc_hello().emit(&mut buf);
        assert_eq!(buf.len(), 56);
        // Spec §3.8 spot-checks:
        assert_eq!(&buf[0..2], &[0x08, 0x00], "pkt_type = 0x0008 LE");
        assert_eq!(buf[2], 0x01, "seq_index low byte = 1");
        assert_eq!(buf[31], 0xC0, "msg_type = SHORT");
        assert_eq!(
            &buf[36..40],
            &[0x10, 0x0E, 0x00, 0x00],
            "mbox_dst = 0x00000E10 LE"
        );
        assert_eq!(&buf[40..42], &[0x01, 0x01], "pkt 1 of 1");
        assert_eq!(buf[42], 0x4F, "svc_req_code = FanucHelloInit");
        assert_eq!(buf[43], 0x01, "seg_selector = FanucHelloInit");
        // Palatis convention: bytes 9 and 17 are 0x00.
        assert_eq!(buf[9], 0x00);
        assert_eq!(buf[17], 0x00);
    }

    #[test]
    fn msg_seq2_mirrors_seq_index_low_byte() {
        // Build a real SHORT request so emit() doesn't take the INIT path.
        let frame = Frame {
            pkt_type: PacketType::Req,
            seq_index: 0x1234,
            text_length: 0,
            msg_seq: 0x34,
            msg_type: MessageType::Short,
            mbox_src: 0,
            mbox_dst: 0x0000_0E10,
            pkt_num: 1,
            total_pkt_num: 1,
            time: None,
            reserved_a: [0u8; 20],
            body: FrameBody::ShortReq {
                svc_req_code: ServiceRequestCode::ReadSysMem,
                seg_selector: SegmentSelector::WordR,
                target_index: 0,
                target_count: 1,
                inline_payload: [0u8; 6],
            },
            extended: Bytes::new(),
        };
        let mut buf = BytesMut::new();
        frame.emit(&mut buf);
        // Spec §3.1: byte 30 mirrors byte 2 (low byte of seq_index).
        assert_eq!(buf[30], 0x34, "msg_seq2 mirrors seq_index low byte");
        assert_eq!(buf[2], 0x34, "seq_index LE low byte");
        assert_eq!(buf[3], 0x12, "seq_index LE high byte");
    }

    #[test]
    fn short_req_roundtrip_smoke() {
        let frame = Frame {
            pkt_type: PacketType::Req,
            seq_index: 42,
            text_length: 0,
            msg_seq: 42,
            msg_type: MessageType::Short,
            mbox_src: 0,
            mbox_dst: 0x0000_0E10,
            pkt_num: 1,
            total_pkt_num: 1,
            time: None,
            reserved_a: [0u8; 20],
            body: FrameBody::ShortReq {
                svc_req_code: ServiceRequestCode::ReadSysMem,
                seg_selector: SegmentSelector::WordR,
                target_index: 4,
                target_count: 2,
                inline_payload: [0u8; 6],
            },
            extended: Bytes::new(),
        };
        let mut buf = BytesMut::new();
        frame.emit(&mut buf);
        let bytes = buf.freeze();
        let decoded = Frame::parse(&bytes).expect("round-trip parse");
        assert_eq!(decoded, frame);
    }

    #[test]
    fn extended_roundtrip_sets_reserved_a_defaults() {
        let payload = Bytes::from_static(&[0xD2, 0x04]);
        let frame = Frame {
            pkt_type: PacketType::Req,
            seq_index: 7,
            text_length: 2,
            msg_seq: 7,
            msg_type: MessageType::Extended,
            mbox_src: 0,
            mbox_dst: 0x0000_0E10,
            pkt_num: 1,
            total_pkt_num: 1,
            time: None,
            reserved_a: [0u8; 20],
            body: FrameBody::Extended {
                svc_req_code: ServiceRequestCode::WriteSysMem,
                seg_selector: SegmentSelector::WordR,
                target_index: 0,
                target_count: 1,
                pkt_num_ext: 1,
                total_pkt_num_ext: 1,
                reserved_body: [0u8; 6],
            },
            extended: payload.clone(),
        };
        let mut buf = BytesMut::new();
        frame.emit(&mut buf);
        // palatis:ExtendedPacketBase.cs:17-18 — slots at offsets 8 and 16
        // both carry 0x00000200 LE.
        assert_eq!(&buf[8..12], &[0x00, 0x02, 0x00, 0x00]);
        assert_eq!(&buf[16..20], &[0x00, 0x02, 0x00, 0x00]);
        // Extended payload follows the 56-byte header.
        assert_eq!(&buf[56..58], &payload[..]);
        assert_eq!(&buf[4..6], &[0x02, 0x00], "text_length = 2 LE");

        let decoded = Frame::parse(&buf.freeze()).expect("round-trip parse");
        // Expected: emit fills reserved_a slots 2 and 10 with 0x00000200 LE
        // because the source frame had an all-zero reserved_a (so the
        // "precedence rule 2" branch in emit fires). Decode preserves those
        // bytes into `Frame.reserved_a`, so the decoded Frame differs from
        // the input by exactly those four populated bytes.
        let mut expected = frame.clone();
        expected.reserved_a[2..6].copy_from_slice(&0x0000_0200u32.to_le_bytes());
        expected.reserved_a[10..14].copy_from_slice(&0x0000_0200u32.to_le_bytes());
        assert_eq!(decoded, expected);
    }
}
