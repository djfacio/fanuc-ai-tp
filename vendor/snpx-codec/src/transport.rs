//! Async transport abstraction — object-safe trait + TCP implementation.
//!
//! Spec §6.1. The `Transport` trait is a single-method async interface:
//! "send a `Frame`, await the paired response". `TcpTransport` wraps
//! `Framed<TcpStream, SrtpCodec>` as the production implementation. Tests
//! plug in a mock transport (see `client.rs`) without any real I/O.
#![allow(clippy::doc_markdown)]

use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::net::{TcpStream, ToSocketAddrs};
use tokio_util::codec::Framed;

use crate::codec::SrtpCodec;
use crate::error::Error;
use crate::frame::Frame;

/// Default per-`call` deadline. Spec §3.7 requires every request to have
/// a timeout; 5 s is generous for a warm SNP-X round-trip (<100 ms
/// typical against a healthy controller) while still surfacing a
/// blackholed link long before the service-level supervisor restarts.
pub const DEFAULT_CALL_TIMEOUT: Duration = Duration::from_secs(5);

/// Default TCP connect deadline. A healthy FANUC controller on a wired
/// LAN ACKs the SYN within a few hundred milliseconds; 3 s lets retries
/// through NAT / switch convergence without wedging the io-loop.
pub const DEFAULT_CONNECT_TIMEOUT: Duration = Duration::from_secs(3);

/// Async transport abstraction. One method: send a [`Frame`], await the
/// paired response [`Frame`].
///
/// Implementations own the framing. The default [`TcpTransport`] wraps
/// `Framed<TcpStream, SrtpCodec>`; test doubles can implement this
/// directly without touching tokio's I/O traits.
///
/// `Send` bound lets callers move the transport across task boundaries.
/// Object-safety requires the `async-trait` crate: without it, the desugared
/// `impl Future` return type would bake in a type parameter, blocking
/// `Box<dyn Transport>`.
#[async_trait::async_trait]
pub trait Transport: Send {
    /// Send `req` as the next outbound frame and await the controller's
    /// next inbound frame. Pairing is strictly ordered — the caller is
    /// responsible for never interleaving requests on one transport.
    ///
    /// # Errors
    ///
    /// Any [`Error`] reported by the underlying codec or I/O stack.
    async fn call(&mut self, req: Frame) -> Result<Frame, Error>;
}

/// TCP implementation of [`Transport`]. Wraps [`TcpStream`] in a
/// [`Framed`] adapter running the [`SrtpCodec`].
///
/// Construct via [`TcpTransport::connect`]. Callers can plumb Nagle / keepalive
/// /timeouts on the underlying socket before wrapping — see
/// [`TcpTransport::into_inner`] / [`TcpTransport::get_ref`] if extended
/// configuration is needed later.
pub struct TcpTransport {
    framed: Framed<TcpStream, SrtpCodec>,
    /// Per-[`Transport::call`] deadline. Defaults to
    /// [`DEFAULT_CALL_TIMEOUT`]; override via [`TcpTransport::with_call_timeout`].
    call_timeout: Duration,
}

impl TcpTransport {
    /// Connect to the controller on the given TCP endpoint with the
    /// default connect timeout ([`DEFAULT_CONNECT_TIMEOUT`]).
    ///
    /// Does **not** run the SRTP / FANUC INIT handshake — that lives in
    /// [`crate::client::Client::connect`]. This constructor only opens the
    /// socket.
    ///
    /// # Errors
    ///
    /// - [`Error::Timeout`] if the TCP handshake doesn't complete within
    ///   the configured deadline.
    /// - [`Error::Io`] if the TCP connect fails for any other reason.
    pub async fn connect(addr: impl ToSocketAddrs) -> Result<Self, Error> {
        Self::connect_with_timeout(addr, DEFAULT_CONNECT_TIMEOUT).await
    }

    /// Connect with an explicit deadline. Spec §3.7: every bounded
    /// operation has a timeout.
    ///
    /// # Errors
    ///
    /// Same taxonomy as [`TcpTransport::connect`].
    pub async fn connect_with_timeout(
        addr: impl ToSocketAddrs,
        connect_timeout: Duration,
    ) -> Result<Self, Error> {
        let stream = tokio::time::timeout(connect_timeout, TcpStream::connect(addr))
            .await
            .map_err(|_| Error::Timeout {
                op: "connect",
                millis: duration_to_millis(connect_timeout),
            })??;
        Ok(Self {
            framed: Framed::new(stream, SrtpCodec),
            call_timeout: DEFAULT_CALL_TIMEOUT,
        })
    }

    /// Override the per-call deadline. Chainable; returns `self`.
    #[must_use]
    pub fn with_call_timeout(mut self, call_timeout: Duration) -> Self {
        self.call_timeout = call_timeout;
        self
    }

    /// The per-call deadline currently in effect.
    #[must_use]
    pub fn call_timeout(&self) -> Duration {
        self.call_timeout
    }

    /// Borrow the underlying framed adapter, for operators that need to
    /// inspect the socket state (peer address, TCP options).
    #[must_use]
    pub fn get_ref(&self) -> &Framed<TcpStream, SrtpCodec> {
        &self.framed
    }

    /// Consume self and return the inner [`Framed`] adapter. Escape hatch
    /// for callers that want to apply Sink / Stream combinators directly
    /// or to reclaim the underlying [`TcpStream`].
    #[must_use]
    pub fn into_inner(self) -> Framed<TcpStream, SrtpCodec> {
        self.framed
    }
}

#[async_trait::async_trait]
impl Transport for TcpTransport {
    async fn call(&mut self, req: Frame) -> Result<Frame, Error> {
        // `SinkExt::send` drives the codec through a full flush cycle;
        // we never pipeline. The send + next pair is wrapped in a single
        // deadline — a slow-read controller that never returns bytes
        // must surface as [`Error::Timeout`] instead of wedging the
        // io-loop (codex P1-3, spec §3.7).
        let deadline = self.call_timeout;
        let fut = async {
            self.framed.send(req).await?;
            match self.framed.next().await {
                Some(Ok(resp)) => Ok(resp),
                Some(Err(e)) => Err(e),
                None => Err(Error::Io(std::io::Error::new(
                    std::io::ErrorKind::UnexpectedEof,
                    "transport closed",
                ))),
            }
        };
        match tokio::time::timeout(deadline, fut).await {
            Ok(res) => res,
            Err(_) => Err(Error::Timeout {
                op: "call",
                millis: duration_to_millis(deadline),
            }),
        }
    }
}

fn duration_to_millis(d: Duration) -> u64 {
    u64::try_from(d.as_millis()).unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Smoke test: `Transport` is object-safe. This compiles only if the
    /// trait's methods don't refer to `Self` in a position that breaks
    /// dyn-dispatch. `async-trait` is the enabler.
    #[test]
    fn transport_trait_is_object_safe() {
        struct NoOpTransport;
        #[async_trait::async_trait]
        impl Transport for NoOpTransport {
            async fn call(&mut self, _req: Frame) -> Result<Frame, Error> {
                unreachable!("compile-only test")
            }
        }
        let _obj: Box<dyn Transport> = Box::new(NoOpTransport);
    }

    /// Codex P1-3: a controller that accepts TCP but never replies must
    /// surface `Error::Timeout`, not block the caller. Bind a listener,
    /// accept but never write, verify `call()` returns a timeout inside
    /// the configured deadline. Uses a real timer (not `start_paused`)
    /// because the test needs the actual socket connect to complete
    /// before the paused call timer would advance.
    #[tokio::test(flavor = "current_thread")]
    async fn call_times_out_on_unresponsive_peer() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        // Accept + hold in a background task; never send anything.
        let accept_task = tokio::spawn(async move {
            let (sock, _) = listener.accept().await.unwrap();
            // Park the socket; it's dropped when this task ends.
            std::mem::forget(sock);
        });

        let mut transport = TcpTransport::connect_with_timeout(addr, Duration::from_secs(1))
            .await
            .unwrap()
            .with_call_timeout(Duration::from_millis(250));

        let err = transport
            .call(Frame::init())
            .await
            .expect_err("must time out against a silent peer");
        match err {
            Error::Timeout { op, .. } => assert_eq!(op, "call"),
            other => panic!("expected Timeout, got {other:?}"),
        }
        drop(accept_task);
    }

    /// A very short connect timeout against a non-routable address must
    /// surface `Error::Timeout { op: "connect", .. }` rather than hang.
    /// Uses TEST-NET-2 (`198.51.100.0/24` per RFC 5737) which is
    /// reserved for documentation and will not route.
    #[tokio::test(flavor = "current_thread")]
    async fn connect_times_out_on_unroutable_address() {
        let result =
            TcpTransport::connect_with_timeout("198.51.100.1:60008", Duration::from_millis(100))
                .await;
        match result {
            Ok(_) => panic!("unroutable address must not succeed"),
            Err(Error::Timeout { op, .. }) => assert_eq!(op, "connect"),
            // Some network stacks return Io::HostUnreachable immediately;
            // accept either as a non-hang.
            Err(Error::Io(_)) => {}
            Err(other) => panic!("expected Timeout or Io, got {other:?}"),
        }
    }
}
