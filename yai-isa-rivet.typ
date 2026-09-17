#import "@preview/rivet:0.3.1": config, schema

#let source = yaml("yai-isa-rivet.yaml")

#let load-format(name) = (schema.load)((
  colors: (main: source.colors.at(name)),
  structures: (main: source.structures.at(name)),
))

#let tc-schema = load-format("tc")
#let bc-schema = load-format("bc")
#let tm-0-schema = load-format("tm-0")
#let tm-1-schema = load-format("tm-1")
#let vm-schema = load-format("vm")

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
