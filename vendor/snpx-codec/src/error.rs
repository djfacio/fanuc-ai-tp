//! Error taxonomy for the SRTP codec. Spec §4.4.
//!
//! Follows `tokio-modbus`'s split of `TransportError` + `ProtocolError` +
//! `IoError` but flattened: the SRTP surface is smaller than Modbus, and
//! every variant here is reachable from either the codec or the client
//! layer without a further nesting level.

/// Errors reported by `snpx-codec`. Every variant is reachable either from
/// the `Decoder`/`Encoder` or from the `Client` facade.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// Underlying `std::io::Error` — TCP read/write, connect, etc.
    #[error("io: {0}")]
    Io(#[from] std::io::Error),

    /// A `Decoder` call saw fewer bytes than a full frame would need.
    /// Surfaced after the codec-layer short-read retries are exhausted.
    #[error("frame too short: need {need} bytes, have {have}")]
    FrameTooShort {
        /// Minimum number of bytes required to make progress.
        need: usize,
        /// Bytes actually available in the input buffer.
        have: usize,
    },

    /// The `text_length` header field (bytes 4-5) exceeds the crate's
    /// per-PDU cap. Default cap is 4 KiB; see spec §9.2 open question O-2.
    #[error("text_length {len} exceeds cap {cap}")]
    PduTooLarge {
        /// The `text_length` value read from the wire.
        len: u16,
        /// The cap the codec rejected against.
        cap: u16,
    },

    /// A u8/u16 discriminant didn't match any variant of the wire enum at
    /// that offset (`PacketType`, `MessageType`, `ServiceRequestCode`,
    /// `SegmentSelector`).
    #[error("unknown discriminant in {field}: {value:#06x}")]
    UnknownDiscriminant {
        /// Static name of the field — e.g. `"msg_type"` or `"svc_req_code"`.
        field: &'static str,
        /// The raw discriminant. Held as `u32` so a single variant covers
        /// both u8 and u16 wire enums.
        value: u32,
    },

    /// A multi-packet response arrived (`total_pkt_num > 1`) but the
    /// decoder is not yet configured to reassemble it. Spec §6.3, §9.2 O-3.
    #[error("unsupported multi-packet response (pkt {pkt}/{total})")]
    MultiPacketUnsupported {
        /// Fragment index, 1-based.
        pkt: u8,
        /// Total number of fragments the sender announced.
        total: u8,
    },

    /// The 56-byte `INIT` handshake was acknowledged, but byte 0 of the
    /// response wasn't `0x01`. Spec §3.8.
    #[error("init handshake failed: first byte of INIT_ACK was {0:#04x} (expected 0x01)")]
    InitFailed(u8),

    /// The optional Booozie-style `%R[0] == 0x0100` liveness probe failed.
    /// Spec §3.8 / §6.2 `Client::link_probe`.
    #[error("link-alive probe returned {got}, expected 0x0100")]
    LinkProbeMismatch {
        /// The u16 value the controller returned.
        got: u16,
    },

    /// A `SHORT_ERR` (`msg_type = 0xD1`) response. The full 14-byte body
    /// is preserved so callers can inspect the FANUC-specific layout
    /// (currently undocumented; spec §9.2 O-1).
    #[error("protocol error response body={body:02x?}")]
    Protocol {
        /// The opaque 14-byte response body at header offsets 42..56.
        body: [u8; 14],
    },

    /// The `seq_index` in the response didn't match the one the client
    /// sent. Spec §6.2.
    #[error("sequence mismatch: sent {sent}, got {got}")]
    SeqMismatch {
        /// The sequence number this client allocated on the outbound frame.
        sent: u16,
        /// The sequence number echoed by the controller.
        got: u16,
    },

    /// The caller-provided `Request` value is self-inconsistent — for
    /// example, a word write whose byte-count is odd. Raised by
    /// `Request::into_frame` *before* any wire bytes are emitted.
    #[error("invalid request: {0}")]
    InvalidRequest(&'static str),

    /// A bounded operation (`connect`, `call`) exceeded its deadline.
    /// Spec §3.7: every request has a timeout. A blackholed controller
    /// must surface here, not wedge the IO loop.
    #[error("timeout: {op} exceeded {millis} ms")]
    Timeout {
        /// Static name of the operation — `"connect"` or `"call"`.
        op: &'static str,
        /// Deadline that was exceeded, in milliseconds.
        millis: u64,
    },

    /// The controller returned a well-formed response, but its payload
    /// is shorter than the caller's request required. Surfaces the
    /// silent-zero failure mode codex flagged: `ReadSysWords` used to
    /// trim to the shorter buffer, and `ReadSysBits::mask_read_bits`
    /// used to pad missing bytes with zero — both paths would return
    /// `Ok` with partially-fabricated data.
    #[error("truncated read: {op} expected {expected} bytes, got {actual}")]
    TruncatedRead {
        /// Operation tag — `"read_words"` or `"read_bits"`.
        op: &'static str,
        /// Bytes the request declared it wanted.
        expected: usize,
        /// Bytes the controller actually returned.
        actual: usize,
    },
}

/// Crate-local `Result` alias. Every public fallible operation returns
/// this.
pub type Result<T> = std::result::Result<T, Error>;
