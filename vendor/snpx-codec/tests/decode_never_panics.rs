//! §13.5 scenario 4: "Malformed frame injection: codec never panics."
//!
//! Stable-CI proptest that feeds arbitrary byte sequences into
//! `SrtpCodec::decode` and asserts the call cannot panic. The
//! nightly libfuzzer target at `fuzz/fuzz_targets/codec_decode.rs`
//! covers the same property with coverage-guided input; this test
//! ships the guarantee inside the default `cargo test` gate so
//! regressions fail before merge.
//!
//! Also covers §13.3 property: "malformed input never panics."

use bytes::BytesMut;
use proptest::collection::vec as pvec;
use proptest::prelude::*;

use snpx_codec::SrtpCodec;
use tokio_util::codec::Decoder;

proptest! {
    // Larger tree and more cases than the default; this is the one
    // guarantee that has to hold on genuinely random bytes, not just
    // round-trippable frames.
    #![proptest_config(ProptestConfig::with_cases(4096))]

    /// Arbitrary bytes, one-shot decode call.
    #[test]
    fn decode_arbitrary_bytes_never_panics(data in pvec(any::<u8>(), 0..=4096)) {
        let mut codec = SrtpCodec;
        let mut buf = BytesMut::from(&data[..]);
        // We don't care about the result — only that it doesn't panic
        // and that `Ok(None)` leaves the buffer untouched (contract
        // with the `Framed` driver in `LinkActor`).
        let before = buf.len();
        if let Ok(None) = codec.decode(&mut buf) {
            prop_assert_eq!(buf.len(), before);
        }
    }

    /// Streaming drive: decode in a loop until the buffer drains or
    /// returns an error. Mirrors how `Framed` calls the codec over a
    /// TCP stream. This is where partial-frame / length-prefix bugs
    /// surface as panics.
    #[test]
    fn streaming_decode_drains_without_panic(data in pvec(any::<u8>(), 0..=4096)) {
        let mut codec = SrtpCodec;
        let mut buf = BytesMut::from(&data[..]);
        for _ in 0..64 {
            let before = buf.len();
            match codec.decode(&mut buf) {
                Ok(None) => {
                    prop_assert_eq!(buf.len(), before);
                    break;
                }
                Ok(Some(_)) => {
                    // Decoder must make progress on a successful decode.
                    prop_assert!(buf.len() < before);
                }
                Err(_) => break,
            }
        }
    }
}
