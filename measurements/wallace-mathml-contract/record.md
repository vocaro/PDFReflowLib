# Wallace MathML source review (#206)

The source is Tyler Wallace's *Beginning and Intermediate Algebra*, SHA-256
`856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678`.
Physical PDF pages 12 and 347 were rendered at 120 DPI and compared with the complete
quiet-lane EPUB at
`/private/tmp/pdfreflow-footprint-244-quiet-20260924/wallace-algebra-2010/wallace-algebra-2010.epub`
(SHA-256 `11c4c3d0706d5a1ff3118f29817d594232fa685c7d5d0f697a6054df83fffbef`).

Page 12 prints Example 15's `36/84`, `(36 ÷ 4)/(84 ÷ 4)` and `9/21` as three
stacked fractions beside two prose notes. All three are source-matching MathML
`mfrac` elements in the EPUB, each with an `altimg` reference to an existing PNG.
Page 347 prints forty numbered quadratic exercises in two columns. The output has
forty MathML expressions with existing fallback PNGs. The previous preserved-image
reference for exercise 35 shows `−5n² − 3n − 52 = 2 − 7n²`; the EPUB's exercise 35
has exactly this accessible `alttext` and two `msup(mi(n),mn(2))` subtrees in the
correct equation order. The source reference remains at
`corpus/references/wallace-algebra-2010/page-347-exercise-35.png`.

The former `minimumImages` and `imageRegions` checks on these two pages counted
visible `<img>` elements. MathML's `altimg` assets are packaged fallbacks rather
than visible images, so those checks fail even though the source structures are
preserved. The replacement `math` contract checks exact ordered MathML content,
accessible `alttext`, and that the fallback target exists. It does **not** test
how a second reading system renders the MathML or uses `altimg`; that is still a
separate #206 acceptance item.

The page-347 check covers exercise 35, not all forty equations. The EPUB still
reads the odd-numbered column before the even-numbered column on this page, a
separate Wallace exercise-order gap tracked by #29/#219; this contract does not
approve that order. Page 12's fraction rows are separate paragraphs around an
equality sign, so this record also does not qualify the complete worked-example
layout there.

Verification on the frozen full EPUB:

```sh
python3 tools/check_corpus_content.py --case wallace-algebra-2010 \
  --evaluation /private/tmp/pdfreflow-footprint-244-quiet-20260924/wallace-algebra-2010
```

The result passed all 36 Wallace content checks after the contract update.
`PYTHONPATH=tools python3 -m unittest tools.test_corpus_content -q` passed 34
tests, including wrong MathML node/order, wrong `alttext`, missing fallback,
and wrong-page negative controls. The complete 489-page EPUB passed EPUBCheck
during the quiet-lane conversion; its host-memory gate was unmeasured because
of pressure and is unrelated to this content review.
