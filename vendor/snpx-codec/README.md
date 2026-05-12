# snpx-codec

Local Rust SNPX/SRTP codec source for future live SNPX reads.

This project keeps the codec source here so FANUC TP generation and status tooling are self-contained. The PowerShell SNPX tools in `tools\` do not call this crate yet; they only generate and validate the read-only ASG mapping plan.

Planned integration path:

1. Build this crate as the wire codec.
2. Add a project-owned live reader that connects to TCP `60008`.
3. Program a private per-connection ASG table with `CLRASG` and `SETASG`.
4. Verify the ASG table by readback before trusting any `%R` values.
5. Emit the existing `generated\cell-status\snpx-values.json` shape.

Do not add write operations to the status snapshot path. Generated TP upload/write behavior remains gated by the manifest and review workflow.
