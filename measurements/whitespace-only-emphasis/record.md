# A run of whitespace alone takes no emphasis from its font (#278)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: the three books that carried a whitespace-only `<strong>` or `<em>` at library defaults
with `--no-ocr` — the FAA handbook, `faa-h-8083-25c.pdf`, SHA-256
`247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7`; the USCIS Arabic guide,
`M-618_a.pdf`, `354effbbe38450664959b8832d136cfd158d3c17d1ba777b8b1e4a5b6aa36d54`;
*Agricultural Research* November–December 2012, `November-December2012.pdf`.
Build: this change over `main` at `c56098e`, Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0
(26A428, Darwin 27.0.0, xnu-13432.1.9~1); release executable SHA-256
`1aae76f4eedf524de591ff80c75d2e7cae1f3ca1c47ed545a722654971a183b0`.
Baseline: `c56098e` alone, executable SHA-256
`4c5aa5e0be4833dfc16e09d35ca2ff548246cddda01c63f024994b2026fbff4c`.
Both runs at `--no-ocr` with fixed packaging (`--package-identifier`, `--modification-date`), so
the two books differ only where the reading does.

## What the markup was saying

`NativeTextReader.inlineText` gave a run `.italic` and `.bold` from its font name and asked nothing
about the run's own characters, exactly as it gave a run `.superscript` and `.subscript` from its
baseline offset before #273. A run holding only whitespace took them too, and the writer wrapped
it: `<strong> </strong>`, `<em> </em>`. The element claims emphasis over no glyph at all.

This is weaker than #273 and was kept separate from it. `<sup>` over a space states something
about the page that is false — a reader raises the space — while a bold space renders as a space.
The case here is that the markup should not claim what the page never set.

`<u>` is judged differently and is untouched: a rule the page paints under a space is ink the page
really put there (#235), and dropping it would lose evidence rather than tidy markup. No corpus
case produces one; `emphasisOverAGlyphAndARulePaintedUnderASpaceBothSurvive` is the whole record
of what the library does with one.

## Before and after

Six such elements stood in the three books; none remains.

| book | `<em> </em>` | `<strong> </strong>` | `<u> </u>` |
| --- | ---: | ---: | ---: |
| FAA handbook | 2 → 0 | 1 → 0 | 0 → 0 |
| USCIS Arabic guide | 0 → 0 | 1 → 0 | 0 → 0 |
| *Agricultural Research* | 1 → 0 | 1 → 0 | 0 → 0 |

Seven chapter files across the three books changed: FAA chapters 3, 9, 29 and 32, the Arabic
guide's chapter 1, and *Agricultural Research* chapters 1 and 2. **The text of all three books is
byte-identical**, tags removed — not merely the letter stream but the whitespace with it. Nothing
moved; only the markup around it did.

Two shapes account for every change. The element disappears where it stood alone:

```
-<p>make a complete circle.<em> </em>An aircraft’s speed (in knots) can
+<p>make a complete circle. An aircraft’s speed (in knots) can
```

and a trailing space leaves the span it was inside where the page set one, because the space now
reads the same as the prose beside it and is merged into it rather than into the emphasis:

```
-<strong>V<sub>LO</sub>. </strong>Landing gear operating speed.
+<strong>V<sub>LO</sub>.</strong> Landing gear operating speed.
```

Seven of the FAA glossary's V-speed entries move that way, and *Agricultural Research* moves one
(`<strong>things,” </strong>says` → `<strong>things,”</strong> says`) and one link's opening space
(`<a …><em> dennis.obrien@…` → `<a …> <em>dennis.obrien@…`). The rendered space is the same space
in the same place in every one of them.

The FAA handbook's nine `<sub><strong> </strong></sub>` elements collapse whole once the inner
run's style is dropped, which is what #278 predicted: the shape is a space and nothing else.

## Coverage

`aRunHoldingOnlyWhitespaceTakesNoEmphasisFromItsFont` holds the three books' shapes run by run,
and every kind of whitespace a page can set between two words — a tab, a non-breaking space, a
figure space and the placeholder an image attachment leaves behind.
`emphasisOverAGlyphAndARulePaintedUnderASpaceBothSurvive` is the positive control: emphasis over
a run of glyphs keeps every style its font names, whitespace beside a glyph in the same run is
that run's own, and a painted rule under a space survives with the font's emphasis dropped from
under it. `aPageThatSetsOnlyASpaceInBoldReachesTheEPUBWithThatSpaceAndNoEmphasis` converts a real
PDF that sets one space in a bold font between two upright clauses and checks the space is kept.
