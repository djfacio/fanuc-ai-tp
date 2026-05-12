# Golden byte vectors

These binary files are derived from wire captures in
[Booozie-Z/Fanuc_GESRTP_Driver](https://github.com/Booozie-Z/Fanuc_GESRTP_Driver),
distributed under the MIT License. See `NOTICE` at the crate root for the
full attribution.

Each file is a single SRTP frame (56-byte header + optional extended payload).
See `tests/golden_vectors.rs` for how each file maps to a specific capture row.
