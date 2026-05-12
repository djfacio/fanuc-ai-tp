//! `Client` facade — the `tokio-modbus::Context`-shaped entry point.
//!
//! Spec §6.2. Wraps a [`Transport`] with:
//!
//! - sequence-number allocation (0 reserved, u16 wrap),
//! - INIT handshake (plus the FANUC structured hello on port 60008),
//! - typed request→response dispatch that narrows the generic
//!   [`Response`] shape returned by [`Response::from_frame`] into
//!   request-specific variants (`Time`, `Info`, `WriteOk`, `ReadBits`).
//!
//! The caller-facing surface is three methods:
//!
//! - [`Client::connect`] — run the handshake.
//! - [`Client::request`] — send a typed [`Request`] and get a typed
//!   [`Response`] back.
//! - [`Client::raw`] — escape hatch; send a [`Frame`] with no sequence
//!   tracking and no response typing. For callers who need finer control
//!   (multi-fragment extended responses, non-request packets).
//!
//! Spec §2.2: every `connect` / `request` call is wrapped in a
//! `tracing::instrument` span so operators can correlate log lines with
//! the FANUC opcode and the allocated sequence number.
#![allow(clippy::doc_markdown)]

use bytes::Bytes;

use crate::addr;
use crate::enums::{PacketType, Port};
use crate::error::{Error, Result};
use crate::frame::Frame;
use crate::request::Request;
use crate::response::Response;
use crate::transport::Transport;

/// Destination mailbox for the FANUC robot service. Spec §3.1
/// / `palatis:RobotIF.cs`. Present on every post-handshake outbound frame.
const MBOX_FANUC_ROBOT: u32 = 0x0000_0E10;

/// Client facade over a [`Transport`]. Generic over the transport type so
/// tests can plug in a mock without any I/O. Spec §6.2.
pub struct Client<T: Transport> {
    transport: T,
    /// Next sequence number to allocate. 0 is reserved per spec §6.2
    /// ("next_seq starts at 1, 0 reserved"), so the initial value is 1
    /// and wrap arithmetic skips 0.
    next_seq: u16,
    /// Source mailbox (header bytes 32..36) on outbound frames. Always
    /// zero for this client; spec §3.1 allows any value but no controller
    /// we've observed validates it.
    src_mbox: u32,
    /// Destination mailbox (header bytes 36..40) on outbound frames.
    /// Always `0x0000_0E10` for FANUC.
    dst_mbox: u32,
    /// The port kind we connected on — retained so callers can inspect it
    /// post-connect for diagnostic logging.
    port_kind: Port,
}

impl<T: Transport> Client<T> {
    /// Run the INIT handshake against a pre-connected transport.
    ///
    /// - Both ports: send the 56-byte all-zero [`Frame::init`] and expect
    ///   [`PacketType::InitAck`] back.
    /// - [`Port::FanucSnpx`] only: follow with the structured
    ///   [`Frame::fanuc_hello`]; the ACK shape varies across oracles so we
    ///   accept any non-error response.
    ///
    /// Does **not** run the Booozie-parity `%R[0] == 0x0100` link probe
    /// — that's callers' opt-in via [`Client::link_probe`].
    ///
    /// # Errors
    ///
    /// - [`Error::InitFailed`] if the first response isn't an `INIT_ACK`.
    /// - Any transport-layer error from [`Transport::call`].
    #[tracing::instrument(skip(transport), fields(port = ?port))]
    pub async fn connect(mut transport: T, port: Port) -> Result<Self> {
        // 1. 56-byte INIT.
        let ack = transport.call(Frame::init()).await?;
        if !matches!(ack.pkt_type, PacketType::InitAck) {
            return Err(Error::InitFailed(ack.raw_first_byte()));
        }

        // 2. Port-60008 FANUC structured hello. Spec §3.8: the ACK shape
        //    varies across oracles (Palatis, BiasedControls disagree on
        //    reserved bytes); absence of a transport error is sufficient.
        if matches!(port, Port::FanucSnpx) {
            let _hello_ack = transport.call(Frame::fanuc_hello()).await?;
        }

        Ok(Self {
            transport,
            next_seq: 1, // spec §6.2: 0 reserved
            src_mbox: 0,
            dst_mbox: MBOX_FANUC_ROBOT,
            port_kind: port,
        })
    }

    /// Return the port this client was opened on.
    #[must_use]
    pub fn port(&self) -> Port {
        self.port_kind
    }

    /// Send a typed [`Request`] and decode a typed [`Response`].
    ///
    /// This is the place where [`Response::from_frame`]'s generic shape
    /// (everything looks like `ReadWords` on `SHORT_ACK`) gets narrowed
    /// into the request-specific variant. See the dispatch table below.
    ///
    /// # Errors
    ///
    /// - [`Error::SeqMismatch`] if the response's `seq_index` doesn't
    ///   match the sequence number we allocated (skipped for
    ///   [`Request::Init`], which predates any session state).
    /// - [`Error::InvalidRequest`] from [`Request::into_frame`] on
    ///   self-inconsistent inputs.
    /// - Any error surfaced by the transport or response decoder.
    #[tracing::instrument(skip(self, req), fields(seq = self.next_seq, svc = ?req.service_code()))]
    pub async fn request(&mut self, req: Request) -> Result<Response> {
        // Remember what we dispatched — needed post-decode to remap
        // generic responses into typed variants (Time, Info, WriteOk, ...).
        // `Request: Clone` makes this cheap: `Bytes` is refcounted, enums
        // are `Copy`-friendly.
        let dispatched = req.clone();

        // Special-case INIT: seq number isn't applicable because the
        // handshake pre-dates session state. This path exists for
        // completeness; `connect` is the usual entry point.
        let is_init = matches!(dispatched, Request::Init);
        let seq = if is_init { 0 } else { self.take_seq() };

        let frame = req.into_frame(seq, self.src_mbox, self.dst_mbox)?;
        let resp_frame = self.transport.call(frame).await?;

        // Spec §6.2: the controller echoes the sequence number. Skip for
        // INIT (the response is an INIT_ACK with seq_index = 0).
        if !is_init && resp_frame.seq_index != seq {
            return Err(Error::SeqMismatch {
                sent: seq,
                got: resp_frame.seq_index,
            });
        }

        let generic = Response::from_frame(resp_frame)?;
        narrow_response(&dispatched, generic)
    }

    /// Escape hatch: send a [`Frame`] as-is, with no sequence tracking or
    /// response typing.
    ///
    /// The caller owns seq allocation and body interpretation. Useful for
    /// tests, diagnostics, and any future feature (multi-fragment writes,
    /// non-request packets) that outgrows the typed dispatch.
    ///
    /// # Errors
    ///
    /// Any [`Error`] surfaced by the transport.
    pub async fn raw(&mut self, frame: Frame) -> Result<Frame> {
        self.transport.call(frame).await
    }

    /// Booozie-parity liveness check: read `%R[0]` and expect the u16
    /// value `0x0100`.
    ///
    /// Spec §3.8 / `robot_comm.py:16-20`. `%R[0]` content is
    /// site-dependent, not a protocol guarantee — callers who want a
    /// generic "is it alive?" should prefer `Client::request(Request::GetTime)`
    /// round-tripping.
    ///
    /// # Errors
    ///
    /// - [`Error::LinkProbeMismatch`] if the probe returned anything other
    ///   than `0x0100` (little-endian).
    /// - Anything surfaced by [`Client::request`].
    pub async fn link_probe(&mut self) -> Result<()> {
        let resp = self
            .request(Request::ReadSysWords {
                selector: crate::request::WordSelector::R,
                addr: crate::FanucAddr::from_raw(0),
                count: 1,
            })
            .await?;
        match resp {
            Response::ReadWords { words } if words.len() >= 2 => {
                let got = u16::from_le_bytes([words[0], words[1]]);
                if got == 0x0100 {
                    Ok(())
                } else {
                    Err(Error::LinkProbeMismatch { got })
                }
            }
            Response::ReadWords { words } => {
                // Fewer than 2 bytes back — treat as a mismatch against 0.
                let got = if let Some(b) = words.first() {
                    u16::from(*b)
                } else {
                    0
                };
                Err(Error::LinkProbeMismatch { got })
            }
            // Anything else (errors, wrong-shape responses) collapses to
            // a single-signal LinkProbeMismatch so callers only handle
            // one error variant.
            _ => Err(Error::LinkProbeMismatch { got: 0 }),
        }
    }

    /// Allocate the next sequence number. 0 is reserved (spec §6.2), so
    /// the wrap from `0xFFFF` skips straight to `1`.
    fn take_seq(&mut self) -> u16 {
        let s = self.next_seq;
        // Wrap and skip zero in one step. `wrapping_add(1)` then `.max(1)`
        // yields `1` when we would have hit 0.
        self.next_seq = self.next_seq.wrapping_add(1).max(1);
        s
    }
}

/// Narrow a generic [`Response`] (as classified by
/// [`Response::from_frame`]) into the request-specific variant.
///
/// The dispatch table:
///
/// | Dispatched [`Request`]       | Generic [`Response`]          | Narrowed result                                  |
/// |------------------------------|-------------------------------|--------------------------------------------------|
/// | `Init`                       | anything                      | `InitOk`                                         |
/// | `ReadSysWords { count }`     | `ReadWords { words }`         | `ReadWords { words: words[..2*count] }`          |
/// | `WriteSysWords { .. }`       | `ReadWords { .. }` / `WriteOk`| `WriteOk`                                        |
/// | `ReadSysBits { addr, count }`| `ReadBits { bits }`           | `ReadBits { bits: slice+masked via bit_read_range}`|
/// | `WriteSysBit { .. }`         | `ReadWords { .. }` / `WriteOk`| `WriteOk`                                        |
/// | `GetTime`                    | `ReadWords { words }`         | `Time { ss, mm, hh }` — see note                 |
/// | `GetInfo`                    | `ReadWords { words }`         | `Info { raw: words }`                            |
///
/// Any `Response::Error` passes through unchanged.
fn narrow_response(dispatched: &Request, generic: Response) -> Result<Response> {
    // Errors pass through regardless of what we dispatched.
    if let Response::Error { .. } = &generic {
        return Ok(generic);
    }

    match dispatched {
        Request::Init => Ok(Response::InitOk),

        Request::ReadSysWords { count, .. } => match generic {
            Response::ReadWords { words } => {
                // Codex P2-7: a short response silently became data.
                // Surface as `Error::TruncatedRead` so the link layer
                // can flip the group quality to Unavailable instead
                // of publishing "zero words we didn't really read."
                let wanted = usize::from(*count) * 2;
                if words.len() < wanted {
                    return Err(Error::TruncatedRead {
                        op: "read_words",
                        expected: wanted,
                        actual: words.len(),
                    });
                }
                Ok(Response::ReadWords {
                    words: words.slice(..wanted),
                })
            }
            other => Ok(other),
        },

        Request::WriteSysWords { .. }
        | Request::WriteSysBit { .. }
        | Request::WriteSysBytes { .. } => {
            // Spec §3.3 note: write ACKs come back as SHORT_ACK with an
            // inline payload of 6 zero bytes. `from_frame` can't tell
            // that apart from a 3-word read of zeros, so we remap here.
            Ok(match generic {
                Response::ReadWords { .. } | Response::WriteOk => Response::WriteOk,
                other => other,
            })
        }

        Request::ReadSysBits {
            addr,
            count,
            selector: _,
        } => match generic {
            Response::ReadBits { bits } => mask_read_bits(&bits, addr.get(), *count),
            Response::ReadWords { words } => {
                // Short-ACK path: bits returned inline as 6 bytes.
                mask_read_bits(&words, addr.get(), *count)
            }
            other => Ok(other),
        },

        Request::GetTime => match generic {
            Response::ReadWords { words } if words.len() >= 3 => {
                // TODO(live-capture): verify GetTime response byte order.
                // Spec §3.1 says the outbound time field is
                // (seconds, minutes, hours) at bytes 26..29 LE. Palatis's
                // `PacketBase.cs:43-45` matches that for the outbound
                // layout. The inbound `GetTime` reply's byte order is not
                // firmly documented by any oracle — we default to the same
                // (ss, mm, hh) layout until a live capture disambiguates.
                Ok(Response::Time {
                    hh: words[2],
                    mm: words[1],
                    ss: words[0],
                })
            }
            Response::ReadWords { words } => Err(Error::TruncatedRead {
                op: "get_time",
                expected: 6,
                actual: words.len(),
            }),
            other => Ok(other),
        },

        Request::GetInfo => Ok(match generic {
            Response::ReadWords { words } => Response::Info { raw: words },
            other => other,
        }),
    }
}

/// Mask a byte-aligned `ReadSysBits` response down to exactly the bits the
/// caller asked for. Uses [`addr::bit_read_range`] to recompute the
/// byte-alignment offset, then slices the window + masks the tail.
///
/// The output length is `ceil(count / 8)` bytes, with the first byte's
/// low-order bits aligned to the caller's first requested bit.
fn mask_read_bits(src: &Bytes, addr: u16, count: u16) -> Result<Response> {
    // Request construction already validated the address math via
    // `to_wire`; if that path accepted this `(addr, count)` pair, the
    // window cannot overflow here. Keep the expect as load-bearing
    // documentation of that invariant.
    let (_first, _aligned_bits, offset) = addr::bit_read_range(addr, count)?;

    // The aligned window is `src` verbatim — the caller's first bit sits
    // at bit `offset` inside `src[0]`. We shift each byte right by
    // `offset` and pull in the high bits from the next byte.
    let bits_needed = usize::from(count);
    let out_bytes = bits_needed.div_ceil(8);
    let mut out = Vec::with_capacity(out_bytes);

    let shift = u32::from(offset);
    if shift == 0 {
        // Fast path: already aligned. Need at least `out_bytes` bytes
        // in the response; codex P2-7 — silently zero-padding used to
        // hide mapping corruption.
        if src.len() < out_bytes {
            return Err(Error::TruncatedRead {
                op: "read_bits",
                expected: out_bytes,
                actual: src.len(),
            });
        }
        out.extend(src.iter().take(out_bytes).copied());
    } else {
        // Offset path: need one extra byte for the high-bit pull-in on
        // the last output byte.
        if src.len() < out_bytes + 1 {
            return Err(Error::TruncatedRead {
                op: "read_bits",
                expected: out_bytes + 1,
                actual: src.len(),
            });
        }
        for i in 0..out_bytes {
            let lo = src[i];
            let hi = src[i + 1];
            // Shift: low byte >> offset, OR with high byte << (8 - offset).
            // All shift amounts are < 8 so u8 arithmetic is exact.
            let shifted: u8 = (lo >> shift) | (hi << (8 - shift));
            out.push(shifted);
        }
    }

    // Mask the tail: clear bits above `count` in the last byte.
    let tail_bits = bits_needed % 8;
    if tail_bits != 0 {
        if let Some(last) = out.last_mut() {
            let mask: u8 = (1u8 << tail_bits) - 1;
            *last &= mask;
        }
    }

    Ok(Response::ReadBits {
        bits: Bytes::from(out),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::enums::{MessageType, SegmentSelector, ServiceRequestCode};
    use crate::frame::{FrameBody, PiggyBack, Status};
    use crate::request::{BitSelector, WordSelector};
    use std::collections::VecDeque;

    /// Scripted transport: each entry is `(expected_outbound, scripted_response)`.
    /// `call` pops the front, asserts the outbound matches, returns the
    /// scripted response.
    struct MockTransport {
        script: VecDeque<(Frame, Frame)>,
    }

    impl MockTransport {
        fn new(script: Vec<(Frame, Frame)>) -> Self {
            Self {
                script: script.into(),
            }
        }
    }

    #[async_trait::async_trait]
    impl Transport for MockTransport {
        async fn call(&mut self, req: Frame) -> Result<Frame> {
            let (expect, resp) = self.script.pop_front().expect("empty mock script");
            assert_eq!(req, expect, "unexpected outbound frame");
            Ok(resp)
        }
    }

    /// Build an `INIT_ACK` response frame. Byte 0 of `raw` is `0x01`.
    fn init_ack_frame() -> Frame {
        let mut raw = [0u8; 56];
        raw[0] = 0x01;
        Frame {
            pkt_type: PacketType::InitAck,
            seq_index: 0,
            text_length: 0,
            msg_seq: 0,
            msg_type: MessageType::Short, // ignored for InitAck
            mbox_src: 0,
            mbox_dst: 0,
            pkt_num: 0,
            total_pkt_num: 0,
            time: None,
            reserved_a: [0u8; 20],
            body: FrameBody::InitAck { raw },
            extended: Bytes::new(),
        }
    }

    /// Build a SHORT_ACK response for sequence `seq` carrying the given
    /// 6-byte inline payload.
    fn short_ack_frame(seq: u16, inline: [u8; 6]) -> Frame {
        Frame {
            pkt_type: PacketType::ReqAck,
            seq_index: seq,
            text_length: 0,
            msg_seq: (seq & 0xFF) as u8,
            msg_type: MessageType::ShortAck,
            mbox_src: 0,
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
                    privilege: 0,
                    sweep_ms: 0,
                    status: 0x217C,
                },
            },
            extended: Bytes::new(),
        }
    }

    #[tokio::test]
    async fn connect_srtp_sends_init_only() {
        let script = vec![(Frame::init(), init_ack_frame())];
        let transport = MockTransport::new(script);
        let client = Client::connect(transport, Port::Srtp)
            .await
            .expect("connect");
        assert_eq!(client.port(), Port::Srtp);
        assert_eq!(client.next_seq, 1);
    }

    #[tokio::test]
    async fn connect_fanuc_snpx_sends_init_then_hello() {
        // Hello ACK: any non-error response. We fabricate a SHORT_ACK
        // because the real controller replies with *something*; the
        // exact shape is oracle-dependent.
        let hello_ack = short_ack_frame(1, [0; 6]);
        let script = vec![
            (Frame::init(), init_ack_frame()),
            (Frame::fanuc_hello(), hello_ack),
        ];
        let transport = MockTransport::new(script);
        let client = Client::connect(transport, Port::FanucSnpx)
            .await
            .expect("connect");
        assert_eq!(client.port(), Port::FanucSnpx);
    }

    #[tokio::test]
    async fn connect_rejects_wrong_init_ack() {
        // Script the controller replying with a `PacketType::Init`
        // instead of `InitAck`. First byte of `pkt_type` LE is 0x00.
        let mut bad = Frame::init();
        bad.pkt_type = PacketType::Init;
        bad.body = FrameBody::Init;
        let script = vec![(Frame::init(), bad)];
        let transport = MockTransport::new(script);
        // Can't use `.expect_err`: `Client<MockTransport>` doesn't impl
        // `Debug`. Match on the Result directly.
        match Client::connect(transport, Port::Srtp).await {
            Err(Error::InitFailed(b)) => assert_eq!(b, 0x00),
            Err(other) => panic!("expected InitFailed, got {other:?}"),
            Ok(_) => panic!("expected Err, got Ok"),
        }
    }

    #[tokio::test]
    async fn request_read_sys_words_round_trips() {
        // Build: connect, then ReadSysWords { R, 5, 2 } at seq=1.
        let req = Request::ReadSysWords {
            selector: WordSelector::R,
            addr: crate::FanucAddr::from_raw(5),
            count: 2,
        };
        let expected_outbound = req
            .clone()
            .into_frame(1, 0, MBOX_FANUC_ROBOT)
            .expect("build frame");

        // Scripted response: 4 bytes of data (2 u16 LE values), padded to
        // the full 6-byte inline payload.
        let resp = short_ack_frame(1, [0xD2, 0x04, 0x01, 0x00, 0x00, 0x00]);

        let script = vec![(Frame::init(), init_ack_frame()), (expected_outbound, resp)];
        let transport = MockTransport::new(script);
        let mut client = Client::connect(transport, Port::Srtp)
            .await
            .expect("connect");

        let got = client.request(req).await.expect("request");
        match got {
            Response::ReadWords { words } => {
                // Trimmed to 2 words = 4 bytes.
                assert_eq!(words.as_ref(), &[0xD2, 0x04, 0x01, 0x00][..]);
            }
            other => panic!("expected ReadWords, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn request_write_sys_words_returns_write_ok() {
        let req = Request::WriteSysWords {
            selector: WordSelector::R,
            addr: crate::FanucAddr::from_raw(1),
            words: Bytes::from_static(&[0xD2, 0x04]),
        };
        let expected_outbound = req
            .clone()
            .into_frame(1, 0, MBOX_FANUC_ROBOT)
            .expect("build frame");

        // Empty-inline SHORT_ACK is the canonical write-ACK shape.
        let resp = short_ack_frame(1, [0; 6]);

        let script = vec![(Frame::init(), init_ack_frame()), (expected_outbound, resp)];
        let transport = MockTransport::new(script);
        let mut client = Client::connect(transport, Port::Srtp)
            .await
            .expect("connect");

        let got = client.request(req).await.expect("request");
        assert_eq!(got, Response::WriteOk);
    }

    #[tokio::test]
    async fn request_write_sys_bit_builds_extended_and_returns_write_ok() {
        let req = Request::WriteSysBit {
            selector: BitSelector::I,
            addr: crate::FanucAddr::from_raw(184),
            value: true,
        };
        let expected_outbound = req
            .clone()
            .into_frame(1, 0, MBOX_FANUC_ROBOT)
            .expect("build frame");

        // Sanity-assert the outbound shape before we even run the client.
        match &expected_outbound.body {
            FrameBody::Extended {
                svc_req_code,
                seg_selector,
                target_index,
                target_count,
                ..
            } => {
                assert_eq!(*svc_req_code, ServiceRequestCode::WriteSysMem);
                assert_eq!(*seg_selector, SegmentSelector::BitI);
                assert_eq!(*target_index, 183);
                assert_eq!(*target_count, 1);
            }
            other => panic!("expected Extended body, got {other:?}"),
        }
        assert_eq!(expected_outbound.extended.as_ref(), &[0x80u8][..]);

        let resp = short_ack_frame(1, [0; 6]);
        let script = vec![(Frame::init(), init_ack_frame()), (expected_outbound, resp)];
        let transport = MockTransport::new(script);
        let mut client = Client::connect(transport, Port::Srtp)
            .await
            .expect("connect");

        let got = client.request(req).await.expect("request");
        assert_eq!(got, Response::WriteOk);
    }

    #[tokio::test]
    async fn request_seq_mismatch_errors() {
        let req = Request::ReadSysWords {
            selector: WordSelector::R,
            addr: crate::FanucAddr::from_raw(1),
            count: 1,
        };
        let expected_outbound = req
            .clone()
            .into_frame(1, 0, MBOX_FANUC_ROBOT)
            .expect("build frame");
        // Reply with a different sequence number.
        let resp = short_ack_frame(42, [0; 6]);

        let script = vec![(Frame::init(), init_ack_frame()), (expected_outbound, resp)];
        let transport = MockTransport::new(script);
        let mut client = Client::connect(transport, Port::Srtp)
            .await
            .expect("connect");

        let err = client.request(req).await.expect_err("seq mismatch");
        match err {
            Error::SeqMismatch { sent, got } => {
                assert_eq!(sent, 1);
                assert_eq!(got, 42);
            }
            other => panic!("expected SeqMismatch, got {other:?}"),
        }
    }

    #[test]
    fn take_seq_wraps_past_u16_max() {
        // Direct unit test on the seq allocator. Build a minimal client
        // with a no-op transport so we can poke `next_seq`.
        struct NoOp;
        #[async_trait::async_trait]
        impl Transport for NoOp {
            async fn call(&mut self, _req: Frame) -> Result<Frame> {
                unreachable!()
            }
        }
        let mut client: Client<NoOp> = Client {
            transport: NoOp,
            next_seq: 0xFFFF,
            src_mbox: 0,
            dst_mbox: MBOX_FANUC_ROBOT,
            port_kind: Port::Srtp,
        };
        let a = client.take_seq();
        assert_eq!(a, 0xFFFF);
        let b = client.take_seq();
        // Wraps to 0, skipped to 1.
        assert_eq!(b, 1);
    }
}
