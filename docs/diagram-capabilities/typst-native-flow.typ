#set page(width: 11in, height: 8.5in, margin: 0.45in)
#set text(font: "Arial", size: 10pt)

#let blue = rgb("#dbeafe")
#let green = rgb("#dcfce7")
#let yellow = rgb("#fef3c7")
#let red = rgb("#fee2e2")
#let ink = rgb("#243447")
#let line = rgb("#64748b")

#let node(title, body, fill: blue) = box(
  width: 2.25in,
  height: 0.82in,
  inset: 7pt,
  radius: 4pt,
  stroke: 0.8pt + line,
  fill: fill,
)[
  #text(weight: "bold", fill: ink)[#title]
  #linebreak()
  #text(size: 8pt, fill: ink)[#body]
]

#let arrow(label: none) = box(width: 0.42in, align(center + horizon)[
  #text(size: 18pt, fill: line)[→]
  #if label != none [
    #linebreak()
    #text(size: 6.5pt, fill: line)[#label]
  ]
])

#align(center)[
  #text(size: 18pt, weight: "bold")[Typst Native Layout: A_MAIN Flow Sketch]
]

#v(0.18in)

#grid(
  columns: (auto, auto, auto, auto, auto),
  rows: (auto, 0.22in, auto, 0.22in, auto),
  gutter: 0.08in,
  node("Startup", "Clear robot-held state. Preserve CNC/TI WIP.", fill: blue),
  arrow(),
  node("Start Async", "A_FSTART owns feeder. A_CSTART owns conveyor.", fill: yellow),
  arrow(),
  node("Main Loop", "Read WIP flags and run only eligible station phases.", fill: green),

  [], [], [], [], [],

  node("CNC Exchange", "Unload/load CNC when F61 or F62 indicates work.", fill: green),
  arrow(),
  node("TI Exchange", "Move part through insertion workflow.", fill: green),
  arrow(),
  node("Place Conveyor", "Release gripper-held print part, then start conveyor.", fill: green),

  [], [], [], [], [],

  node("Finish Work?", "If infeed off and CNC/TI WIP empty, exit loop.", fill: yellow),
  arrow(label: "yes"),
  node("Go Home", "Finish path must leave robot in reviewed home/perch.", fill: blue),
  arrow(label: "fault"),
  node("Alarm/Recovery", "Bounded waits raise UALM and preserve WIP state.", fill: red),
)

#v(0.3in)

#text(size: 8pt, fill: rgb("#475569"))[
  Typst is strongest as a review-packet and report layout tool. This is easy to
  render to PDF, but the diagram grammar is not as natural as PlantUML for
  program-flow thinking.
]
