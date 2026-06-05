# Commissioning Policy

This project uses an operator-owned step-test commissioning model.

The tools may upload generated TP programs after local evidence passes under
`config\commissioning-policy.psd1`. Upload is staging only. Upload does not
approve automatic operation, select the program, start the program, validate the
robot-side setup, or approve production use.

The operator owns:

- pendant selection and execution
- deadman control
- low-speed first run
- step-by-step verification
- PR, frame, tool, payload, and controller setup
- final judgment about whether a path or sequence is safe to run

The tooling owns:

- structured spec validation
- cell-map resource allowlist enforcement
- static LS safety checks
- MakeTP compile
- PrintTP round-trip/decode evidence
- upload and readback evidence

Do not ask for repeated pendant-review approval just to upload a program whose
resources are already covered by the active project policy and whose local
evidence passed. If a robot-facing generated TP is changed or regenerated,
upload it every time after local evidence passes so the pendant review target
matches the current source. A successful upload command must also perform fresh
robot readback, hash-compare the readback TP against the local compiled TP,
decode the readback copy, and refresh the job manifest. Stale readback evidence
is a deployment defect.

Still require an explicit project policy decision before widening authority for:

- new motion templates
- new `RUN` targets or async-task ownership rules
- new generated `CALL` targets
- writes outside the current register or IO allowlists
- system variable writes beyond documented project policy
- KAREL deployment beyond approved utilities
- SNPX writes outside the scratch write policy
- DCS, UOP, mastering, frame, tool, payload, or controller configuration changes
- automatic program selection or automatic program start
