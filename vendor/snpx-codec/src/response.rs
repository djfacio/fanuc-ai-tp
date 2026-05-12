//! Typed response ADT — the caller-facing layer above raw frames. Spec §4.3.
//!
//! `Response::from_frame` is **generic**: it classifies the inbound frame
//! by its wire shape alone, because the Request/Response ADT is stateless
//! (the codec doesn't remember what you asked). The Phase-4 `Client::request`
//! layer re-types `Response::ReadWords` as `Response::Time` when the
//! originating request was `Request::GetTime`, etc.
//!
//! Concretely this means:
//! - `SHORT_ACK` with `status.major == 0` always decodes as
//!   [`Response::ReadWords`] carrying the 6-byte inline payload. For
//!   `WriteSysBit` / `WriteSysWords` responses the caller will see an
//!   `ReadWords { words: [0;6] }` — that's fine, `Client::request` maps
//!   it to `Response::WriteOk` when it recognizes the dispatched request.
//! - `EXTENDED_ACK` with a bit-family selector decodes as
//!   [`Response::ReadBits`]; with a word-family selector as
//!   [`Response::ReadWords`]; empty extended payload as
//!   [`Response::WriteOk`].
//! - `SHORT_ACK` with `status.major != 0` decodes as [`Response::Error`].
//! - `SHORT_ERR` always decodes as [`Response::Error`].
#![allow(clippy::doc_markdown)]

use bytes::Bytes;

use crate::enums::SegmentSelector;
use crate::error::{Error, Result};
use crate::frame::{Frame, FrameBody, Status};
use crate::PacketType;

/// Caller-facing response ADT. Spec §4.3.
///
/// Kept deliberately generic — see module docs. The Phase-4 `Client` layer
/// narrows `ReadWords` / `ReadBits` into `Time` / `Info` / `WriteOk` based
/// on the request type it dispatched.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Response {
    /// The controller answered the INIT handshake with `INIT_ACK`.
    InitOk,
    /// A read of word-addressed memory. `words` carries the raw bytes;
    /// the caller decodes 16-bit little-endian words.
    ReadWords {
        /// Raw return bytes. For `SHORT_ACK` this is the 6-byte inline
        /// payload verbatim; for `EXTENDED_ACK` this is the payload
        /// following the 56-byte header.
        words: Bytes,
    },
    /// A read of bit-addressed memory. `bits` is byte-aligned; caller
    /// masks per spec §7.
    ReadBits {
        /// Raw return bytes.
        bits: Bytes,
    },
    /// A write acknowledgement. Emitted when `EXTENDED_ACK` arrives with
    /// an empty extended payload — reads return data, writes don't.
    WriteOk,
    /// Wall-clock time from the controller. Constructed by the Phase-4
    /// `Client` layer; `Response::from_frame` never emits this variant.
    Time {
        /// Hours (0..24).
        hh: u8,
        /// Minutes (0..60).
        mm: u8,
        /// Seconds (0..60).
        ss: u8,
    },
    /// Controller info / type. Constructed by the Phase-4 `Client` layer;
    /// `Response::from_frame` never emits this variant.
    Info {
        /// Raw info bytes from the controller.
        raw: Bytes,
    },
    /// A `SHORT_ERR` or non-success `SHORT_ACK`.
    Error {
        /// Parsed `(major, minor)` status bytes. FANUC R-30iB emits
        /// `(0, 0)` for every `SHORT_ERR` observed so far — spec §9.2 O-1.
        status: Status,
        /// Full 14-byte body at header offsets 42..56 for forensic
        /// inspection.
        raw: [u8; 14],
    },
}

impl Response {
    /// Classify a decoded [`Frame`] as a typed [`Response`].
    ///
    /// See module docs for the classification rules. This function never
    /// allocates — `words` / `bits` are slices of the caller's `Frame`.
    ///
    /// # Errors
    ///
    /// - [`Error::Protocol`] if the frame's packet-type / msg-type
    ///   combination doesn't match any expected response shape.
    pub fn from_frame(frame: Frame) -> Result<Self> {
        // Spec §3.8: INIT_ACK is a top-level packet-type classification,
        // orthogonal to the 14-byte body dispatch.
        if matches!(frame.pkt_type, PacketType::InitAck) {
            return Ok(Response::InitOk);
        }

        match frame.body {
            FrameBody::ShortErr { status, raw } => Ok(Response::Error { status, raw }),

            FrameBody::ShortAck {
                status,
                inline_payload,
                piggy,
            } => {
                if status.major != 0 {
                    // Reconstruct the 14-byte body for forensic preservation
                    // so `Error::raw` layout matches the `ShortErr` path.
                    let raw = reassemble_short_ack_body(status, inline_payload, piggy);
                    Ok(Response::Error { status, raw })
                } else {
                    // Generic interpretation — caller's request type
                    // narrows this into Time / Info / WriteOk if needed.
                    Ok(Response::ReadWords {
                        words: Bytes::copy_from_slice(&inline_payload),
                    })
                }
            }

            FrameBody::ExtendedAck { seg_selector, .. } => {
                // Empty payload means write-ACK: reads always return data.
                if frame.extended.is_empty() {
                    Ok(Response::WriteOk)
                } else if is_bit_selector(seg_selector) {
                    Ok(Response::ReadBits {
                        bits: frame.extended,
                    })
                } else {
                    Ok(Response::ReadWords {
                        words: frame.extended,
                    })
                }
            }

            // Inbound requests / hello frames / INIT are not valid
            // responses for the Client layer. Preserve the raw body so
            // callers can see what arrived.
            FrameBody::ShortReq { .. }
            | FrameBody::Extended { .. }
            | FrameBody::Init
            | FrameBody::InitAck { .. } => {
                // Best-effort body reconstruction: zero if we can't
                // recover from the variant. `InitAck` is the only case
                // that actually carries the full 14-byte body verbatim,
                // and it's already handled above via `pkt_type`.
                Err(Error::Protocol { body: [0u8; 14] })
            }
        }
    }
}

/// True for `BitI`/`BitQ`/…/`BitG` selectors — the bit-level family.
/// Used to classify `EXTENDED_ACK` payloads as `ReadBits` vs `ReadWords`.
///
/// Byte-family selectors (`ByteI`, `ByteQ`, …) are currently classified as
/// `ReadWords`. FANUC R553 doesn't use byte selectors (`snpx-findings.md §1`),
/// so the distinction only matters for non-FANUC GE-SRTP traffic; we err
/// toward the "treat bytes as opaque words" shape because byte selectors
/// return raw bytes the caller interprets per the command channel.
fn is_bit_selector(sel: SegmentSelector) -> bool {
    matches!(
        sel,
        SegmentSelector::BitI
            | SegmentSelector::BitQ
            | SegmentSelector::BitM
            | SegmentSelector::BitT
            | SegmentSelector::BitSA
            | SegmentSelector::BitSB
            | SegmentSelector::BitSC
            | SegmentSelector::BitS
            | SegmentSelector::BitG
    )
}

/// Rebuild the 14-byte `SHORT_ACK` body from its typed fields.
///
/// Used on the error path so `Response::Error::raw` carries the same
/// layout regardless of whether the source was `ShortErr` or a
/// non-success `ShortAck`. Mirrors `FrameBody::emit_into` in frame.rs.
fn reassemble_short_ack_body(
    status: Status,
    inline_payload: [u8; 6],
    piggy: crate::frame::PiggyBack,
) -> [u8; 14] {
    let mut raw = [0u8; 14];
    raw[0] = status.major;
    raw[1] = status.minor;
    raw[2..8].copy_from_slice(&inline_payload);
    raw[8] = piggy.prog_num;
    raw[9] = piggy.privilege;
    raw[10..12].copy_from_slice(&piggy.sweep_ms.to_le_bytes());
    raw[12..14].copy_from_slice(&piggy.status.to_le_bytes());
    raw
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::enums::{MessageType, ServiceRequestCode};
    use crate::frame::{PiggyBack, Status};

    /// Build a skeletal response `Frame` — caller overrides `body`,
    /// `extended`, and `msg_type` as needed. Factored out to dodge
    /// `clippy::type_complexity` on a wide tuple-returning helper.
    fn skeleton(msg_type: MessageType, body: FrameBody, extended: Bytes) -> Frame {
        Frame {
            pkt_type: PacketType::ReqAck,
            seq_index: 42,
            text_length: u16::try_from(extended.len()).unwrap_or(u16::MAX),
            msg_seq: 42,
            msg_type,
            mbox_src: 0,
            mbox_dst: 0x0000_0E10,
            pkt_num: 1,
            total_pkt_num: 1,
            time: None,
            reserved_a: [0u8; 20],
            body,
            extended,
        }
    }

    fn piggy_sample() -> PiggyBack {
        PiggyBack {
            prog_num: 0xFF,
            privilege: 0x02,
            sweep_ms: 0,
            status: 0x217C,
        }
    }

    #[test]
    fn init_ack_frame_becomes_init_ok() {
        let frame = Frame {
            pkt_type: PacketType::InitAck,
            seq_index: 0,
            text_length: 0,
            msg_seq: 0,
            msg_type: MessageType::Short, // value ignored for InitAck
            mbox_src: 0,
            mbox_dst: 0,
            pkt_num: 0,
            total_pkt_num: 0,
            time: None,
            reserved_a: [0u8; 20],
            body: FrameBody::InitAck { raw: [0u8; 56] },
            extended: Bytes::new(),
        };
        let resp = Response::from_frame(frame).expect("parse InitAck");
        assert_eq!(resp, Response::InitOk);
    }

    #[test]
    fn short_ack_success_becomes_read_words() {
        let frame = skeleton(
            MessageType::ShortAck,
            FrameBody::ShortAck {
                status: Status { major: 0, minor: 0 },
                inline_payload: [1, 2, 3, 4, 5, 6],
                piggy: piggy_sample(),
            },
            Bytes::new(),
        );
        let resp = Response::from_frame(frame).expect("parse ShortAck");
        match resp {
            Response::ReadWords { words } => {
                assert_eq!(words.as_ref(), &[1, 2, 3, 4, 5, 6][..]);
            }
            other => panic!("expected ReadWords, got {other:?}"),
        }
    }

    #[test]
    fn short_ack_with_error_status_becomes_response_error() {
        let frame = skeleton(
            MessageType::ShortAck,
            FrameBody::ShortAck {
                status: Status { major: 1, minor: 2 },
                inline_payload: [0xAA; 6],
                piggy: piggy_sample(),
            },
            Bytes::new(),
        );
        let resp = Response::from_frame(frame).expect("parse ShortAck");
        match resp {
            Response::Error { status, raw } => {
                assert_eq!(status, Status { major: 1, minor: 2 });
                assert_eq!(raw[0], 1);
                assert_eq!(raw[1], 2);
                assert_eq!(&raw[2..8], &[0xAA; 6][..]);
                // piggy prog_num = 0xFF from piggy_sample.
                assert_eq!(raw[8], 0xFF);
            }
            other => panic!("expected Error, got {other:?}"),
        }
    }

    #[test]
    fn short_err_becomes_response_error() {
        let mut raw = [0u8; 14];
        raw[0] = 0x07;
        raw[1] = 0x05;
        let frame = skeleton(
            MessageType::ShortErr,
            FrameBody::ShortErr {
                status: Status {
                    major: 0x07,
                    minor: 0x05,
                },
                raw,
            },
            Bytes::new(),
        );
        let resp = Response::from_frame(frame).expect("parse ShortErr");
        match resp {
            Response::Error {
                status,
                raw: out_raw,
            } => {
                assert_eq!(
                    status,
                    Status {
                        major: 0x07,
                        minor: 0x05
                    }
                );
                assert_eq!(out_raw, raw);
            }
            other => panic!("expected Error, got {other:?}"),
        }
    }

    #[test]
    fn extended_ack_bit_selector_becomes_read_bits() {
        let payload = Bytes::from_static(&[0xAB]);
        let frame = skeleton(
            MessageType::ExtendedAck,
            FrameBody::ExtendedAck {
                svc_req_code: ServiceRequestCode::ReadSysMem,
                seg_selector: SegmentSelector::BitI,
                target_index: 0,
                target_count: 8,
                pkt_num_ext: 1,
                total_pkt_num_ext: 1,
                reserved_body: [0u8; 6],
            },
            payload.clone(),
        );
        let resp = Response::from_frame(frame).expect("parse ExtendedAck");
        match resp {
            Response::ReadBits { bits } => assert_eq!(bits.as_ref(), payload.as_ref()),
            other => panic!("expected ReadBits, got {other:?}"),
        }
    }

    #[test]
    fn extended_ack_word_selector_becomes_read_words() {
        let payload = Bytes::from_static(&[0xD2, 0x04]);
        let frame = skeleton(
            MessageType::ExtendedAck,
            FrameBody::ExtendedAck {
                svc_req_code: ServiceRequestCode::ReadSysMem,
                seg_selector: SegmentSelector::WordR,
                target_index: 0,
                target_count: 1,
                pkt_num_ext: 1,
                total_pkt_num_ext: 1,
                reserved_body: [0u8; 6],
            },
            payload.clone(),
        );
        let resp = Response::from_frame(frame).expect("parse ExtendedAck");
        match resp {
            Response::ReadWords { words } => assert_eq!(words.as_ref(), payload.as_ref()),
            other => panic!("expected ReadWords, got {other:?}"),
        }
    }

    #[test]
    fn extended_ack_empty_payload_becomes_write_ok() {
        let frame = skeleton(
            MessageType::ExtendedAck,
            FrameBody::ExtendedAck {
                svc_req_code: ServiceRequestCode::WriteSysMem,
                seg_selector: SegmentSelector::WordR,
                target_index: 0,
                target_count: 1,
                pkt_num_ext: 1,
                total_pkt_num_ext: 1,
                reserved_body: [0u8; 6],
            },
            Bytes::new(),
        );
        let resp = Response::from_frame(frame).expect("parse write ACK");
        assert_eq!(resp, Response::WriteOk);
    }
}
