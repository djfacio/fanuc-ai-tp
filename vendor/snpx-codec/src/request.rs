//! Typed request ADT — the caller-facing layer above raw frames. Spec §4.3.
//!
//! `Request` is intentionally narrow: only the six FANUC-reachable selectors
//! (`%R`, `%AI`, `%AQ`, `%I`, `%Q`) plus `GetTime` / `GetInfo` are exposed.
//! Every other `SegmentSelector` stays in the internal wire enum for decode
//! correctness but is unreachable from this ADT.
//!
//! Hello-only discriminants (`ServiceRequestCode::FanucHelloInit`,
//! `SegmentSelector::FanucHelloInit`) are deliberately omitted from the
//! public surface — they live in `Frame::fanuc_hello` only.
#![allow(clippy::doc_markdown)]

use bytes::Bytes;

use crate::addr;
use crate::addr::FanucAddr;
use crate::enums::{SegmentSelector, ServiceRequestCode};
use crate::error::{Error, Result};
use crate::frame::{Frame, FrameBody};
use crate::{MessageType, PacketType};

/// Word-addressed memory region (16 bits per address).
///
/// Only the three FANUC-reachable word selectors are exposed. Mapping to
/// the wire `SegmentSelector` is in [`WordSelector::selector`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WordSelector {
    /// `%R` — numeric-register region. FANUC's `$SNPX_ASG` catch-all.
    R,
    /// `%AI` — analog-input words. FANUC `GI[x]` projection.
    AI,
    /// `%AQ` — analog-output words. FANUC `GO[x]` projection.
    AQ,
}

impl WordSelector {
    /// Map to the wire-level [`SegmentSelector`]. Spec §3.7:
    /// `R → 0x08`, `AI → 0x0A`, `AQ → 0x0C`.
    #[must_use]
    pub fn selector(self) -> SegmentSelector {
        match self {
            WordSelector::R => SegmentSelector::WordR, // spec §3.7: 0x08
            WordSelector::AI => SegmentSelector::WordAI, // spec §3.7: 0x0A
            WordSelector::AQ => SegmentSelector::WordAQ, // spec §3.7: 0x0C
        }
    }
}

/// Bit-addressed memory region (1 bit per address).
///
/// Only the two FANUC-reachable bit selectors are exposed. Mapping to the
/// wire `SegmentSelector` is in [`BitSelector::selector`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BitSelector {
    /// `%I` — discrete-input bits. On FANUC R553: `DO[x]` ⇔ `%I`.
    I,
    /// `%Q` — discrete-output bits. On FANUC R553: `DI[x]` ⇔ `%Q`.
    Q,
}

impl BitSelector {
    /// Map to the wire-level [`SegmentSelector`]. Spec §3.7:
    /// `I → 0x46`, `Q → 0x48`.
    #[must_use]
    pub fn selector(self) -> SegmentSelector {
        match self {
            BitSelector::I => SegmentSelector::BitI, // spec §3.7: 0x46
            BitSelector::Q => SegmentSelector::BitQ, // spec §3.7: 0x48
        }
    }
}

/// Byte-addressed memory region (1 byte per address).
///
/// Only `%G` is exposed today — it's the FANUC command channel used
/// for the `CLRASG` / `SETASG` / `CLRALM` ASCII-payload commands that
/// drive §5.11 link-up address-space negotiation. `%M`, `%T`, `%S*`
/// are wire-addressable but have no FANUC caller on our roadmap.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ByteSelector {
    /// `%G` — command channel. Writes of ASCII command strings
    /// (`"CLRASG"`, `"SETASG R...,1,1,REAL,..."`, etc.) per
    /// `snpx-findings.md §A.3` and MARUCHMID06121E §12.3.
    G,
}

impl ByteSelector {
    /// Map to the wire-level [`SegmentSelector`]. Spec §3.7:
    /// `G → 0x38`.
    #[must_use]
    pub fn selector(self) -> SegmentSelector {
        match self {
            ByteSelector::G => SegmentSelector::ByteG, // spec §3.7: 0x38
        }
    }
}

/// Caller-facing request ADT. Spec §4.3.
///
/// Every non-init variant converts to a [`Frame`] via
/// [`Request::into_frame`], which allocates a sequence number and fills in
/// the mailbox fields. `Init` is a sentinel that delegates to
/// [`Frame::init`] — the codec takes it as a signal, not as an ordinary
/// service request.
///
/// # Address convention
///
/// Every `addr` field below is the **1-based FANUC operator-visible
/// address** — the number an operator types on the teach pendant
/// (`R[10]`, `DO[184]`, `GI[3]`, etc.) wrapped in a [`FanucAddr`]
/// newtype so `u16::try_from(user_input)` can't accidentally flow
/// into the codec as a 0-based wire index. The codec converts to
/// the 0-based wire `target_index` via [`addr::word_target`] /
/// [`addr::bit_read_range`] / [`addr::bit_write`].
///
/// Construct with [`FanucAddr::from_raw`] when the bound is
/// implicit (e.g. the `$SNPX_ASG` slot plan already enforces it) or
/// [`FanucAddr::new_bounded`] at the trust boundary where user
/// input first enters the system.
#[derive(Debug, Clone)]
pub enum Request {
    /// 56-byte all-zero handshake. Ignores `seq`/`src_mbox`/`dst_mbox`.
    Init,
    /// Read `count` words from `%R` / `%AI` / `%AQ` starting at `addr`
    /// (1-based). Emitted as a SHORT request (spec §3.2) regardless of
    /// `count` — reads never carry a payload, so the 6-byte SHORT inline
    /// area is always sufficient.
    ReadSysWords {
        /// Word-addressed region.
        selector: WordSelector,
        /// 1-based FANUC address.
        addr: FanucAddr,
        /// Number of 16-bit words to read.
        count: u16,
    },
    /// Write `words` (byte buffer, little-endian word order) to
    /// `%R` / `%AI` / `%AQ` starting at `addr` (1-based). Emitted as an
    /// EXTENDED request (spec §3.5) **even for ≤6 bytes**. Palatis's code
    /// switches to SHORT for small writes (`palatis:RobotIF.cs:263,320,375,427`);
    /// we take the simpler rule — always EXTENDED — because it keeps
    /// `target_count` consistently selector-native and avoids duplicating
    /// the body-layout decision across two code paths. Marginally less
    /// efficient for 1–3-word writes; worth the simplicity.
    WriteSysWords {
        /// Word-addressed region.
        selector: WordSelector,
        /// 1-based FANUC address.
        addr: FanucAddr,
        /// Raw bytes to write. `words.len()` must be even (whole words);
        /// odd lengths return `Error::InvalidRequest`.
        words: Bytes,
    },
    /// Read `count` bits from `%I` / `%Q` starting at `addr` (1-based).
    /// Uses [`addr::bit_read_range`] — the returned bytes are
    /// byte-aligned; caller masks per spec §7 "Caller masks the returned
    /// byte(s)".
    ReadSysBits {
        /// Bit-addressed region.
        selector: BitSelector,
        /// 1-based FANUC address.
        addr: FanucAddr,
        /// Number of bits to read.
        count: u16,
    },
    /// Write a single bit in `%I` / `%Q` at `addr` (1-based) to `value`.
    /// Emitted as an EXTENDED request (spec §3.5) carrying a 1-byte
    /// payload with the target bit set per [`addr::bit_write`].
    WriteSysBit {
        /// Bit-addressed region.
        selector: BitSelector,
        /// 1-based FANUC address.
        addr: FanucAddr,
        /// New bit value.
        value: bool,
    },
    /// Read controller wall-clock time. Emitted as a SHORT request with
    /// `svc_req_code = 0x25`, `seg_selector = 0x00`.
    GetTime,
    /// Read controller info / type. Emitted as a SHORT request with
    /// `svc_req_code = 0x43`, `seg_selector = 0x00`.
    GetInfo,
    /// Write `bytes` to a byte-addressed region (`%G` today) starting
    /// at `addr` (1-based). Emitted as an EXTENDED request with
    /// `target_count` = byte count. The canonical FANUC use is
    /// writing the ASCII command strings `"CLRASG"`, `"SETASG ..."`,
    /// `"CLRALM"` to `%G` during §5.11 link-up.
    WriteSysBytes {
        /// Byte-addressed region.
        selector: ByteSelector,
        /// 1-based FANUC address (`%G[1]` is addr = 1).
        addr: FanucAddr,
        /// Raw bytes to write.
        bytes: Bytes,
    },
}

impl Request {
    /// Return the wire-level [`ServiceRequestCode`] this request will emit.
    ///
    /// The value is recorded in Phase 4's tracing spans (`svc` field on
    /// `Client::request`) so operators can correlate log lines with the
    /// FANUC opcode.
    #[must_use]
    pub fn service_code(&self) -> ServiceRequestCode {
        match self {
            // `Init` has no service-request code on the wire (the INIT
            // frame is all zeros). `PlcShortStatus = 0x00` is the closest
            // label for "no service request"; tracing sees it and callers
            // never confuse it with the actual all-zero INIT packet.
            Request::Init => ServiceRequestCode::PlcShortStatus,
            Request::ReadSysWords { .. } | Request::ReadSysBits { .. } => {
                ServiceRequestCode::ReadSysMem
            }
            Request::WriteSysWords { .. }
            | Request::WriteSysBit { .. }
            | Request::WriteSysBytes { .. } => ServiceRequestCode::WriteSysMem,
            Request::GetTime => ServiceRequestCode::GetTime,
            Request::GetInfo => ServiceRequestCode::GetInfo,
        }
    }

    /// Build the outbound [`Frame`] for this request.
    ///
    /// `seq` is the client-allocated sequence number; `src_mbox` and
    /// `dst_mbox` are the mailbox fields (typically `0x0000_0000` and
    /// `0x0000_0E10`). For `Request::Init`, all three arguments are
    /// ignored — the 56-byte all-zero handshake has fixed contents.
    ///
    /// # Errors
    ///
    /// - [`Error::InvalidRequest`] if `WriteSysWords::words` has an odd
    ///   byte length (words are 16-bit; odd lengths are malformed).
    #[allow(clippy::too_many_lines)] // one match arm per Request variant; splitting adds
                                     // indirection without improving clarity.
    pub fn into_frame(self, seq: u16, src_mbox: u32, dst_mbox: u32) -> Result<Frame> {
        match self {
            Request::Init => Ok(Frame::init()),

            Request::ReadSysWords {
                selector,
                addr,
                count,
            } => Ok(short_req(
                seq,
                src_mbox,
                dst_mbox,
                ServiceRequestCode::ReadSysMem,
                selector.selector(),
                addr::word_target(addr.get()),
                count,
            )),

            Request::WriteSysWords {
                selector,
                addr,
                words,
            } => {
                let addr_u16 = addr.get();
                if words.len() % 2 != 0 {
                    return Err(Error::InvalidRequest(
                        "WriteSysWords.words length must be even (whole 16-bit words)",
                    ));
                }
                // Wire cap: `text_length` (u16 LE at bytes 4..6) and the
                // codec's `MAX_TEXT_LENGTH` both bound this. Rejecting
                // here — in the public Request layer — prevents the
                // silent `unwrap_or(u16::MAX)` truncation that would
                // otherwise happen inside `Frame::emit` for payloads
                // larger than 64 KiB.
                if words.len() > crate::codec::MAX_TEXT_LENGTH as usize {
                    return Err(Error::InvalidRequest(
                        "WriteSysWords.words exceeds codec MAX_TEXT_LENGTH (4096 bytes)",
                    ));
                }
                // `target_count` is selector-native: word count for
                // WORD_* selectors. Spec §3.5 units table. `words.len()`
                // is byte length, which feeds `text_length` independently.
                let word_count = u16::try_from(words.len() / 2).map_err(|_| {
                    Error::InvalidRequest("WriteSysWords.words too long for u16 target_count")
                })?;
                Ok(extended_req(
                    seq,
                    src_mbox,
                    dst_mbox,
                    ServiceRequestCode::WriteSysMem,
                    selector.selector(),
                    addr::word_target(addr_u16),
                    word_count,
                    words,
                ))
            }

            Request::ReadSysBits {
                selector,
                addr,
                count,
            } => {
                // `bit_read_range` returns (first_bit_idx, bits_to_read,
                // offset). We send the first two; `offset` is the caller's
                // concern per spec §7. See response.rs doc. The `?` surfaces
                // `addr + count` overflow as `InvalidRequest` instead of
                // panicking in debug / wrapping in release.
                let (first, bits, _offset) = addr::bit_read_range(addr.get(), count)?;
                Ok(short_req(
                    seq,
                    src_mbox,
                    dst_mbox,
                    ServiceRequestCode::ReadSysMem,
                    selector.selector(),
                    first,
                    bits,
                ))
            }

            Request::WriteSysBit {
                selector,
                addr,
                value,
            } => {
                let (idx, mask) = addr::bit_write(addr.get());
                let payload_byte: u8 = if value { mask } else { 0 };
                // `Bytes::copy_from_slice` on a single byte is cheap; no
                // heap alloc larger than a `Vec<u8>` of length 1.
                let payload = Bytes::copy_from_slice(&[payload_byte]);
                Ok(extended_req(
                    seq,
                    src_mbox,
                    dst_mbox,
                    ServiceRequestCode::WriteSysMem,
                    selector.selector(),
                    idx,
                    1, // target_count = 1 bit
                    payload,
                ))
            }

            Request::GetTime => Ok(short_req(
                seq,
                src_mbox,
                dst_mbox,
                ServiceRequestCode::GetTime,
                // Spec §3.7 addition: selector byte is 0x00 for services
                // that don't address memory.
                SegmentSelector::None,
                0,
                0,
            )),

            Request::GetInfo => Ok(short_req(
                seq,
                src_mbox,
                dst_mbox,
                ServiceRequestCode::GetInfo,
                SegmentSelector::None,
                0,
                0,
            )),

            Request::WriteSysBytes {
                selector,
                addr,
                bytes,
            } => {
                // Byte-selector `target_index` is the 0-based byte
                // index. `target_count` is selector-native: byte count.
                if bytes.len() > crate::codec::MAX_TEXT_LENGTH as usize {
                    return Err(Error::InvalidRequest(
                        "WriteSysBytes.bytes exceeds codec MAX_TEXT_LENGTH (4096 bytes)",
                    ));
                }
                let byte_count = u16::try_from(bytes.len()).map_err(|_| {
                    Error::InvalidRequest("WriteSysBytes.bytes too long for u16 target_count")
                })?;
                Ok(extended_req(
                    seq,
                    src_mbox,
                    dst_mbox,
                    ServiceRequestCode::WriteSysMem,
                    selector.selector(),
                    addr::byte_target(addr.get()),
                    byte_count,
                    bytes,
                ))
            }
        }
    }
}

/// Build a SHORT request frame (spec §3.2) from typed body fields.
///
/// Factored out so every `ShortReq`-emitting arm of `into_frame` shares
/// one layout truth instead of duplicating the `Frame` literal.
fn short_req(
    seq: u16,
    src_mbox: u32,
    dst_mbox: u32,
    svc_req_code: ServiceRequestCode,
    seg_selector: SegmentSelector,
    target_index: u16,
    target_count: u16,
) -> Frame {
    Frame {
        pkt_type: PacketType::Req, // spec §3.1: request packets are 0x0002
        seq_index: seq,
        text_length: 0, // codec re-derives from extended.len()
        #[allow(clippy::cast_possible_truncation)]
        msg_seq: seq as u8, // spec §3.1: byte 30 mirrors seq low byte
        msg_type: MessageType::Short,
        mbox_src: src_mbox,
        mbox_dst: dst_mbox,
        pkt_num: 1,
        total_pkt_num: 1,
        time: None,
        reserved_a: [0u8; 20],
        body: FrameBody::ShortReq {
            svc_req_code,
            seg_selector,
            target_index,
            target_count,
            inline_payload: [0u8; 6],
        },
        extended: Bytes::new(),
    }
}

/// Build an EXTENDED request frame (spec §3.5) from typed body fields
/// and a payload.
///
/// Single-packet only — `pkt_num_ext = total_pkt_num_ext = 1`. Multi-packet
/// fragmentation is a future concern (spec §6.3, §9.2 O-3).
#[allow(clippy::too_many_arguments)] // eight primitives is cheaper here than a one-off params struct
fn extended_req(
    seq: u16,
    src_mbox: u32,
    dst_mbox: u32,
    svc_req_code: ServiceRequestCode,
    seg_selector: SegmentSelector,
    target_index: u16,
    target_count: u16,
    extended: Bytes,
) -> Frame {
    Frame {
        pkt_type: PacketType::Req,
        seq_index: seq,
        // Codec ignores this field on emit (it uses `extended.len()`), but
        // keeping it in sync keeps round-trip equality clean.
        text_length: u16::try_from(extended.len()).unwrap_or(u16::MAX),
        #[allow(clippy::cast_possible_truncation)]
        msg_seq: seq as u8,
        msg_type: MessageType::Extended,
        mbox_src: src_mbox,
        mbox_dst: dst_mbox,
        pkt_num: 1,
        total_pkt_num: 1,
        time: None,
        reserved_a: [0u8; 20],
        body: FrameBody::Extended {
            svc_req_code,
            seg_selector,
            target_index,
            target_count,
            pkt_num_ext: 1,
            total_pkt_num_ext: 1,
            reserved_body: [0u8; 6],
        },
        extended,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_sys_words_builds_short_req() {
        // Spec §3.2 smoke test: read 2 words from %R5 → target_index = 4
        // (word-level, zero-based), target_count = 2 (words).
        let req = Request::ReadSysWords {
            selector: WordSelector::R,
            addr: FanucAddr::from_raw(5),
            count: 2,
        };
        let frame = req.into_frame(7, 0, 0x0000_0E10).expect("build short req");

        assert_eq!(frame.pkt_type, PacketType::Req);
        assert_eq!(frame.msg_type, MessageType::Short);
        assert_eq!(frame.seq_index, 7);
        assert_eq!(frame.mbox_dst, 0x0000_0E10);
        assert_eq!(frame.pkt_num, 1);
        assert_eq!(frame.total_pkt_num, 1);

        match frame.body {
            FrameBody::ShortReq {
                svc_req_code,
                seg_selector,
                target_index,
                target_count,
                inline_payload,
            } => {
                assert_eq!(svc_req_code, ServiceRequestCode::ReadSysMem);
                assert_eq!(seg_selector, SegmentSelector::WordR);
                assert_eq!(target_index, 4);
                assert_eq!(target_count, 2);
                assert_eq!(inline_payload, [0u8; 6]);
            }
            other => panic!("expected ShortReq body, got {other:?}"),
        }
        assert!(frame.extended.is_empty());
    }

    #[test]
    fn write_sys_bit_builds_extended() {
        // Spec capture: Writing DO[184] = true → Extended, svc=WriteSysMem,
        // sel=BitI, target_index=183, target_count=1 (bit), payload=[0x80].
        let req = Request::WriteSysBit {
            selector: BitSelector::I,
            addr: FanucAddr::from_raw(184),
            value: true,
        };
        let frame = req.into_frame(9, 0, 0x0000_0E10).expect("build extended");

        assert_eq!(frame.msg_type, MessageType::Extended);
        assert_eq!(frame.seq_index, 9);

        match frame.body {
            FrameBody::Extended {
                svc_req_code,
                seg_selector,
                target_index,
                target_count,
                pkt_num_ext,
                total_pkt_num_ext,
                ..
            } => {
                assert_eq!(svc_req_code, ServiceRequestCode::WriteSysMem);
                assert_eq!(seg_selector, SegmentSelector::BitI);
                assert_eq!(target_index, 183);
                assert_eq!(target_count, 1);
                assert_eq!(pkt_num_ext, 1);
                assert_eq!(total_pkt_num_ext, 1);
            }
            other => panic!("expected Extended body, got {other:?}"),
        }
        assert_eq!(frame.extended.as_ref(), &[0x80u8][..]);
    }

    #[test]
    fn write_sys_bit_false_emits_zero_byte() {
        let req = Request::WriteSysBit {
            selector: BitSelector::Q,
            addr: FanucAddr::from_raw(1),
            value: false,
        };
        let frame = req.into_frame(1, 0, 0x0000_0E10).expect("build extended");
        assert_eq!(frame.extended.as_ref(), &[0x00u8][..]);
    }

    #[test]
    fn write_sys_words_odd_bytes_rejected() {
        let req = Request::WriteSysWords {
            selector: WordSelector::R,
            addr: FanucAddr::from_raw(1),
            words: Bytes::from_static(&[0x01, 0x02, 0x03]),
        };
        let err = req
            .into_frame(1, 0, 0x0000_0E10)
            .expect_err("odd byte count should reject");
        match err {
            Error::InvalidRequest(_) => {}
            other => panic!("expected InvalidRequest, got {other:?}"),
        }
    }

    #[test]
    fn write_sys_words_over_max_text_length_rejected() {
        // One byte past the 4 KiB codec cap (spec §9.2 O-2).
        let oversize = vec![0u8; crate::codec::MAX_TEXT_LENGTH as usize + 2];
        let req = Request::WriteSysWords {
            selector: WordSelector::R,
            addr: FanucAddr::from_raw(1),
            words: Bytes::from(oversize),
        };
        let err = req
            .into_frame(1, 0, 0x0000_0E10)
            .expect_err("oversize payload should reject");
        match err {
            Error::InvalidRequest(msg) => {
                assert!(
                    msg.contains("MAX_TEXT_LENGTH"),
                    "expected MAX_TEXT_LENGTH message, got {msg:?}"
                );
            }
            other => panic!("expected InvalidRequest, got {other:?}"),
        }
    }

    #[test]
    fn write_sys_words_at_exact_max_accepted() {
        // Exactly at the cap is fine — only strict overflow should reject.
        let at_max = vec![0u8; crate::codec::MAX_TEXT_LENGTH as usize];
        let req = Request::WriteSysWords {
            selector: WordSelector::R,
            addr: FanucAddr::from_raw(1),
            words: Bytes::from(at_max),
        };
        req.into_frame(1, 0, 0x0000_0E10)
            .expect("exactly at cap should succeed");
    }

    #[test]
    fn write_sys_words_builds_extended_with_word_count() {
        // Writing %R1 = 0x04D2 (1234) — 1 word, 2 bytes. text_length diverges
        // from target_count per spec §3.5.
        let req = Request::WriteSysWords {
            selector: WordSelector::R,
            addr: FanucAddr::from_raw(1),
            words: Bytes::from_static(&[0xD2, 0x04]),
        };
        let frame = req.into_frame(2, 0, 0x0000_0E10).expect("build extended");
        match frame.body {
            FrameBody::Extended {
                svc_req_code,
                seg_selector,
                target_index,
                target_count,
                ..
            } => {
                assert_eq!(svc_req_code, ServiceRequestCode::WriteSysMem);
                assert_eq!(seg_selector, SegmentSelector::WordR);
                assert_eq!(target_index, 0);
                assert_eq!(target_count, 1, "selector-native: 1 word, not 2 bytes");
            }
            other => panic!("expected Extended body, got {other:?}"),
        }
        assert_eq!(frame.extended.as_ref(), &[0xD2, 0x04][..]);
    }

    #[test]
    fn selector_mapping_round_trips() {
        // Spec §3.7: five selector byte values.
        assert_eq!(WordSelector::R.selector() as u8, 0x08);
        assert_eq!(WordSelector::AI.selector() as u8, 0x0A);
        assert_eq!(WordSelector::AQ.selector() as u8, 0x0C);
        assert_eq!(BitSelector::I.selector() as u8, 0x46);
        assert_eq!(BitSelector::Q.selector() as u8, 0x48);
    }

    #[test]
    fn get_time_uses_none_selector() {
        let frame = Request::GetTime
            .into_frame(3, 0, 0x0000_0E10)
            .expect("build short req");
        match frame.body {
            FrameBody::ShortReq {
                svc_req_code,
                seg_selector,
                target_index,
                target_count,
                ..
            } => {
                assert_eq!(svc_req_code, ServiceRequestCode::GetTime);
                assert_eq!(seg_selector, SegmentSelector::None);
                assert_eq!(target_index, 0);
                assert_eq!(target_count, 0);
            }
            other => panic!("expected ShortReq body, got {other:?}"),
        }
    }

    #[test]
    fn get_info_uses_none_selector() {
        let frame = Request::GetInfo
            .into_frame(4, 0, 0x0000_0E10)
            .expect("build short req");
        match frame.body {
            FrameBody::ShortReq {
                svc_req_code,
                seg_selector,
                ..
            } => {
                assert_eq!(svc_req_code, ServiceRequestCode::GetInfo);
                assert_eq!(seg_selector, SegmentSelector::None);
            }
            other => panic!("expected ShortReq body, got {other:?}"),
        }
    }

    #[test]
    fn read_sys_bits_uses_bit_aligned_range() {
        // DI[9..16]: bit-aligned first = 8, count_bits = 8, offset = 0.
        let req = Request::ReadSysBits {
            selector: BitSelector::Q,
            addr: FanucAddr::from_raw(9),
            count: 8,
        };
        let frame = req.into_frame(5, 0, 0x0000_0E10).expect("build short req");
        match frame.body {
            FrameBody::ShortReq {
                seg_selector,
                target_index,
                target_count,
                ..
            } => {
                assert_eq!(seg_selector, SegmentSelector::BitQ);
                assert_eq!(target_index, 8);
                assert_eq!(target_count, 8);
            }
            other => panic!("expected ShortReq body, got {other:?}"),
        }
    }

    #[test]
    fn init_delegates_to_frame_init() {
        let frame = Request::Init
            .into_frame(999, 0xDEAD_BEEF, 0xCAFE_BABE)
            .expect("init");
        assert_eq!(frame.pkt_type, PacketType::Init);
        assert_eq!(frame.seq_index, 0);
        assert_eq!(frame.mbox_src, 0);
        assert_eq!(frame.mbox_dst, 0);
    }

    #[test]
    fn service_code_mapping() {
        assert_eq!(
            Request::ReadSysWords {
                selector: WordSelector::R,
                addr: FanucAddr::from_raw(1),
                count: 1,
            }
            .service_code(),
            ServiceRequestCode::ReadSysMem,
        );
        assert_eq!(
            Request::WriteSysBit {
                selector: BitSelector::I,
                addr: FanucAddr::from_raw(1),
                value: true,
            }
            .service_code(),
            ServiceRequestCode::WriteSysMem,
        );
        assert_eq!(Request::GetTime.service_code(), ServiceRequestCode::GetTime);
        assert_eq!(Request::GetInfo.service_code(), ServiceRequestCode::GetInfo);
        assert_eq!(
            Request::WriteSysBytes {
                selector: ByteSelector::G,
                addr: FanucAddr::from_raw(1),
                bytes: Bytes::from_static(b"CLRASG"),
            }
            .service_code(),
            ServiceRequestCode::WriteSysMem,
        );
    }

    #[test]
    fn write_sys_bytes_clrasg_builds_extended_with_byte_count() {
        // CLRASG: 6 ASCII bytes over %G[1]. Per snpx-findings §A.3,
        // target_count = 6 (bytes), text_length = 6 (bytes), selector
        // = ByteG (0x38), target_index = 0 (addr=1 → 0-based).
        let req = Request::WriteSysBytes {
            selector: ByteSelector::G,
            addr: FanucAddr::from_raw(1),
            bytes: Bytes::from_static(b"CLRASG"),
        };
        let frame = req.into_frame(11, 0, 0x0000_0E10).expect("build extended");
        assert_eq!(frame.msg_type, MessageType::Extended);
        match frame.body {
            FrameBody::Extended {
                svc_req_code,
                seg_selector,
                target_index,
                target_count,
                ..
            } => {
                assert_eq!(svc_req_code, ServiceRequestCode::WriteSysMem);
                assert_eq!(seg_selector, SegmentSelector::ByteG);
                assert_eq!(target_index, 0);
                assert_eq!(target_count, 6, "byte count, not bit count");
            }
            other => panic!("expected Extended body, got {other:?}"),
        }
        assert_eq!(frame.extended.as_ref(), b"CLRASG");
    }

    #[test]
    fn write_sys_bytes_over_max_rejected() {
        let oversize = vec![0u8; crate::codec::MAX_TEXT_LENGTH as usize + 1];
        let req = Request::WriteSysBytes {
            selector: ByteSelector::G,
            addr: FanucAddr::from_raw(1),
            bytes: Bytes::from(oversize),
        };
        let err = req
            .into_frame(1, 0, 0x0000_0E10)
            .expect_err("oversize should reject");
        assert!(matches!(err, Error::InvalidRequest(_)));
    }

    #[test]
    fn byte_selector_maps_to_byte_g() {
        assert_eq!(ByteSelector::G.selector() as u8, 0x38);
    }
}
