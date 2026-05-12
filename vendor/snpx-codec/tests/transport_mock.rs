//! Mock-transport integration tests — spec §8.3.
#![allow(clippy::doc_markdown)]
//!
//! Drives the codec + client stack over a byte-level `tokio_test::io::Builder`
//! mock that scripts exact send/recv sequences. No sockets, no runtime
//! configuration — just the framing plus the client.
//!
//! Three scenarios (spec §8.3 / §10 acceptance):
//!
//! 1. `connect_srtp_and_read_r` — port 18245 single-packet handshake, then
//!    a `ReadSysWords{R, 5, 2}` round-trip returning `[de ad be ef]`.
//! 2. `connect_fanuc_snpx_and_read_r` — port 60008 two-packet handshake,
//!    then the same read.
//! 3. `write_do_bit_returns_write_ok` — write `DO184 = true` and verify the
//!    ACK is decoded as `Response::WriteOk`.

use bytes::BytesMut;
use futures_util::{SinkExt, StreamExt};
use tokio_test::io::{Builder, Mock};
use tokio_util::codec::{Encoder, Framed};

use snpx_codec::{
    BitSelector, Client, Error, Frame, FrameBody, MessageType, PacketType, PiggyBack, Port,
    Request, Response, SrtpCodec, Status, Transport, WordSelector,
};

/// `tokio_test::io::Mock` wrapped in a `Framed<_, SrtpCodec>`, exposed as a
/// [`Transport`]. Behaviourally identical to `TcpTransport` but backed by
/// a scripted byte stream rather than a real socket.
struct MockTransport {
    framed: Framed<Mock, SrtpCodec>,
}

impl MockTransport {
    fn new(mock: Mock) -> Self {
        Self {
            framed: Framed::new(mock, SrtpCodec),
        }
    }
}

#[async_trait::async_trait]
impl Transport for MockTransport {
    async fn call(&mut self, req: Frame) -> Result<Frame, Error> {
        self.framed.send(req).await?;
        match self.framed.next().await {
            Some(Ok(resp)) => Ok(resp),
            Some(Err(e)) => Err(e),
            None => Err(Error::Io(std::io::Error::new(
                std::io::ErrorKind::UnexpectedEof,
                "mock transport closed",
            ))),
        }
    }
}

/// Encode a [`Frame`] to owned `Vec<u8>` using the production `SrtpCodec`.
/// Used by tests to script the exact outbound bytes the codec will write.
fn encode_frame(frame: Frame) -> Vec<u8> {
    let mut codec = SrtpCodec;
    let mut buf = BytesMut::new();
    codec
        .encode(frame, &mut buf)
        .expect("codec encode for mock script");
    buf.to_vec()
}

/// Build a 56-byte INIT_ACK the controller would send in response to INIT.
/// Byte 0 = `0x01` per spec §3.8.
fn init_ack_bytes() -> Vec<u8> {
    let mut raw = [0u8; 56];
    raw[0] = 0x01;
    raw.to_vec()
}

/// Build a SHORT_ACK response frame carrying the given 6-byte inline
/// payload at the given sequence number.
fn short_ack_frame(seq: u16, inline: [u8; 6]) -> Frame {
    Frame {
        pkt_type: PacketType::ReqAck,
        seq_index: seq,
        text_length: 0,
        #[allow(clippy::cast_possible_truncation)]
        msg_seq: seq as u8,
        msg_type: MessageType::ShortAck,
        mbox_src: 0x0000_0E10,
        mbox_dst: 0,
        pkt_num: 1,
        total_pkt_num: 1,
        time: None,
        reserved_a: [0u8; 20],
        body: FrameBody::ShortAck {
            status: Status { major: 0, minor: 0 },
            inline_payload: inline,
            piggy: PiggyBack {
                prog_num: 0xFF,
                privilege: 0x02,
                sweep_ms: 0,
                status: 0x217C,
            },
        },
        extended: bytes::Bytes::new(),
    }
}

// ---------------------------------------------------------------------------

#[tokio::test]
async fn connect_srtp_and_read_r() {
    // Script both sides of the exchange:
    //   1. client sends 56-byte INIT → mock expects
    //   2. mock replies INIT_ACK (56 bytes, byte 0 = 0x01)
    //   3. client sends SHORT ReadSysMem(R, idx=4, count=2) → mock expects
    //   4. mock replies SHORT_ACK with inline [de ad be ef 00 00]
    let init_out = encode_frame(Frame::init());

    let read_req = Request::ReadSysWords {
        selector: WordSelector::R,
        addr: snpx_codec::FanucAddr::from_raw(5),
        count: 2,
    };
    // seq=1 because `Client::connect` leaves `next_seq = 1` after the handshake.
    let read_out = encode_frame(
        read_req
            .clone()
            .into_frame(1, 0, 0x0000_0E10)
            .expect("build frame"),
    );

    let ack_in = encode_frame(short_ack_frame(1, [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00]));

    let mock = Builder::new()
        .write(&init_out)
        .read(&init_ack_bytes())
        .write(&read_out)
        .read(&ack_in)
        .build();

    let transport = MockTransport::new(mock);
    let mut client = Client::connect(transport, Port::Srtp)
        .await
        .expect("connect");
    assert_eq!(client.port(), Port::Srtp);

    let resp = client.request(read_req).await.expect("read");
    match resp {
        Response::ReadWords { words } => {
            // Trimmed to 2 words = 4 bytes.
            assert_eq!(words.as_ref(), &[0xDE, 0xAD, 0xBE, 0xEF][..]);
        }
        other => panic!("expected ReadWords, got {other:?}"),
    }
}

#[tokio::test]
async fn connect_fanuc_snpx_and_read_r() {
    // Port-60008 two-packet init: INIT → INIT_ACK, then fanuc_hello →
    // some-ack (we fabricate a SHORT_ACK since the real shape isn't
    // firmly documented — spec §3.8 notes the ACK shape varies).
    let init_out = encode_frame(Frame::init());
    let hello_out = encode_frame(Frame::fanuc_hello());
    let hello_ack = encode_frame(short_ack_frame(1, [0u8; 6]));

    let read_req = Request::ReadSysWords {
        selector: WordSelector::R,
        addr: snpx_codec::FanucAddr::from_raw(5),
        count: 2,
    };
    let read_out = encode_frame(
        read_req
            .clone()
            .into_frame(1, 0, 0x0000_0E10)
            .expect("build frame"),
    );
    let ack_in = encode_frame(short_ack_frame(1, [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00]));

    let mock = Builder::new()
        .write(&init_out)
        .read(&init_ack_bytes())
        .write(&hello_out)
        .read(&hello_ack)
        .write(&read_out)
        .read(&ack_in)
        .build();

    let transport = MockTransport::new(mock);
    let mut client = Client::connect(transport, Port::FanucSnpx)
        .await
        .expect("connect");
    assert_eq!(client.port(), Port::FanucSnpx);

    let resp = client.request(read_req).await.expect("read");
    match resp {
        Response::ReadWords { words } => {
            assert_eq!(words.as_ref(), &[0xDE, 0xAD, 0xBE, 0xEF][..]);
        }
        other => panic!("expected ReadWords, got {other:?}"),
    }
}

#[tokio::test]
async fn write_do_bit_returns_write_ok() {
    let init_out = encode_frame(Frame::init());

    let write_req = Request::WriteSysBit {
        selector: BitSelector::I,
        addr: snpx_codec::FanucAddr::from_raw(184),
        value: true,
    };
    let write_out = encode_frame(
        write_req
            .clone()
            .into_frame(1, 0, 0x0000_0E10)
            .expect("build frame"),
    );
    // Canonical write-ACK shape: SHORT_ACK with empty inline payload.
    let ack_in = encode_frame(short_ack_frame(1, [0u8; 6]));

    let mock = Builder::new()
        .write(&init_out)
        .read(&init_ack_bytes())
        .write(&write_out)
        .read(&ack_in)
        .build();

    let transport = MockTransport::new(mock);
    let mut client = Client::connect(transport, Port::Srtp)
        .await
        .expect("connect");

    let resp = client.request(write_req).await.expect("write");
    assert_eq!(resp, Response::WriteOk);
}
