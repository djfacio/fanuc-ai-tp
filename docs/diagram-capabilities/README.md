# LaTeX And Typst Diagram Capability Demo

This folder shows what document-native diagramming looks like for the same
small FANUC TP workflow sketch.

- `typst-native-flow.typ`: Typst-only layout using boxes, grid, color, and text
  arrows. This can render locally with the bundled Typst binary.
- `latex-tikz-flow.tex`: LaTeX/TikZ source. TikZ is powerful and precise, but a
  full LaTeX distribution is intentionally not installed in this workspace.
  The project-local Tectonic executable renders this example to PDF.

Rendered outputs:

- `typst-native-flow.png`
- `typst-native-flow.pdf`
- `latex-tikz-flow.png`
- `latex-tikz-flow.pdf`

Project-local tools used:

- `generated\tools\typst-0.14.2\typst-x86_64-pc-windows-msvc\typst.exe`
- `generated\tools\tectonic-0.16.9\tectonic.exe`
- `generated\tools\python-packages\pypdfium2` for PDF-to-PNG previews

Project recommendation:

- Use PlantUML for TP workflow design.
- Use Graphviz for audit diagrams.
- Use Typst for assembling reviewed diagrams, notes, and evidence into packets.
- Use LaTeX/TikZ only when publication-grade technical diagrams are worth the
  extra syntax and tooling cost.
