#import "@preview/rivet:0.3.1": config, schema

#let descriptors = yaml("descriptors.yaml")
#let formats = yaml("formats.yaml")
#let chapters = yaml("chapters.yaml")

#let load-schema(file, name, deps: ()) = (schema.load)((
  colors: (main: file.colors.at(name)),
  structures: (
    main: file.structures.at(name),
    ..deps.map(d => ((d): file.structures.at(d))).sum(default: (:)),
  ),
))

#let tc-schema = load-schema(descriptors, "tc")
#let ac-schema = load-schema(descriptors, "ac")
#let bc-schema = load-schema(descriptors, "bc")
#let tm-0-schema = load-schema(descriptors, "tm-0")
#let tm-1-schema = load-schema(descriptors, "tm-1")
#let tm-2-schema = load-schema(descriptors, "tm-2")
#let vm-schema = load-schema(descriptors, "vm")

#let fmt-r4-schema = load-schema(formats, "fmt-r4")
#let fmt-r3-schema = load-schema(formats, "fmt-r3")
#let fmt-r2-schema = load-schema(formats, "fmt-r2")
#let fmt-mr-schema = load-schema(formats, "fmt-mr")
#let fmt-i-schema = load-schema(formats, "fmt-i")
#let fmt-z-schema = load-schema(formats, "fmt-z")

#let cfg-seti-schema = load-schema(chapters, "cfg-seti")
#let cfg-setx-schema = load-schema(chapters, "cfg-setx")
#let cfg-get-schema = load-schema(chapters, "cfg-get")
#let cfg-copy-setw-schema = load-schema(chapters, "cfg-copy-setw")
#let cfg-getw-schema = load-schema(chapters, "cfg-getw")
#let m-blk-schema = load-schema(chapters, "m-blk")
#let m-gather-schema = load-schema(chapters, "m-gather")
#let m-row-schema = load-schema(chapters, "m-row", deps: ("index-imm", "index-x"))

#let fill-imm-schema = load-schema(chapters, "fill-imm-instr")
#let reg-move-schema = load-schema(chapters, "reg-move")
#let row-move-schema = load-schema(chapters, "row-move", deps: ("index-imm", "index-x"))
#let lane-move-schema = load-schema(chapters, "lane-move", deps: ("index-imm", "index-x"))
#let mma-bdot-schema = load-schema(chapters, "mma-bdot")
#let red-schema = load-schema(chapters, "red")
#let vreduce-argmax-schema = load-schema(chapters, "vreduce-argmax")
#let cvt-schema = load-schema(chapters, "cvt")
#let qnt-mat-schema = load-schema(chapters, "qnt-mat")
#let qnt-vec-schema = load-schema(chapters, "qnt-vec", deps: ("index-imm", "index-x"))
#let sys-schema = load-schema(chapters, "sys")
#let e-bin-schema = load-schema(chapters, "e-bin", deps: ("reg-b", "reg-x"))
#let e-bcast-schema = load-schema(chapters, "e-bcast")
#let e-unary-schema = load-schema(chapters, "e-unary")
#let e-cmp-schema = load-schema(chapters, "e-cmp", deps: ("reg-b", "reg-x"))
#let e-r4-schema = load-schema(chapters, "e-r4")
#let e-mask-schema = load-schema(chapters, "e-mask", deps: ("fill-imm", "fill-x"))

#let rivet-font = ("Tex Gyre Termes", "Noto Serif CJK SC")

#let make-rivet-config(bit-width, bit-height, margins: (24, 24, 24, 24)) = config.config(
  default-font-family: rivet-font,
  italic-font-family: rivet-font,
  background: white,
  text-color: black,
  link-color: luma(60),
  bit-i-color: luma(60),
  border-color: luma(80),
  bit-width: bit-width,
  bit-height: bit-height,
  margins: margins,
  left-labels: true,
  force-descs-on-side: true,
  all-bit-i: false,
  full-page: false,
)

#let rivet-compute-config = make-rivet-config(15, 25)
#let rivet-desc-config = make-rivet-config(10, 28)
#let rivet-encoding-config = make-rivet-config(26, 32)
#let rivet-format-config = make-rivet-config(30, 30, margins: (28, 28, 28, 28))

#let schema-figure(rivet-config, doc, caption: none) = figure(
  align(center, schema.render(doc, width: 100%, config: rivet-config)),
  caption: caption,
  supplement: [图],
  kind: "bits",
)

#let schema-rows-figure(rivet-config, rows, caption: none) = figure(
  block(width: 100%)[
    #for doc in rows [
      #align(center, schema.render(doc, width: 100%, config: rivet-config))
      #v(-8pt)
    ]
  ],
  caption: caption,
  supplement: [图],
  kind: "bits",
)

// Matrix descriptor figures: TM/AM split across three words.
#let rivet-tm-figure(rows, caption: none) = schema-rows-figure(rivet-desc-config, rows, caption: caption)

// BM/VM descriptor figure.
#let rivet-vm-figure(doc, caption: none) = schema-figure(rivet-desc-config, doc, caption: caption)

// Compute config register figures.
#let rivet-c-figure(doc, caption: none) = schema-figure(rivet-compute-config, doc, caption: caption)

// Per-family encoding figures in body chapters.
#let rivet-encoding-figure(doc, caption: none) = schema-figure(rivet-encoding-config, doc, caption: caption)

#let rivet-encoding-rows-figure(rows, caption: none) = schema-rows-figure(rivet-encoding-config, rows, caption: caption)

// Generic instruction format diagrams.
#let rivet-format-figure(doc, caption: none) = schema-figure(rivet-format-config, doc, caption: caption)
