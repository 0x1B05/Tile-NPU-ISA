#import "@preview/tablem:0.3.0": tablem

#let setup(body) = {
  set document(
    title: "Tile NPU 指令集手册",
    author: "Yanqihu-AICore 设计组",
    keywords: ("Tile NPU", "Yanqihu-AICore", "Tile ISA"),
  )
  set page(
    paper: "a4",
    margin: (top: 24mm, bottom: 22mm, left: 24mm, right: 20mm),
    numbering: "1",
  )
  set text(
    font: ("Tex Gyre Termes", "Noto Serif CJK SC"),
    size: 10.5pt,
    lang: "zh",
  )
  set par(justify: true, leading: 0.72em)
  set heading(numbering: "1.1")
  // Every top-level chapter starts on a fresh page, as in the reference ISA manuals.
  show heading.where(level: 1): it => {
    pagebreak()
    block(above: 1.2em, below: 0.9em)[#it]
  }
  show heading.where(level: 2): it => block(above: 0.9em, below: 0.7em)[#it]
  body
}

#let important = block.with(
  fill: rgb("f3f6fa"),
  stroke: (left: 3pt + rgb("446e9b")),
  inset: 9pt,
  radius: 2pt,
)
#let warning = block.with(
  fill: rgb("fff8e8"),
  stroke: (left: 3pt + rgb("b27a18")),
  inset: 9pt,
  radius: 2pt,
)
#let note = block.with(
  fill: rgb("f0f7f2"),
  stroke: (left: 3pt + rgb("3d8a4f")),
  inset: 9pt,
  radius: 2pt,
)
#let example = block.with(
  fill: rgb("f7f7f7"),
  stroke: (left: 3pt + luma(160)),
  inset: 9pt,
  radius: 2pt,
)

#let yai-table-counter = counter("yai-table")
#let captioned-table(body, caption: none) = if caption == none {
  body
} else {
  yai-table-counter.step()
  block(width: 100%, above: 0.9em, below: 0.4em)[
    #context align(center)[#text(
      size: 9pt,
    )[表 #yai-table-counter.display()　#caption]]
  ]
  body
}

// Markdown-style rows, with Typst content inside each cell:
// #manual-table(columns: (1fr, 2fr), caption: [示例])[
//   | 名称 | 容量 |
//   | --- | --- |
//   | `v0` | $32 times 32$ bit |
// ]
// Keep each row on one source line; use #linebreak() inside a cell.
#let manual-table(
  columns: auto,
  caption: none,
  inset: 5pt,
  stroke: 0.4pt + luma(190),
  body,
) = {
  set par(justify: false)

  let render = table.with(
    inset: inset,
    stroke: stroke,
    fill: (_, y) => if y == 0 { rgb("e9f0f7") },
    align: (_, y) => if y == 0 { center } else { left },
  )

  captioned-table(
    tablem(render: render, columns: columns, body),
    caption: caption,
  )
}

// Markdown columns: Instruction | Format | Operation | Notes.
#let instruction-table = manual-table.with(
  columns: (2.1fr, 0.5fr, 2.5fr, 2.1fr),
  inset: 4pt,
  stroke: 0.35pt + luma(195),
)

// Markdown columns: Instruction | Format | Function | Summary.
// Write one instruction per row; names/functions are no longer expanded from arrays.
#let instruction-listing = manual-table.with(
  columns: (1.6fr, 0.6fr, 2.7fr, 2.5fr),
  inset: 3.5pt,
  stroke: 0.35pt + luma(195),
)
