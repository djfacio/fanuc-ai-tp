//! `snpx-codec` — clean-room Rust implementation of the FANUC SNP-X-over-SRTP
//! wire protocol.
//!
//! This crate is a byte-layout-precise codec for the GE-SRTP framing that
//! FANUC R-30iB controllers expose on TCP ports 18245 and 60008. It mirrors
//! the `tokio-modbus` shape (a `tokio-util::codec::{Decoder, Encoder}`
//! feeding a `Transport` trait and a thin `Client` facade) without taking a
//! dependency on `tokio-modbus` code itself.
//!
//! The full specification — including the six open-source oracles this
//! implementation was reverse-engineered against — lives in
//! `docs/snpx-codec-spec.md`. Sections cited in source comments (e.g.
//! `§3.6`, `§7`) refer to that document.
//!
//! # Crate layout
//!
//! - [`addr`] — address-math helpers + [`FanucAddr`] newtype for
//!   1-based operator-visible addresses. Spec §7.
//! - [`enums`] — the four wire enums (`PacketType`, `MessageType`,
//!   `ServiceRequestCode`, `SegmentSelector`) plus the public `Port` enum.
//!   Spec §3.6–§3.8, §4.2.
//! - [`error`] — `Error` taxonomy + `Result` alias. Spec §4.4.
//! - [`frame`] — [`Frame`] / [`FrameBody`] / [`HeaderRaw`] — ergonomic
//!   and byte-exact views of the 56-byte SRTP header plus optional
//!   EXTENDED payload. Spec §4.0–§4.1, §5.
//! - [`codec`] — [`SrtpCodec`] implementing
//!   `tokio_util::codec::{Decoder, Encoder}`. Rejects oversize PDUs
//!   via [`MAX_TEXT_LENGTH`]. Spec §5.
//! - [`request`] / [`response`] — typed [`Request`] / [`Response`]
//!   ADTs — the caller-facing layer above raw frames. Spec §4.3.
//! - [`transport`] — [`Transport`] trait + [`TcpTransport`] wrapping
//!   `Framed<TcpStream, SrtpCodec>`. Spec §6.1.
//! - [`client`] — [`Client`] facade: runs the INIT handshake (plus
//!   the FANUC structured hello on port 60008), allocates sequence
//!   numbers, dispatches typed requests. Spec §6.
//!
//! # Wire format
//!
//! Every frame is a fixed 56-byte SRTP header followed by `text_length`
//! bytes of EXTENDED payload (zero for SHORT variants). Multi-byte
//! integers are little-endian. Wire enums live at fixed header
//! offsets; see [`frame::HeaderRaw`] for the byte-exact layout.
//!
//! The codec bounds `text_length` at [`MAX_TEXT_LENGTH`] (4 KiB per
//! spec §9.2 O-2). Requests and encoder both enforce this — there is
//! no silent truncation path.
//!
//! # Usage
//!
//! ```no_run
//! # async fn run() -> snpx_codec::Result<()> {
//! use snpx_codec::{Client, FanucAddr, Port, Request, TcpTransport, WordSelector};
//!
//! let transport = TcpTransport::connect("10.0.1.50:60008").await?;
//! let mut client = Client::connect(transport, Port::FanucSnpx).await?;
//!
//! let resp = client
//!     .request(Request::ReadSysWords {
//!         selector: WordSelector::R,
//!         addr: FanucAddr::from_raw(1),
//!         count: 4,
//!     })
//!     .await?;
//! # let _ = resp; Ok(()) }
//! ```

pub mod addr;
pub mod client;
pub mod codec;
pub mod enums;
pub mod error;
pub mod frame;
pub mod request;
pub mod response;
pub mod transport;

pub use addr::FanucAddr;
pub use client::Client;
pub use codec::{SrtpCodec, MAX_TEXT_LENGTH};
pub use enums::{MessageType, PacketType, Port, SegmentSelector, ServiceRequestCode};
pub use error::{Error, Result};
pub use frame::{Frame, FrameBody, HeaderRaw, PiggyBack, Status};
pub use request::{BitSelector, ByteSelector, Request, WordSelector};
pub use response::Response;
pub use transport::{TcpTransport, Transport};
