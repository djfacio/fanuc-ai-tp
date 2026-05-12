//! `tokio-util::codec` `Decoder` + `Encoder` for SRTP frames. Spec §5.
//!
//! `SrtpCodec` is zero-sized; construct it with the unit struct literal.
//! Wrap a `TcpStream` in `tokio_util::codec::Framed<_, SrtpCodec>` for the
//! production path, or an `AsyncRead + AsyncWrite` mock for testing
//! (see `tests/transport_mock.rs`).
#![allow(clippy::doc_markdown)]

use bytes::BytesMut;
use tokio_util::codec::{Decoder, Encoder};
use tracing::{debug, trace};
use zerocopy::FromBytes;

use crate::error::Error;
use crate::frame::{Frame, HeaderRaw};

/// Per-frame cap on the EXTENDED payload length (spec §9.2 O-2). FANUC's
/// actual limit is undocumented; 4 KiB is generous for every request this
/// crate will issue (largest observed capture is ~100 bytes).
pub const MAX_TEXT_LENGTH: u16 = 4096;

/// `tokio-util::codec` codec for SRTP frames. Zero-sized.
///
/// The decoder is length-prefixed on `text_length` (header bytes 4..6,
/// u16 LE) — the codec reads the fixed 56-byte header first, extracts
/// the length, then waits for the payload. Spec §5.
#[derive(Debug, Default, Clone, Copy)]
pub struct SrtpCodec;

impl Decoder for SrtpCodec {
    type Item = Frame;
    type Error = Error;

    #[tracing::instrument(level = "trace", skip(self, src), fields(have = src.len()))]
    fn decode(&mut self, src: &mut BytesMut) -> Result<Option<Frame>, Error> {
        // Step 1: need at least the full header to know how much to read.
        // `HeaderRaw::ref_from_prefix` returns `Ok((&HeaderRaw, &[u8]))`
        // on zerocopy 0.8; an error means the prefix is shorter than 56.
        let Ok((hdr, _tail)) = HeaderRaw::ref_from_prefix(src.as_ref()) else {
            return Ok(None); // fewer than 56 bytes, try again
        };

        // Step 2: read the LE text_length via the zerocopy newtype.
        let text_len = hdr.text_length.get();

        // Spec §9.2 O-2: cap `text_length` at 4 KiB. A controller sending
        // more is either corrupted or malicious; we refuse to allocate.
        if text_len > MAX_TEXT_LENGTH {
            return Err(Error::PduTooLarge {
                len: text_len,
                cap: MAX_TEXT_LENGTH,
            });
        }

        let needed = 56usize + text_len as usize;
        if src.len() < needed {
            trace!(text_len, needed, have = src.len(), "short read");
            return Ok(None);
        }

        // Step 3: take ownership of the full frame's bytes and parse.
        let buf = src.split_to(needed).freeze();
        let frame = Frame::parse(&buf)?;
        debug!(
            pkt_type = ?frame.pkt_type,
            msg_type = ?frame.msg_type,
            seq = frame.seq_index,
            "decoded frame",
        );
        Ok(Some(frame))
    }
}

impl Encoder<Frame> for SrtpCodec {
    type Error = Error;

    #[tracing::instrument(level = "trace", skip(self, dst), fields(
        pkt_type = ?frame.pkt_type,
        msg_type = ?frame.msg_type,
        seq = frame.seq_index,
    ))]
    fn encode(&mut self, frame: Frame, dst: &mut BytesMut) -> Result<(), Error> {
        // Spec §9.2 O-2 cap applied symmetrically on encode so a bad
        // caller (one that bypassed `Request::into_frame`) can't smuggle
        // an oversize payload past the decoder's mirror check. Without
        // this, `Frame::emit` would silently truncate via
        // `u16::try_from(...).unwrap_or(u16::MAX)` and produce a
        // malformed wire frame.
        if frame.extended.len() > MAX_TEXT_LENGTH as usize {
            return Err(Error::PduTooLarge {
                len: u16::try_from(frame.extended.len()).unwrap_or(u16::MAX),
                cap: MAX_TEXT_LENGTH,
            });
        }
        dst.reserve(56 + frame.extended.len());
        debug!(
            pkt_type = ?frame.pkt_type,
            msg_type = ?frame.msg_type,
            seq = frame.seq_index,
            text_len = frame.text_length,
            "encoding frame",
        );
        frame.emit(dst);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::enums::{MessageType, PacketType, SegmentSelector, ServiceRequestCode};
    use crate::frame::FrameBody;
    use bytes::Bytes;

    fn sample_short_req() -> Frame {
        Frame {
            pkt_type: PacketType::Req,
            seq_index: 0x0203,
            text_length: 0,
            msg_seq: 0x03,
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
        }
    }

    #[test]
    fn decode_short_frame_round_trips() {
        let mut codec = SrtpCodec;
        let mut buf = BytesMut::new();
        let frame = sample_short_req();
        codec.encode(frame.clone(), &mut buf).expect("encode");
        assert_eq!(buf.len(), 56);

        let decoded = codec
            .decode(&mut buf)
            .expect("decode ok")
            .expect("full frame");
        assert_eq!(decoded, frame);
        assert!(buf.is_empty(), "codec consumed the whole frame");
    }

    #[test]
    fn decode_returns_none_on_short_buffer() {
        let mut codec = SrtpCodec;
        let mut buf = BytesMut::from(&[0u8; 32][..]);
        assert!(codec.decode(&mut buf).unwrap().is_none());
        // Codec left the bytes in place for the next poll.
        assert_eq!(buf.len(), 32);
    }

    #[test]
    fn encode_rejects_oversize_extended_payload() {
        use bytes::Bytes;
        let mut codec = SrtpCodec;
        let oversize = vec![0u8; MAX_TEXT_LENGTH as usize + 1];
        let frame = Frame {
            extended: Bytes::from(oversize),
            ..sample_short_req()
        };
        let mut buf = BytesMut::new();
        match codec.encode(frame, &mut buf) {
            Err(Error::PduTooLarge { len, cap }) => {
                assert_eq!(len, MAX_TEXT_LENGTH + 1);
                assert_eq!(cap, MAX_TEXT_LENGTH);
            }
            other => panic!("expected PduTooLarge, got {other:?}"),
        }
        assert!(buf.is_empty(), "encoder must not emit partial frame");
    }

    #[test]
    fn decode_rejects_oversize_text_length() {
        let mut codec = SrtpCodec;
        // Craft a valid-looking 56-byte header with text_length = 8192
        // (0x2000 LE).
        let mut header = [0u8; 56];
        // pkt_type = 0x0002 (Req).
        header[0] = 0x02;
        // text_length = 0x2000 LE at bytes 4..6.
        header[4] = 0x00;
        header[5] = 0x20;
        // msg_type = SHORT so the decoder would try to parse a body.
        header[31] = 0xC0;
        let mut buf = BytesMut::from(&header[..]);

        match codec.decode(&mut buf) {
            Err(Error::PduTooLarge { len, cap }) => {
                assert_eq!(len, 8192);
                assert_eq!(cap, MAX_TEXT_LENGTH);
            }
            other => panic!("expected PduTooLarge, got {other:?}"),
        }
    }
}
