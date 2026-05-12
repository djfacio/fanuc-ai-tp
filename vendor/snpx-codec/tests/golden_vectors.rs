//! Golden byte vectors from `Booozie-Z/Fanuc_GESRTP_Driver/docs/srtp packets.txt`.
//! Spec §8.2, §10 acceptance criterion "five golden byte vectors parse and
//! emit byte-equal".
//!
//! Each `.bin` file is a single SRTP frame captured on the wire. The tests
//! verify:
//!
//! 1. `Frame::parse` decodes the bytes into the expected typed shape.
//! 2. `frame.emit(&mut buf)` writes back exactly the original bytes
//!    (byte-for-byte).
//! 3. The codec `SrtpCodec::decode`/`encode` round-trip matches.
//!
//! Attribution: see `crates/snpx-codec/src/golden/README.md` and the
//! crate-root `NOTICE` file. Captures are MIT-licensed (Booozie-Z).

use bytes::{Bytes, BytesMut};
use snpx_codec::{
    addr, BitSelector, Frame, FrameBody, MessageType, PacketType, SegmentSelector,
    ServiceRequestCode, SrtpCodec,
};
use tokio_util::codec::{Decoder, Encoder};

const INIT_BIN: &[u8] = include_bytes!("../src/golden/init.bin");
const READ_R1_REQ: &[u8] = include_bytes!("../src/golden/read_r1_req.bin");
const READ_R1_ACK: &[u8] = include_bytes!("../src/golden/read_r1_ack.bin");
const WRITE_R1_1234_REQ: &[u8] = include_bytes!("../src/golden/write_r1_1234_req.bin");
const WRITE_DO184_REQ: &[u8] = include_bytes!("../src/golden/write_do184_req.bin");

/// Assert a full codec round-trip: bytes → decode → encode → equal bytes.
/// Also confirms the decoder consumes the whole buffer (no trailing bytes).
fn assert_codec_roundtrip(golden: &[u8]) -> Frame {
    let mut codec = SrtpCodec;
    let mut buf = BytesMut::from(golden);
    let frame = codec
        .decode(&mut buf)
        .expect("decode ok")
        .expect("full frame");
    assert!(buf.is_empty(), "codec left bytes on the floor");

    let mut out = BytesMut::new();
    codec.encode(frame.clone(), &mut out).expect("encode");
    assert_eq!(
        &out[..],
        golden,
        "codec emit != golden bytes (len {} vs {})",
        out.len(),
        golden.len()
    );
    frame
}

// ---------------------------------------------------------------------------

#[test]
fn init_bin_is_56_zero_bytes() {
    assert_eq!(INIT_BIN.len(), 56);
    assert_eq!(INIT_BIN, &[0u8; 56][..]);

    // Frame::init().emit(...) must reproduce the same 56 zero bytes.
    let mut buf = BytesMut::new();
    Frame::init().emit(&mut buf);
    assert_eq!(&buf[..], INIT_BIN);
}

#[test]
fn read_r1_req_bin_parses_and_round_trips() {
    assert_eq!(READ_R1_REQ.len(), 56);

    let frame = Frame::parse(&Bytes::from_static(READ_R1_REQ)).expect("parse");
    assert_eq!(frame.pkt_type, PacketType::Req);
    assert_eq!(frame.msg_type, MessageType::Short);
    match frame.body {
        FrameBody::ShortReq {
            svc_req_code,
            seg_selector,
            target_index,
            target_count,
            ..
        } => {
            // Spec §8.2 assertions for read_r1_req.bin:
            // ShortReq { svc=ReadSysMem, sel=WordR, idx=0, count=1 }
            assert_eq!(svc_req_code, ServiceRequestCode::ReadSysMem);
            assert_eq!(seg_selector, SegmentSelector::WordR);
            assert_eq!(target_index, 0);
            assert_eq!(target_count, 1);
        }
        other => panic!("expected ShortReq, got {other:?}"),
    }

    // Emit back and assert byte-equality with the original capture.
    let mut buf = BytesMut::new();
    frame.emit(&mut buf);
    assert_eq!(&buf[..], READ_R1_REQ);

    // Codec round-trip consistency.
    let _ = assert_codec_roundtrip(READ_R1_REQ);
}

#[test]
fn read_r1_ack_bin_parses_and_round_trips() {
    assert_eq!(READ_R1_ACK.len(), 56);

    let frame = Frame::parse(&Bytes::from_static(READ_R1_ACK)).expect("parse");
    assert_eq!(frame.pkt_type, PacketType::ReqAck);
    assert_eq!(frame.msg_type, MessageType::ShortAck);

    match frame.body {
        FrameBody::ShortAck {
            status,
            inline_payload,
            piggy,
        } => {
            // Spec §8.2: status.major == 0, some inline payload present.
            assert_eq!(status.major, 0);
            assert_eq!(status.minor, 0);
            // Inline payload at bytes 44..50 on the wire. For read_r1_ack
            // the last two bytes are 0x01 0x01 — echoed pkt_num/total
            // from the request side, not actual %R data (the %R read
            // target was slot 1 which returns zero per snpx-findings.md §9).
            assert_eq!(inline_payload, [0x00, 0x00, 0x00, 0x00, 0x01, 0x01]);
            // Piggy-back byte at offset 50 is 0xFF = master not logged in;
            // byte 51 = 0x02 (privilege); bytes 54..56 = 0x217C (status).
            assert_eq!(piggy.prog_num, 0xFF);
            assert_eq!(piggy.privilege, 0x02);
            assert_eq!(piggy.sweep_ms, 0x0000);
            assert_eq!(piggy.status, 0x217C);
        }
        other => panic!("expected ShortAck, got {other:?}"),
    }

    let mut buf = BytesMut::new();
    frame.emit(&mut buf);
    assert_eq!(&buf[..], READ_R1_ACK);

    let _ = assert_codec_roundtrip(READ_R1_ACK);
}

#[test]
fn write_r1_1234_req_bin_parses_and_round_trips() {
    assert_eq!(WRITE_R1_1234_REQ.len(), 58);

    let frame = Frame::parse(&Bytes::from_static(WRITE_R1_1234_REQ)).expect("parse");
    assert_eq!(frame.pkt_type, PacketType::Req);
    assert_eq!(frame.msg_type, MessageType::Extended);
    // Spec §3.5: text_length = byte count of payload (2); target_count = 1 word.
    assert_eq!(frame.text_length, 2);
    assert_eq!(frame.extended.as_ref(), &[0xD2, 0x04][..]);

    match frame.body {
        FrameBody::Extended {
            svc_req_code,
            seg_selector,
            target_index,
            target_count,
            ..
        } => {
            // Spec §8.2: Extended { svc=WriteSysMem, sel=WordR, idx=0, count=1 }
            assert_eq!(svc_req_code, ServiceRequestCode::WriteSysMem);
            assert_eq!(seg_selector, SegmentSelector::WordR);
            assert_eq!(target_index, 0);
            assert_eq!(target_count, 1, "selector-native: 1 word, not 2 bytes");
        }
        other => panic!("expected Extended, got {other:?}"),
    }

    let mut buf = BytesMut::new();
    frame.emit(&mut buf);
    assert_eq!(&buf[..], WRITE_R1_1234_REQ);

    let _ = assert_codec_roundtrip(WRITE_R1_1234_REQ);
}

#[test]
fn write_do184_req_bin_parses_and_round_trips() {
    assert_eq!(WRITE_DO184_REQ.len(), 57);

    let frame = Frame::parse(&Bytes::from_static(WRITE_DO184_REQ)).expect("parse");
    assert_eq!(frame.pkt_type, PacketType::Req);
    assert_eq!(frame.msg_type, MessageType::Extended);
    assert_eq!(frame.text_length, 1);
    // Spec §8.2: payload mask = 0x80 (bit 7 of the byte, = DO184's bit).
    assert_eq!(frame.extended.as_ref(), &[0x80][..]);

    match frame.body {
        FrameBody::Extended {
            svc_req_code,
            seg_selector,
            target_index,
            target_count,
            ..
        } => {
            // Spec §8.2: Extended { svc=WriteSysMem, sel=BitI, idx=183, count=1 }
            assert_eq!(svc_req_code, ServiceRequestCode::WriteSysMem);
            assert_eq!(seg_selector, SegmentSelector::BitI);
            assert_eq!(target_index, 183);
            assert_eq!(target_count, 1);
        }
        other => panic!("expected Extended, got {other:?}"),
    }

    // Cross-check: the addr helper computes the same (idx, mask).
    assert_eq!(addr::bit_write(184), (183, 0x80));

    let mut buf = BytesMut::new();
    frame.emit(&mut buf);
    assert_eq!(&buf[..], WRITE_DO184_REQ);

    let _ = assert_codec_roundtrip(WRITE_DO184_REQ);
}

#[test]
fn write_do184_matches_request_builder() {
    // Spec §10 acceptance cross-check: building the same request via the
    // typed `Request::WriteSysBit` path produces the same wire bytes at the
    // body + payload level. The capture's reserved_a carries 0x00000200
    // (the EXTENDED default), which our builder also produces, so the
    // full 57 bytes match.
    use snpx_codec::Request;

    // seq_index = 0x3b71 is what appears in the capture at byte 2..4.
    let seq: u16 = u16::from_le_bytes([WRITE_DO184_REQ[2], WRITE_DO184_REQ[3]]);
    let req = Request::WriteSysBit {
        selector: BitSelector::I,
        addr: snpx_codec::FanucAddr::from_raw(184),
        value: true,
    };
    let frame = req.into_frame(seq, 0, 0x0000_0E10).expect("build extended");

    // The capture's header carries pkt_num/total_pkt_num = 0x01/0x02, while
    // the builder defaults to 1/1. Same for msg_seq (byte 30 = 0x02 in the
    // capture), which mirrors the byte Kepware wrote there — not our seq
    // low byte. So we don't expect byte-for-byte equality with the capture
    // here — we only cross-check the body+payload invariants.
    match frame.body {
        FrameBody::Extended {
            svc_req_code,
            seg_selector,
            target_index,
            target_count,
            ..
        } => {
            assert_eq!(svc_req_code, ServiceRequestCode::WriteSysMem);
            assert_eq!(seg_selector, SegmentSelector::BitI);
            assert_eq!(target_index, 183);
            assert_eq!(target_count, 1);
        }
        other => panic!("expected Extended, got {other:?}"),
    }
    assert_eq!(frame.extended.as_ref(), &[0x80][..]);
}
