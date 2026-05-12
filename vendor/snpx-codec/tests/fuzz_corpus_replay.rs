//! §13.5 scenario 20: "Fuzz corpus replay: historical bug traces
//! replay cleanly."
//!
//! The nightly libfuzzer target at `fuzz/fuzz_targets/codec_decode.rs`
//! is where new crash seeds get found. When one surfaces, the
//! minimised bytes land under `tests/fuzz_corpus/` as a `.bin` file
//! so stable CI replays it on every test run — we never silently
//! re-introduce a decoder crash we've already fixed.
//!
//! An empty corpus directory (the initial state) is not an error:
//! scenario 20 is vacuously satisfied until real findings arrive.

use std::fs;
use std::path::PathBuf;

use bytes::BytesMut;
use snpx_codec::SrtpCodec;
use tokio_util::codec::Decoder;

fn corpus_dir() -> PathBuf {
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.push("tests");
    p.push("fuzz_corpus");
    p
}

/// Replay one corpus entry. Matches the loop shape of the libfuzzer
/// target: decode in a loop until the buffer drains or the decoder
/// returns an error, asserting only that no call panics.
fn replay_one(bytes: &[u8]) {
    let mut codec = SrtpCodec;
    let mut buf = BytesMut::from(bytes);
    for _ in 0..256 {
        let before = buf.len();
        match codec.decode(&mut buf) {
            Ok(None) => {
                assert_eq!(buf.len(), before, "decode(None) consumed bytes");
                break;
            }
            Ok(Some(_)) => {
                assert!(buf.len() < before, "decode(Some) must make progress");
            }
            Err(_) => break,
        }
    }
}

#[test]
fn replay_all_fuzz_corpus_entries() {
    let dir = corpus_dir();
    let mut entries: Vec<PathBuf> = Vec::new();
    if dir.exists() {
        for e in fs::read_dir(&dir).expect("read corpus dir") {
            let e = e.unwrap();
            if e.file_type().unwrap().is_file() {
                entries.push(e.path());
            }
        }
    }
    // Deterministic order so a failure points at a specific file.
    entries.sort();

    if entries.is_empty() {
        // No recorded crashes yet — scenario 20 is vacuously satisfied.
        // Print a hint so the test output makes the contract visible.
        eprintln!(
            "fuzz_corpus_replay: no entries in {} — add minimised \
             `.bin` files here to pin regressions",
            dir.display()
        );
        return;
    }

    for path in entries {
        let bytes = fs::read(&path).expect("read corpus entry");
        eprintln!(
            "fuzz_corpus_replay: {} ({} bytes)",
            path.file_name().unwrap().to_string_lossy(),
            bytes.len()
        );
        replay_one(&bytes);
    }
}
