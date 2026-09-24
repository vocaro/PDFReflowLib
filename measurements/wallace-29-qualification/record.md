# Wallace algebra numbering and formula qualification (#29)

Source: owner-supplied *Beginning and Intermediate Algebra*, 489 physical pages, SHA-256
`856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678`.
Semantic exercise-list conversion is tracked separately in #195 by the owner's
2026-09-17 decision.

## Source-reviewed coverage

- Pages 10 and 347: two-per-row exercise numbering stays in printed row order;
  page 347 reads 1–40 and packages each equation's MathML fallback crop.
- Page 16: fraction products retain their whole numbered expressions. The source
  prints item 33 without a closing parenthesis; its whole product stays as a
  warned image crop matched to a source reference.
- Page 266: paired complex fractions read 1–22. Each number precedes its own
  expression; item 11 has nested-fraction MathML and an `altimg`, while other
  unsupported stacks use warned source crops.
- Pages 293 and 343: indexed-root working and the displayed quadratic derivation
  retain warned source image regions. The introductory `ax²` on page 343 is a
  selectable superscript.
- Page 438: the chapter/section headings precede integer answers 1–60 with their
  source-checked values, then the fractions answer heading.
- Page 479: answers 33–56 precede 9.4 and its quadratic-formula heading, followed
  by answers 1–27 in left-then-right column order. Unsupported complex roots and
  fractions remain warned source crops.
- Page 483: all 18 graph answer numbers immediately precede their own graph crop;
  the source fixture checks a distinctive coordinate in each paired crop.

Source layout fixtures and focused tests protect these associations and true
three-column answer/prose negative controls. Bounded EPUBs for the changed pages
passed EPUBCheck 3.3; page 479's cropped answers 15–18 were visually inspected for
clipping. The content contract covers these reviewed pages; it does not certify
every expression or every image in the book.

## One full-book run

Release converter built from commit `8358adb7dc8dd7a77d624a8b7549ec030c26a1e1`, binary
SHA-256 `0e0ff2c8091a209182968e6fe37e1341fec9939d31fb4c1e`. Command:

```sh
python3 tools/evaluate_real_document.py --case wallace-algebra-2010 \
  --pdf corpus/cache/Beginning_and_Intermediate_Algebra.pdf \
  --converter .build/corpus-cli/release/pdf-reflow \
  --output /private/tmp/wallace-29-full-20260924 \
  --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_content.py --case wallace-algebra-2010 \
  --evaluation /private/tmp/wallace-29-full-20260924
```

The single conversion completed all 489 pages; 482 contained reflowed text. The
35,809,457-byte EPUB has SHA-256
`db9445eb3ee844b3587f2071eba31cdb0f1e254d9eefcc11dd4de125e294e9cf`.
The structural gate, EPUBCheck (0 errors/warnings), and 256 MiB memory gate
passed; converter peak RSS was 87,408,640 bytes. The corrected Wallace content
gate passed **166 checks on 14 reviewed pages, zero errors** against this same
EPUB. `tools/test_corpus_content.py` passed 36 tests. The first content check
used an overbroad `absentText` substring that matched valid MathML tokens on page
16; `absentPreformatted` now tests detached `<pre>` stubs without rejecting that
complete MathML. No second full conversion was needed. Output and logs remain
under `/private/tmp/wallace-29-full-20260924` on the validating host.
