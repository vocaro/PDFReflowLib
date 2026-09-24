# Wallace exercise and answer-key order (#29)

Source: Tyler Wallace, *Beginning and Intermediate Algebra* (2010), CC BY 3.0; cached
PDF SHA-256 `856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678`.
Physical source pages 347 and 438 were read against Poppler's layout extraction and the
source-only layout fixtures; the tests use the pinned source and never a converter-made fixture.

Page 347 prints two aligned columns of quadratic equations: 1, 3, ... 39 at the left and
2, 4, ... 40 at the right, in paired row order. Before this change the converter preserved
all forty MathML equations and their fallback PNGs but emitted every odd equation before
every even equation. The source has two large crops, each recognized as twenty exact
math rows. `MathRecognizer.pairedExerciseColumn` accepts only a long, evenly stepped
single column with numeric labels and no prose notes. The pipeline keeps its rows as
individual layout elements; the existing spatial order then places each left/right pair
in sequence. A changed label, short run and prose-note controls refuse the split.

Page 438 prints the chapter and section headings above the integer answer key, followed
by three columns numbered 1–21, 22–42 and 43–60. Section 0.2 and its fraction heading/answers
start below all sixty integer answers. Previously the first 21 answers appeared before
the chapter and integer headings, and section 0.2 and fractions 1–3 appeared before
integer answers 22–60. A heading band above overlapping answer columns is now read
before the gutter cut. The source-backed test requires the chapter/section/topic heading
order, the fraction title before its images, and every integer answer's exact printed value
in 1–60 order; it catches errors
that a set-of-numbers check misses. FAA prose-column and existing answer-title controls
still pass.

A bounded real EPUB was made from just those two source pages with `qpdf --empty --pages`
and `pdf-reflow --no-ocr`. The excerpt PDF's SHA-256 is
`d50a3daa38573cb54382d249ac96f8556dae8b09a1ecb5a52326b69f6b103ecc`; the EPUB
at `/private/tmp/wallace-29-347-438-final.epub` has SHA-256
`285c826ed0ae32010d18934744609b1d878653f754e1e05e2d6a3012120b0b47`.
It has two reflowed pages, no warnings, page-347 MathML labels exactly 1–40 with forty
packaged `altimg` fallbacks, and page-438 headings followed by answers 1–60 before 0.2,
then `Answers - Fractions` before the fraction images.
EPUBCheck 3.3 reports zero errors and warnings.

This increment qualifies those two source sets. The rest of #29 remains open: the
reviewed source record still calls out p16 fraction-exercise association, p479 complex
answers and p483 graph-answer association, and broader unsupported math structures need
their own verified fallback coverage. Semantic exercise-list classes are tracked in #195.
