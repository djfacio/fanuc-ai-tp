//! Wire round-trip proptest — for every valid `Frame`, emit → parse → equal.
//! Skips `FrameBody::ShortErr` (opaque body; covered by golden-vector phase)
//! and `FrameBody::InitAck` (ditto).

use bytes::{Bytes, BytesMut};
use proptest::collection::vec as pvec;
use proptest::prelude::*;

use snpx_codec::{
    Frame, FrameBody, MessageType, PacketType, PiggyBack, SegmentSelector, ServiceRequestCode,
    SrtpCodec, Status,
};
use tokio_util::codec::{Decoder, Encoder};

// ---- Strategy helpers --------------------------------------------------

fn any_svc_req_code() -> impl Strategy<Value = ServiceRequestCode> {
    // Exclude FanucHelloInit — it's hello-only and doesn't belong in a
    // generic round-trip; the `fanuc_hello` unit test already covers it.
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

/// Build a (`msg_type`, body, `extended_payload`) tuple consistent with
/// the spec §4.1 dispatch table.
fn any_body_and_ext() -> impl Strategy<Value = (MessageType, FrameBody, Vec<u8>)> {
    prop_oneof![
        // SHORT request — no extended payload.
        short_req_body().prop_map(|b| (MessageType::Short, b, Vec::new())),
        // SHORT_ACK — no extended payload.
        short_ack_body().prop_map(|b| (MessageType::ShortAck, b, Vec::new())),
        // EXTENDED — 0..=1024 bytes of payload.
        (extended_body(false), pvec(any::<u8>(), 0..=1024)).prop_map(|(b, ext)| (
            MessageType::Extended,
            b,
            ext
        )),
        // EXTENDED_ACK — 0..=1024 bytes of payload.
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
                // Ensure at least one non-zero so emit's "preserve verbatim"
                // branch fires — otherwise emit fills the EXTENDED defaults
                // (0x00000200 at offsets 2 and 10) and round-trip would see
                // a mismatch against the all-zero input. The test's job is
                // to prove byte-exact round-trip, so we pin the reserved
                // field explicitly.
                if reserved_a == [0u8; 20] {
                    reserved_a[0] = 1;
                }
                Frame {
                    pkt_type,
                    seq_index: seq,
                    // Bounded by proptest strategy to 0..=1024; fits u16.
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

// ---- Tests --------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    #[test]
    fn frame_emit_parse_roundtrips(frame in any_frame()) {
        let mut buf = BytesMut::new();
        frame.emit(&mut buf);
        let bytes = buf.freeze();
        let parsed = Frame::parse(&bytes).expect("parse");
        prop_assert_eq!(parsed, frame);
    }

    #[test]
    fn codec_encode_decode_roundtrips(frame in any_frame()) {
        let mut codec = SrtpCodec;
        let mut buf = BytesMut::new();
        codec.encode(frame.clone(), &mut buf).expect("encode");
        let decoded = codec
            .decode(&mut buf)
            .expect("decode")
            .expect("full frame");
        prop_assert_eq!(decoded, frame);
        prop_assert!(buf.is_empty());
    }
}

#[test]
fn encode_decode_max_extended_frame() {
    // Exactly-at-cap EXTENDED payload round-trips cleanly and the
    // codec consumes every byte. This guards the boundary between
    // Request::into_frame's accept-rule and SrtpCodec::encode's
    // PduTooLarge gate (both at MAX_TEXT_LENGTH inclusive).
    //
    // Construct via Request::WriteSysWords so `reserved_a` gets the
    // canonical 0x00000200 slots that Frame::emit applies to Extended
    // frames — otherwise the first emit→decode pair disagrees on
    // those reserved bytes.
    let payload = vec![0xA5u8; snpx_codec::MAX_TEXT_LENGTH as usize];
    let req = snpx_codec::Request::WriteSysWords {
        selector: snpx_codec::WordSelector::R,
        addr: snpx_codec::FanucAddr::from_raw(1),
        words: Bytes::from(payload.clone()),
    };
    let mut frame = req.into_frame(7, 0, 0x0000_0E10).expect("build request");
    // Pre-populate reserved_a to the canonical Extended values so the
    // round-trip preserves them verbatim.
    let le = 0x0000_0200u32.to_le_bytes();
    frame.reserved_a[2..6].copy_from_slice(&le);
    frame.reserved_a[10..14].copy_from_slice(&le);

    let mut codec = SrtpCodec;
    let mut buf = BytesMut::new();
    codec.encode(frame.clone(), &mut buf).expect("encode @ max");
    assert_eq!(
        buf.len(),
        56 + payload.len(),
        "encoded length = header + payload"
    );
    let decoded = codec
        .decode(&mut buf)
        .expect("decode ok")
        .expect("full frame");
    assert_eq!(decoded, frame);
    assert!(buf.is_empty(), "codec consumed the whole frame");
}
