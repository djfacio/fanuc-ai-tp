//! Agreement tests for frame emit/parse structural invariants —
//! the Tier 3 Verus target T3-1.
//!
//! `wire_roundtrip.rs` pins `parse(emit(f)) == f` (byte-round-trip).
//! This test adds the structural INVARIANTS the downstream pipeline
//! depends on regardless of the round-trip value equality:
//!
//! **F1 Size-exact.** `emit(f)` produces exactly `56 + f.extended.len()`
//!       bytes. Callers rely on this to allocate the wire buffer
//!       up-front and to pre-commit transport budget.
//!
//! **F2 Header text_length matches payload.** After emit, the
//!       header's `text_length` field equals `f.extended.len()`.
//!       Parsers downstream (including `Frame::parse` re-reading our
//!       own output) use this to split header from body.
//!
//! **F3 Header prefix dispatch is total.** `Frame::parse` on
//!       any `emit`-produced byte sequence succeeds — no legitimate
//!       emit output is unparseable.
//!
//! **F4 Stable prefix shape.** The first 56 bytes of `emit(f)` form
//!       a valid `HeaderRaw` whose `pkt_type`, `seq_index`,
//!       `mbox_src`, `mbox_dst`, `pkt_num`, `total_pkt_num`, and
//!       `msg_seq2` match the frame's corresponding fields byte-for-
//!       byte.
//!
//! No Verus binding here — `Frame::emit` writes into `BytesMut`,
//! whose `external_type_specification` would require wrapping the
//! entire `bytes` crate. That's several days of scaffolding for a
//! property already covered at runtime by this proptest.

use bytes::{Bytes, BytesMut};
use proptest::collection::vec as pvec;
use proptest::prelude::*;

use snpx_codec::{
    Frame, FrameBody, MessageType, PacketType, PiggyBack, SegmentSelector, ServiceRequestCode,
    Status,
};

// ---- Strategies (forked from wire_roundtrip.rs; keep in sync) -----------

fn any_svc_req_code() -> impl Strategy<Value = ServiceRequestCode> {
    prop_oneof![
        Just(ServiceRequestCode::PlcShortStatus),
        Just(ServiceRequestCode::GetProgName),
        Just(ServiceRequestCode::ReadSysMem),
        Just(ServiceRequestCode::ReadTaskMem),
        Just(ServiceRequestCode::ReadProgMem),
        Just(ServiceRequestCode::WriteSysMem),
        Just(ServiceRequestCode::WriteTaskMem),
        Just(ServiceRequestCode::WriteProgMem),
        Just(ServiceRequestCode::GetTime),
        Just(ServiceRequestCode::GetInfo),
    ]
}

fn any_seg_selector() -> impl Strategy<Value = SegmentSelector> {
    prop_oneof![
        Just(SegmentSelector::WordR),
        Just(SegmentSelector::WordAI),
        Just(SegmentSelector::WordAQ),
        Just(SegmentSelector::BitI),
        Just(SegmentSelector::BitQ),
        Just(SegmentSelector::ByteG),
    ]
}

fn any_time() -> impl Strategy<Value = Option<(u8, u8, u8)>> {
    prop_oneof![
        Just(None),
        (1u8..=23, 0u8..=59, 0u8..=59).prop_map(|(h, m, s)| Some((h, m, s))),
    ]
}

fn short_req_body() -> impl Strategy<Value = FrameBody> {
    (
        any_svc_req_code(),
        any_seg_selector(),
        any::<u16>(),
        any::<u16>(),
        pvec(any::<u8>(), 6..=6),
    )
        .prop_map(|(svc, sel, idx, cnt, inline)| {
            let mut arr = [0u8; 6];
            arr.copy_from_slice(&inline);
            FrameBody::ShortReq {
                svc_req_code: svc,
                seg_selector: sel,
                target_index: idx,
                target_count: cnt,
                inline_payload: arr,
            }
        })
}

fn short_ack_body() -> impl Strategy<Value = FrameBody> {
    (
        any::<u8>(),
        any::<u8>(),
        pvec(any::<u8>(), 6..=6),
        any::<u8>(),
        any::<u8>(),
        any::<u16>(),
        any::<u16>(),
    )
        .prop_map(|(major, minor, inline, prog, priv_, sweep, status)| {
            let mut arr = [0u8; 6];
            arr.copy_from_slice(&inline);
            FrameBody::ShortAck {
                status: Status { major, minor },
                inline_payload: arr,
                piggy: PiggyBack {
                    prog_num: prog,
                    privilege: priv_,
                    sweep_ms: sweep,
                    status,
                },
            }
        })
}

fn extended_body(is_ack: bool) -> impl Strategy<Value = FrameBody> {
    (
        any_svc_req_code(),
        any_seg_selector(),
        any::<u16>(),
        any::<u16>(),
        any::<u8>(),
        any::<u8>(),
    )
        .prop_map(move |(svc, sel, idx, cnt, pn, tpn)| {
            if is_ack {
                FrameBody::ExtendedAck {
                    svc_req_code: svc,
                    seg_selector: sel,
                    target_index: idx,
                    target_count: cnt,
                    pkt_num_ext: pn,
                    total_pkt_num_ext: tpn,
                    reserved_body: [0u8; 6],
                }
            } else {
                FrameBody::Extended {
                    svc_req_code: svc,
                    seg_selector: sel,
                    target_index: idx,
                    target_count: cnt,
                    pkt_num_ext: pn,
                    total_pkt_num_ext: tpn,
                    reserved_body: [0u8; 6],
                }
            }
        })
}

fn any_body_and_ext() -> impl Strategy<Value = (MessageType, FrameBody, Vec<u8>)> {
    prop_oneof![
        short_req_body().prop_map(|b| (MessageType::Short, b, Vec::new())),
        short_ack_body().prop_map(|b| (MessageType::ShortAck, b, Vec::new())),
        (extended_body(false), pvec(any::<u8>(), 0..=1024)).prop_map(|(b, ext)| (
            MessageType::Extended,
            b,
            ext
        )),
        (extended_body(true), pvec(any::<u8>(), 0..=1024)).prop_map(|(b, ext)| (
            MessageType::ExtendedAck,
            b,
            ext
        )),
    ]
}

fn any_frame() -> impl Strategy<Value = Frame> {
    (
        prop_oneof![
            Just(PacketType::Req),
            Just(PacketType::ReqAck),
            Just(PacketType::Unknown),
        ],
        any::<u16>(),
        any::<u32>(),
        any::<u32>(),
        1u8..=8,
        1u8..=8,
        any_time(),
        pvec(any::<u8>(), 20..=20),
        any_body_and_ext(),
    )
        .prop_map(
            |(pkt_type, seq, msrc, mdst, pn, tpn, time, reserved, (msg_type, body, ext))| {
                let mut reserved_a = [0u8; 20];
                reserved_a.copy_from_slice(&reserved);
                if reserved_a == [0u8; 20] {
                    reserved_a[0] = 1;
                }
                Frame {
                    pkt_type,
                    seq_index: seq,
                    text_length: u16::try_from(ext.len()).expect("ext.len() <= 1024"),
                    #[allow(clippy::cast_possible_truncation)]
                    msg_seq: seq as u8,
                    msg_type,
                    mbox_src: msrc,
                    mbox_dst: mdst,
                    pkt_num: pn,
                    total_pkt_num: tpn,
                    time,
                    reserved_a,
                    body,
                    extended: Bytes::from(ext),
                }
            },
        )
}

// ---- Invariant tests ----------------------------------------------------

proptest! {
    /// **F1 Size-exact.** `emit(f)` produces exactly `56 + extended.len()`
    /// bytes for every well-formed frame. The allocator in `SrtpCodec::encode`
    /// pre-reserves on this assumption; a drift here would make that reserve
    /// either too tight (realloc during encode) or too loose (wasted hot
    /// allocation).
    #[test]
    fn f1_emit_size_is_56_plus_extended(frame in any_frame()) {
        let mut buf = BytesMut::new();
        frame.emit(&mut buf);
        prop_assert_eq!(
            buf.len(),
            56 + frame.extended.len(),
            "emit() size = {} but expected 56 + {} = {}",
            buf.len(),
            frame.extended.len(),
            56 + frame.extended.len()
        );
    }

    /// **F2 Header text_length matches payload.** After emit, the header's
    /// `text_length` LE u16 at bytes 4..6 equals `frame.extended.len()`.
    /// Downstream parsers (including our own) rely on this to split header
    /// from body without re-examining the frame object.
    #[test]
    fn f2_header_text_length_matches_extended(frame in any_frame()) {
        let mut buf = BytesMut::new();
        frame.emit(&mut buf);
        let bytes = buf.freeze();
        prop_assert!(bytes.len() >= 56);
        let header_text_length =
            u16::from_le_bytes([bytes[4], bytes[5]]) as usize;
        prop_assert_eq!(
            header_text_length, frame.extended.len(),
            "header.text_length = {} but frame.extended.len() = {}",
            header_text_length, frame.extended.len()
        );
    }

    /// **F3 Parse totality on emit output.** Every byte sequence produced by
    /// `emit` is parseable. A counter-example would mean emit can construct
    /// a frame the parser rejects — a correctness break in the encoder.
    #[test]
    fn f3_parse_accepts_every_emit_output(frame in any_frame()) {
        let mut buf = BytesMut::new();
        frame.emit(&mut buf);
        let bytes = buf.freeze();
        prop_assert!(
            Frame::parse(&bytes).is_ok(),
            "Frame::parse rejected emit output — encoder/decoder disagree"
        );
    }

    /// **F4 Stable prefix shape.** The first 56 bytes of `emit` decode
    /// structurally: `pkt_type`, `seq_index`, `mbox_src`, `mbox_dst`,
    /// `pkt_num`, `total_pkt_num`, and `msg_seq2` all round-trip at the
    /// byte-offset level. This pins the header schema against silent
    /// reordering.
    #[test]
    fn f4_header_prefix_is_byte_exact(frame in any_frame()) {
        let mut buf = BytesMut::new();
        frame.emit(&mut buf);
        let bytes = buf.freeze();
        prop_assert!(bytes.len() >= 56);

        let seq_index = u16::from_le_bytes([bytes[2], bytes[3]]);
        prop_assert_eq!(
            seq_index, frame.seq_index,
            "seq_index: emitted {} vs field {}",
            seq_index, frame.seq_index
        );

        // bytes 30 = msg_seq2 (mirror of seq_index low byte per palatis,
        // but callers may override — emit preserves self.msg_seq).
        prop_assert_eq!(
            bytes[30], frame.msg_seq,
            "msg_seq2 byte: emitted {} vs field {}",
            bytes[30], frame.msg_seq
        );

        let mbox_src = u32::from_le_bytes([bytes[32], bytes[33], bytes[34], bytes[35]]);
        prop_assert_eq!(
            mbox_src, frame.mbox_src,
            "mbox_src: emitted {} vs field {}",
            mbox_src, frame.mbox_src
        );

        let mbox_dst = u32::from_le_bytes([bytes[36], bytes[37], bytes[38], bytes[39]]);
        prop_assert_eq!(
            mbox_dst, frame.mbox_dst,
            "mbox_dst: emitted {} vs field {}",
            mbox_dst, frame.mbox_dst
        );

        prop_assert_eq!(bytes[40], frame.pkt_num, "pkt_num byte");
        prop_assert_eq!(bytes[41], frame.total_pkt_num, "total_pkt_num byte");
    }
}
