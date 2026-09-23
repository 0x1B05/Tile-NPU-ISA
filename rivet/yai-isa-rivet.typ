#import "@preview/rivet:0.3.1": config, schema

#let descriptors = yaml("descriptors.yaml")
#let formats = yaml("formats.yaml")
#let chapters = yaml("chapters.yaml")

#let load-format(file, name) = (schema.load)((
  colors: (main: file.colors.at(name)),
  structures: (main: file.structures.at(name)),
))

#let tc-schema = load-format(descriptors, "tc")
#let bc-schema = load-format(descriptors, "bc")
#let tm-0-schema = load-format(descriptors, "tm-0")
#let tm-1-schema = load-format(descriptors, "tm-1")
#let vm-schema = load-format(descriptors, "vm")

#let fmt-r4-schema = load-format(formats, "fmt-r4")
#let fmt-r3-schema = load-format(formats, "fmt-r3")
#let fmt-r2-schema = load-format(formats, "fmt-r2")
#let fmt-mr-schema = load-format(formats, "fmt-mr")
#let fmt-rb-schema = load-format(formats, "fmt-rb")
#let fmt-i-schema = load-format(formats, "fmt-i")
#let fmt-z-schema = load-format(formats, "fmt-z")

#let cfg-seti-schema = load-format(chapters, "cfg-seti")
#let cfg-reg-schema = load-format(chapters, "cfg-reg")
#let m-blk-schema = load-format(chapters, "m-blk")
#let m-row-schema = load-format(chapters, "m-row")

#let init-fill-schema = load-format(chapters, "init-fill")
#let init-move-schema = load-format(chapters, "init-move")
#let row-move-schema = load-format(chapters, "row-move")
#let lane-move-schema = load-format(chapters, "lane-move")
#let mma-bdot-schema = load-format(chapters, "mma-bdot")
#let red-schema = load-format(chapters, "red")
#let vreduce-argmax-schema = load-format(chapters, "vreduce-argmax")
#let cvt-schema = load-format(chapters, "cvt")
#let qnt-schema = load-format(chapters, "qnt")
#let sys-schema = load-format(chapters, "sys")
#let e-bin-schema = load-format(chapters, "e-bin")
#let e-bcast-schema = load-format(chapters, "e-bcast")
#let e-brow-schema = load-format(chapters, "e-brow")
#let e-unary-schema = load-format(chapters, "e-unary")
#let e-cmp-schema = load-format(chapters, "e-cmp")
#let e-r4-schema = load-format(chapters, "e-r4")
#let e-mask-schema = load-format(chapters, "e-mask")

// Light background instead of the rivet blueprint preset's dark blue.
#let rivet-c-config = config.config(
  default-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  italic-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  background: white,
  text-color: black,
  link-color: luma(60),
  bit-i-color: luma(60),
  border-color: luma(80),
  bit-width: 15,
  bit-height: 25,
  margins: (24, 24, 24, 24),
  left-labels: true,
  force-descs-on-side: true,
  all-bit-i: false,
  full-page: false,
)

#let rivet-tm-config = config.config(
  default-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  italic-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  background: white,
  text-color: black,
  link-color: luma(60),
  bit-i-color: luma(60),
  border-color: luma(80),
  bit-width: 8,
  bit-height: 28,
  margins: (24, 24, 24, 24),
  left-labels: true,
  force-descs-on-side: true,
  all-bit-i: false,
  full-page: false,
)

#let rivet-128-config = config.config(
  default-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  italic-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  background: white,
  text-color: black,
  link-color: luma(60),
  bit-i-color: luma(60),
  border-color: luma(80),
  bit-width: 10,
  bit-height: 28,
  margins: (24, 24, 24, 24),
  left-labels: true,
  force-descs-on-side: true,
  all-bit-i: false,
  full-page: false,
)

#let rivet-tm-figure(rows, caption: none) = figure(
  block(width: 100%)[
    #for doc in rows [
      #align(center, schema.render(doc, width: 100%, config: rivet-128-config))
      #v(-8pt)
    ]
  ],
  caption: caption,
  supplement: [图],
  kind: "bits",
)
#let rivet-vm-figure(doc, caption: none) = figure(
  align(center, schema.render(doc, width: 100%, config: rivet-128-config)),
  caption: caption,
  supplement: [图],
  kind: "bits",
)
#let rivet-c-figure(doc, caption: none) = figure(
  align(center, schema.render(doc, width: 100%, config: rivet-c-config)),
  caption: caption,
  supplement: [图],
  kind: "bits",
)

// Per-family encoding plates in body chapters: roomier than the config-register figures.
#let rivet-fmt-config = config.config(
  default-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  italic-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  background: white,
  text-color: black,
  link-color: luma(60),
  bit-i-color: luma(60),
  border-color: luma(80),
  bit-width: 26,
  bit-height: 32,
  margins: (24, 24, 24, 24),
  left-labels: true,
  force-descs-on-side: true,
  all-bit-i: false,
  full-page: false,
)

#let rivet-fmt-figure(doc, caption: none) = figure(
  align(center, schema.render(doc, width: 100%, config: rivet-fmt-config)),
  caption: caption,
  supplement: [图],
  kind: "bits",
)

// Encoding plates: full 32-bit instruction word on a portrait page.
// Square bits, matching the proportions of the rivet RISC-V example.
#let rivet-plate-config = config.config(
  default-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  italic-font-family: ("Tex Gyre Termes", "Noto Serif CJK SC"),
  background: white,
  text-color: black,
  link-color: luma(60),
  bit-i-color: luma(60),
  border-color: luma(80),
  bit-width: 30,
  bit-height: 30,
  margins: (28, 28, 28, 28),
  left-labels: true,
  force-descs-on-side: true,
  all-bit-i: false,
  full-page: false,
)

#let rivet-plate-figure(doc, caption: none) = figure(
  align(center, schema.render(doc, width: 100%, config: rivet-plate-config)),
  caption: caption,
  supplement: [图],
  kind: "bits",
)
